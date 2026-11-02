//! Each session is one signed-in device; revoking it signs the device out.

use arcanum_proto::DeviceInfo;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use uuid::Uuid;

use crate::auth::AuthSession;
use crate::error::{ApiError, ApiResult};
use crate::{now_ms, validate, AppState};

pub async fn list(
    auth: AuthSession,
    State(s): State<AppState>,
) -> ApiResult<Json<Vec<DeviceInfo>>> {
    let rows: Vec<(Uuid, String, i64, i64)> = sqlx::query_as(
        "SELECT id, device_name, created_at, last_used_at FROM sessions
         WHERE account_id = $1 AND expires_at > $2
         ORDER BY last_used_at DESC",
    )
    .bind(auth.account_id)
    .bind(now_ms())
    .fetch_all(&s.pool)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|(id, name, created_at, last_used_at)| DeviceInfo {
                current: id == auth.session_id,
                id: id.to_string(),
                name,
                created_at,
                last_used_at,
            })
            .collect(),
    ))
}

pub async fn revoke(
    auth: AuthSession,
    State(s): State<AppState>,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    let id = validate::uuid(&id, "device id")?;
    let deleted = sqlx::query("DELETE FROM sessions WHERE id = $1 AND account_id = $2")
        .bind(id)
        .bind(auth.account_id)
        .execute(&s.pool)
        .await?
        .rows_affected();
    if deleted == 0 {
        return Err(ApiError::not_found());
    }
    Ok(StatusCode::NO_CONTENT)
}
