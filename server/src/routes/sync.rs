//! Item sync. The server orders changes with a global sequence (the pull
//! cursor) and applies pushes with optimistic concurrency on `revision`.

use std::collections::HashSet;

use arcanum_proto::limits::{MAX_CIPHERTEXT_BYTES, MAX_PULL_ITEMS, MAX_PUSH_ITEMS};
use arcanum_proto::{ItemRecord, PullResponse, PushRequest, PushResponse};
use axum::extract::{Query, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::AuthSession;
use crate::error::{ApiError, ApiResult};
use crate::{validate, AppState};

const MAX_WRAPPED_KEY_BYTES: usize = 1024;

#[derive(Deserialize)]
pub struct PullQuery {
    #[serde(default)]
    since: i64,
}

#[derive(sqlx::FromRow)]
struct ItemRow {
    id: Uuid,
    vault_id: Uuid,
    revision: i64,
    wrapped_key: Vec<u8>,
    ciphertext: Vec<u8>,
    deleted: bool,
    updated_at: i64,
    seq: i64,
}

#[derive(sqlx::FromRow)]
struct LockedItemRow {
    #[sqlx(flatten)]
    item: ItemRow,
    account_id: Uuid,
}

impl ItemRow {
    fn into_record(self) -> ApiResult<ItemRecord> {
        Ok(ItemRecord {
            id: self.id.to_string(),
            vault_id: self.vault_id.to_string(),
            revision: u64::try_from(self.revision)
                .map_err(|_| ApiError::internal("negative revision in database"))?,
            wrapped_key: self.wrapped_key,
            ciphertext: self.ciphertext,
            deleted: self.deleted,
            updated_at: self.updated_at,
        })
    }
}

pub async fn pull(
    auth: AuthSession,
    State(s): State<AppState>,
    Query(q): Query<PullQuery>,
) -> ApiResult<Json<PullResponse>> {
    // A cursor the sequence never reached means the database was restored
    // to an older state: the client would silently miss new changes.
    let last_seq: i64 =
        sqlx::query_scalar("SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM item_seq")
            .fetch_one(&s.pool)
            .await?;
    if q.since > last_seq {
        return Err(ApiError::cursor_ahead());
    }

    let mut rows: Vec<ItemRow> = sqlx::query_as(
        "SELECT i.id, i.vault_id, i.revision, i.wrapped_key, i.ciphertext, i.deleted, i.updated_at, i.seq
         FROM items i JOIN vaults v ON v.id = i.vault_id
         WHERE v.account_id = $1 AND i.seq > $2
         ORDER BY i.seq
         LIMIT $3",
    )
    .bind(auth.account_id)
    .bind(q.since)
    .bind(MAX_PULL_ITEMS + 1)
    .fetch_all(&s.pool)
    .await?;

    let limit = usize::try_from(MAX_PULL_ITEMS).unwrap_or(usize::MAX);
    let has_more = rows.len() > limit;
    rows.truncate(limit);
    let cursor = rows.last().map_or(q.since, |r| r.seq);
    let items = rows
        .into_iter()
        .map(ItemRow::into_record)
        .collect::<ApiResult<Vec<_>>>()?;
    Ok(Json(PullResponse {
        items,
        cursor,
        has_more,
        epoch: s.sync_epoch.to_string(),
    }))
}

pub async fn push(
    auth: AuthSession,
    State(s): State<AppState>,
    Json(req): Json<PushRequest>,
) -> ApiResult<Json<PushResponse>> {
    if req.items.len() > MAX_PUSH_ITEMS {
        return Err(ApiError::bad_request("too many items in one push"));
    }

    let mut tx = s.pool.begin().await?;
    // Serialize pushes per account so `seq` order equals commit order and
    // a concurrent pull can never skip a change.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(auth.account_id.to_string())
        .execute(&mut *tx)
        .await?;
    let vaults: HashSet<Uuid> = sqlx::query_scalar("SELECT id FROM vaults WHERE account_id = $1")
        .bind(auth.account_id)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .collect();

    // Items (tombstones included) already stored for the account; new
    // inserts beyond the operator's quota are refused.
    let mut stored: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM items i JOIN vaults v ON v.id = i.vault_id WHERE v.account_id = $1",
    )
    .bind(auth.account_id)
    .fetch_one(&mut *tx)
    .await?;

    let mut response = PushResponse::default();
    for push in req.items {
        let rec = push.item;
        let id = validate::uuid(&rec.id, "item id")?;
        let vault_id = validate::uuid(&rec.vault_id, "vault id")?;
        if !vaults.contains(&vault_id) {
            return Err(ApiError::bad_request("unknown vault"));
        }
        if rec.ciphertext.len() > MAX_CIPHERTEXT_BYTES
            || rec.wrapped_key.is_empty()
            || rec.wrapped_key.len() > MAX_WRAPPED_KEY_BYTES
        {
            return Err(ApiError::bad_request("item too large or malformed"));
        }
        let revision = i64::try_from(rec.revision)
            .ok()
            .filter(|r| *r >= 1)
            .ok_or_else(|| ApiError::bad_request("invalid revision"))?;

        let current: Option<LockedItemRow> = sqlx::query_as(
            "SELECT i.id, i.vault_id, i.revision, i.wrapped_key, i.ciphertext, i.deleted,
                    i.updated_at, i.seq, v.account_id
             FROM items i JOIN vaults v ON v.id = i.vault_id
             WHERE i.id = $1
             FOR UPDATE OF i",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;

        match current {
            None => {
                if stored >= s.config.max_items_per_account {
                    tracing::info!(account_id = %auth.account_id, "push refused: item quota reached");
                    return Err(ApiError::quota_exceeded());
                }
                stored += 1;
                sqlx::query(
                    "INSERT INTO items (id, vault_id, revision, wrapped_key, ciphertext, deleted, updated_at, seq)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, nextval('item_seq'))",
                )
                .bind(id)
                .bind(vault_id)
                .bind(revision)
                .bind(&rec.wrapped_key)
                .bind(&rec.ciphertext)
                .bind(rec.deleted)
                .bind(rec.updated_at)
                .execute(&mut *tx)
                .await?;
                response.accepted.push(rec.id);
            }
            Some(cur) if cur.account_id != auth.account_id => {
                return Err(ApiError::bad_request("item id already in use"));
            }
            Some(cur) => {
                let base_matches = push.base_revision.and_then(|b| i64::try_from(b).ok())
                    == Some(cur.item.revision);
                if base_matches && revision > cur.item.revision && cur.item.vault_id == vault_id {
                    sqlx::query(
                        "UPDATE items SET revision = $2, wrapped_key = $3, ciphertext = $4,
                                deleted = $5, updated_at = $6, seq = nextval('item_seq')
                         WHERE id = $1",
                    )
                    .bind(id)
                    .bind(revision)
                    .bind(&rec.wrapped_key)
                    .bind(&rec.ciphertext)
                    .bind(rec.deleted)
                    .bind(rec.updated_at)
                    .execute(&mut *tx)
                    .await?;
                    response.accepted.push(rec.id);
                } else {
                    response.conflicts.push(cur.item.into_record()?);
                }
            }
        }
    }
    tx.commit().await?;
    Ok(Json(response))
}
