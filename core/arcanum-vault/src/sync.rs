//! Client side of sync. Transport-agnostic: the HTTP client lives in
//! `arcanum-sync` and plugs in through [`SyncTransport`].
//!
//! Conflict policy, per item:
//! - an edit always beats a delete;
//! - two edits: the most recent (`updated_at`) wins and the other version
//!   is kept as a new item titled "… (conflitto)", so nothing is lost;
//! - identical content is not a conflict.
//!
//! When the server was restored from a backup (its epoch changed, or our
//! cursor is ahead of it) the device resyncs: it pulls everything again and
//! compares revisions item by item. The higher revision wins, items the
//! server lost are pushed again, and only edits made on both sides at the
//! same revision go through the conflict policy above. Every device does
//! this, so the changes each one made after the backup end up on the
//! server without stale copies overwriting newer ones.

use arcanum_proto::limits::MAX_PUSH_ITEMS;
use arcanum_proto::{ItemRecord, PullResponse, PushItem, PushRequest, PushResponse};

use crate::store::ItemRow;
use crate::vault::{
    decrypt_data, encrypt_row, next_revision, unwrap_item_key, Session, META_RESYNC,
    META_SYNC_CURSOR, META_SYNC_EPOCH,
};
use crate::{ItemData, Result, Vault, VaultError};

const MAX_ROUNDS: usize = 5;
const CONFLICT_SUFFIX: &str = " (conflitto)";

pub trait SyncTransport {
    fn pull(&mut self, since: i64) -> Result<PullResponse>;
    fn push(&mut self, request: &PushRequest) -> Result<PushResponse>;
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SyncReport {
    /// Remote changes applied locally.
    pub pulled: u32,
    /// Local changes accepted by the server.
    pub pushed: u32,
    /// Items edited on both sides since the last sync.
    pub conflicts: u32,
}

impl Vault {
    pub fn sync(&mut self, transport: &mut dyn SyncTransport) -> Result<SyncReport> {
        match self.sync_rounds(transport) {
            Err(VaultError::ServerRestored) => {
                // Pull everything again; the epoch seen next is recorded as
                // current. The flag survives an interrupted resync.
                let vault_id = self.session()?.vault_id.clone();
                self.store.transaction(|s| {
                    s.delete_meta(META_SYNC_CURSOR)?;
                    s.delete_meta(META_SYNC_EPOCH)?;
                    s.set_meta(META_RESYNC, &[1])?;
                    s.forget_server_revisions(&vault_id)
                })?;
                self.sync_rounds(transport)
            }
            other => other,
        }
    }

    fn sync_rounds(&self, transport: &mut dyn SyncTransport) -> Result<SyncReport> {
        let session = self.session()?;
        let mut report = SyncReport::default();

        for _ in 0..MAX_ROUNDS {
            let resync = self.store.get_meta(META_RESYNC)?.is_some();
            self.pull_all(session, transport, resync, &mut report)?;
            if resync {
                // Flag cleared last: if interrupted, the next sync redoes it.
                self.store.mark_missing_on_server(&session.vault_id)?;
                self.store.delete_meta(META_RESYNC)?;
            }
            if !self.push_dirty(session, transport, &mut report)? {
                return Ok(report);
            }
        }
        Err(VaultError::Transport(
            "sync did not converge, try again".into(),
        ))
    }

    fn pull_all(
        &self,
        session: &Session,
        transport: &mut dyn SyncTransport,
        resync: bool,
        report: &mut SyncReport,
    ) -> Result<()> {
        loop {
            let since = self.cursor()?;
            let page = transport.pull(since)?;
            self.check_epoch(&page.epoch)?;
            for record in page.items {
                if resync {
                    self.resync_remote(session, record, report)?;
                } else {
                    self.merge_remote(session, record, report)?;
                }
            }
            self.store
                .set_meta(META_SYNC_CURSOR, &page.cursor.to_le_bytes())?;
            if !page.has_more {
                return Ok(());
            }
        }
    }

    /// Returns true if the server reported conflicts (another round needed).
    fn push_dirty(
        &self,
        session: &Session,
        transport: &mut dyn SyncTransport,
        report: &mut SyncReport,
    ) -> Result<bool> {
        let dirty = self.store.dirty_items(&session.vault_id)?;
        let mut had_conflicts = false;
        for chunk in dirty.chunks(MAX_PUSH_ITEMS) {
            let request = PushRequest {
                items: chunk
                    .iter()
                    .map(|row| PushItem {
                        base_revision: row.server_revision,
                        item: to_record(row),
                    })
                    .collect(),
            };
            let response = transport.push(&request)?;
            for id in &response.accepted {
                if let Some(row) = chunk.iter().find(|r| &r.id == id) {
                    self.store.mark_synced(id, row.revision)?;
                    report.pushed += 1;
                }
            }
            had_conflicts |= !response.conflicts.is_empty();
            for record in response.conflicts {
                self.merge_remote(session, record, report)?;
            }
        }
        Ok(had_conflicts)
    }

    fn merge_remote(
        &self,
        session: &Session,
        record: ItemRecord,
        report: &mut SyncReport,
    ) -> Result<()> {
        if record.vault_id != session.vault_id {
            return Ok(()); // not a vault this device knows (yet)
        }
        let remote = from_record(record);
        let Some(local) = self.store.get_item(&remote.id)? else {
            report.pulled += 1;
            return self.store.put(&remote);
        };

        if !local.dirty {
            if remote.revision > local.revision {
                report.pulled += 1;
                self.store.put(&remote)?;
            }
            return Ok(());
        }
        // Local has unpushed changes. If the server copy is the one we
        // started from (or older), our push will simply apply.
        if local
            .server_revision
            .is_some_and(|base| remote.revision <= base)
        {
            return Ok(());
        }
        self.resolve_conflict(session, local, remote, report)
    }

    /// Merge rule while resyncing, when no item has a known server base.
    fn resync_remote(
        &self,
        session: &Session,
        record: ItemRecord,
        report: &mut SyncReport,
    ) -> Result<()> {
        if record.vault_id != session.vault_id {
            return Ok(());
        }
        let remote = from_record(record);
        let Some(local) = self.store.get_item(&remote.id)? else {
            report.pulled += 1;
            return self.store.put(&remote);
        };
        if remote.revision < local.revision {
            // The server is behind: send ours on top of its copy.
            return self
                .store
                .set_server_revision(&local.id, remote.revision, true);
        }
        if !local.dirty && remote.revision > local.revision {
            report.pulled += 1;
            return self.store.put(&remote);
        }
        if !local.dirty && remote.ciphertext == local.ciphertext {
            return self
                .store
                .set_server_revision(&local.id, remote.revision, false);
        }
        // Same revision with other content (another device edited the
        // restored copy), or an unsent local edit against a server copy at
        // least as new: a real concurrent edit.
        self.resolve_conflict(session, local, remote, report)
    }

    fn resolve_conflict(
        &self,
        session: &Session,
        local: ItemRow,
        remote: ItemRow,
        report: &mut SyncReport,
    ) -> Result<()> {
        let local_data = decrypt_data(session, &local)?;
        // A remote copy we can't decrypt is corrupt or forged: keep ours.
        let Ok(remote_data) = decrypt_data(session, &remote) else {
            return self.rebase(session, &local, local_data.as_ref(), &remote);
        };

        if local_data == remote_data {
            return self.store.put(&remote);
        }
        report.conflicts += 1;
        match (local_data, remote_data) {
            (None, _) => {
                report.pulled += 1;
                self.store.put(&remote)
            }
            (Some(l), None) => self.rebase(session, &local, Some(&l), &remote),
            (Some(l), Some(r)) => {
                if local.updated_at > remote.updated_at {
                    self.rebase(session, &local, Some(&l), &remote)?;
                    self.keep_copy(session, r)
                } else {
                    report.pulled += 1;
                    self.store.put(&remote)?;
                    self.keep_copy(session, l)
                }
            }
        }
    }

    /// Re-encrypts the local version on top of the server's revision so the
    /// next push is accepted.
    fn rebase(
        &self,
        session: &Session,
        local: &ItemRow,
        data: Option<&ItemData>,
        remote: &ItemRow,
    ) -> Result<()> {
        let item_key = unwrap_item_key(session, local)?;
        let mut row = encrypt_row(
            session,
            local.id.clone(),
            next_revision(remote.revision)?,
            local.wrapped_key.clone(),
            &item_key,
            data,
            local.updated_at,
        )?;
        row.server_revision = Some(remote.revision);
        self.store.put(&row)
    }

    fn keep_copy(&self, session: &Session, mut data: ItemData) -> Result<()> {
        data.title.push_str(CONFLICT_SUFFIX);
        self.insert_new(session, &data)?;
        Ok(())
    }

    /// Remembers the server's epoch; a different one means the server was
    /// restored and everything must be synced again.
    fn check_epoch(&self, epoch: &str) -> Result<()> {
        if epoch.is_empty() {
            return Ok(()); // server without epochs
        }
        let known = self.store.get_meta(META_SYNC_EPOCH)?;
        if known.as_deref() == Some(epoch.as_bytes()) {
            return Ok(());
        }
        self.store.set_meta(META_SYNC_EPOCH, epoch.as_bytes())?;
        // The first epoch seen (new link or app update) is just recorded.
        match known {
            None => Ok(()),
            Some(_) => Err(VaultError::ServerRestored),
        }
    }

    fn cursor(&self) -> Result<i64> {
        Ok(match self.store.get_meta(META_SYNC_CURSOR)? {
            Some(bytes) => i64::from_le_bytes(
                bytes
                    .try_into()
                    .map_err(|_| VaultError::Corrupt("sync cursor"))?,
            ),
            None => 0,
        })
    }
}

fn to_record(row: &ItemRow) -> ItemRecord {
    ItemRecord {
        id: row.id.clone(),
        vault_id: row.vault_id.clone(),
        revision: row.revision,
        wrapped_key: row.wrapped_key.clone(),
        ciphertext: row.ciphertext.clone(),
        deleted: row.deleted,
        updated_at: row.updated_at,
    }
}

/// A server record as a clean (already synced) local row.
fn from_record(r: ItemRecord) -> ItemRow {
    ItemRow {
        server_revision: Some(r.revision),
        id: r.id,
        vault_id: r.vault_id,
        revision: r.revision,
        wrapped_key: r.wrapped_key,
        ciphertext: r.ciphertext,
        deleted: r.deleted,
        updated_at: r.updated_at,
        dirty: false,
    }
}
