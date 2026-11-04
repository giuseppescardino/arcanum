//! Thin SQLite layer. Knows nothing about cryptography: it stores opaque
//! blobs and the bookkeeping needed for sync.

use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::{Result, VaultError};

/// Applied in order; `PRAGMA user_version` records how many have run.
const MIGRATIONS: &[&str] = &[
    // v1: initial schema
    "CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS vaults (
        id          TEXT PRIMARY KEY,
        wrapped_key BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS items (
        id          TEXT PRIMARY KEY,
        vault_id    TEXT NOT NULL REFERENCES vaults(id),
        revision    INTEGER NOT NULL,
        wrapped_key BLOB NOT NULL,
        ciphertext  BLOB NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        updated_at  INTEGER NOT NULL,
        dirty       INTEGER NOT NULL DEFAULT 1
    );
    CREATE INDEX IF NOT EXISTS items_vault ON items(vault_id, deleted);",
    // v2: last revision known to be on the server (base for pushes)
    "ALTER TABLE items ADD COLUMN server_revision INTEGER;",
];

const ITEM_COLUMNS: &str =
    "id, vault_id, revision, wrapped_key, ciphertext, deleted, updated_at, dirty, server_revision";

#[derive(Debug, Clone)]
pub(crate) struct ItemRow {
    pub id: String,
    pub vault_id: String,
    pub revision: u64,
    pub wrapped_key: Vec<u8>,
    pub ciphertext: Vec<u8>,
    pub deleted: bool,
    pub updated_at: i64,
    /// Changed locally since the last successful push.
    pub dirty: bool,
    pub server_revision: Option<u64>,
}

pub(crate) struct Store {
    conn: Connection,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        // secure_delete overwrites freed pages, so old ciphertexts and
        // tombstoned items don't linger in the file.
        conn.execute_batch(
            "PRAGMA foreign_keys = ON;
             PRAGMA secure_delete = ON;
             PRAGMA journal_mode = WAL;",
        )?;
        let mut store = Self { conn };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&mut self) -> Result<()> {
        let version: i64 = self
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))?;
        let version =
            usize::try_from(version).map_err(|_| VaultError::Corrupt("schema version"))?;
        if version > MIGRATIONS.len() {
            return Err(VaultError::Corrupt("vault created by a newer app version"));
        }
        for (i, sql) in MIGRATIONS.iter().enumerate().skip(version) {
            self.transaction(|s| {
                s.conn.execute_batch(sql)?;
                s.conn
                    .execute_batch(&format!("PRAGMA user_version = {}", i + 1))?;
                Ok(())
            })?;
        }
        Ok(())
    }

    pub fn get_meta(&self, key: &str) -> Result<Option<Vec<u8>>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM meta WHERE key = ?1", [key], |r| r.get(0))
            .optional()?)
    }

    pub fn set_meta(&self, key: &str, value: &[u8]) -> Result<()> {
        self.conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn delete_meta(&self, key: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM meta WHERE key = ?1", [key])?;
        Ok(())
    }

    pub fn insert_vault(&self, id: &str, wrapped_key: &[u8]) -> Result<()> {
        self.conn.execute(
            "INSERT INTO vaults (id, wrapped_key) VALUES (?1, ?2)",
            params![id, wrapped_key],
        )?;
        Ok(())
    }

    pub fn first_vault(&self) -> Result<Option<(String, Vec<u8>)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, wrapped_key FROM vaults ORDER BY rowid LIMIT 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?)
    }

    /// Records a local edit: marks the row dirty and keeps whatever
    /// `server_revision` it already had.
    pub fn upsert_local(&self, row: &ItemRow) -> Result<()> {
        self.conn.execute(
            "INSERT INTO items (id, vault_id, revision, wrapped_key, ciphertext, deleted, updated_at, dirty)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1)
             ON CONFLICT(id) DO UPDATE SET
                revision = excluded.revision,
                wrapped_key = excluded.wrapped_key,
                ciphertext = excluded.ciphertext,
                deleted = excluded.deleted,
                updated_at = excluded.updated_at,
                dirty = 1",
            params![
                row.id,
                row.vault_id,
                to_sql(row.revision)?,
                row.wrapped_key,
                row.ciphertext,
                row.deleted,
                row.updated_at
            ],
        )?;
        Ok(())
    }

    /// Writes every column as given; used by sync.
    pub fn put(&self, row: &ItemRow) -> Result<()> {
        self.conn.execute(
            "INSERT INTO items (id, vault_id, revision, wrapped_key, ciphertext, deleted, updated_at, dirty, server_revision)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                vault_id = excluded.vault_id,
                revision = excluded.revision,
                wrapped_key = excluded.wrapped_key,
                ciphertext = excluded.ciphertext,
                deleted = excluded.deleted,
                updated_at = excluded.updated_at,
                dirty = excluded.dirty,
                server_revision = excluded.server_revision",
            params![
                row.id,
                row.vault_id,
                to_sql(row.revision)?,
                row.wrapped_key,
                row.ciphertext,
                row.deleted,
                row.updated_at,
                row.dirty,
                row.server_revision.map(to_sql).transpose()?
            ],
        )?;
        Ok(())
    }

    pub fn mark_synced(&self, id: &str, revision: u64) -> Result<()> {
        self.conn.execute(
            "UPDATE items SET dirty = 0, server_revision = ?2 WHERE id = ?1 AND revision = ?2",
            params![id, to_sql(revision)?],
        )?;
        Ok(())
    }

    /// Forget all server state: every item becomes a new local change.
    /// Deletes every row: account, vaults, items and sync bookkeeping.
    pub fn wipe(&self) -> Result<()> {
        self.conn
            .execute_batch("DELETE FROM items; DELETE FROM vaults; DELETE FROM meta;")?;
        Ok(())
    }

    /// Folds the WAL into the database and truncates it, so erased pages
    /// (overwritten thanks to secure_delete) don't survive in the log.
    pub fn checkpoint(&self) -> Result<()> {
        self.conn
            .query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(()))?;
        Ok(())
    }

    pub fn reset_sync_state(&self) -> Result<()> {
        self.conn
            .execute("UPDATE items SET dirty = 1, server_revision = NULL", [])?;
        Ok(())
    }

    /// Starts a resync: no item is known to be on the server any more.
    pub fn forget_server_revisions(&self, vault_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE items SET server_revision = NULL WHERE vault_id = ?1",
            [vault_id],
        )?;
        Ok(())
    }

    /// Records which revision the server has; `dirty` if ours must be pushed.
    pub fn set_server_revision(&self, id: &str, revision: u64, dirty: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE items SET server_revision = ?2, dirty = ?3 WHERE id = ?1",
            params![id, to_sql(revision)?, dirty],
        )?;
        Ok(())
    }

    /// Ends a resync: synced items the server did not return are missing
    /// there and are pushed again.
    pub fn mark_missing_on_server(&self, vault_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE items SET dirty = 1 WHERE vault_id = ?1 AND server_revision IS NULL",
            [vault_id],
        )?;
        Ok(())
    }

    pub fn get_item(&self, id: &str) -> Result<Option<ItemRow>> {
        self.conn
            .query_row(
                &format!("SELECT {ITEM_COLUMNS} FROM items WHERE id = ?1"),
                [id],
                read_row,
            )
            .optional()?
            .transpose()
    }

    pub fn live_items(&self, vault_id: &str) -> Result<Vec<ItemRow>> {
        self.query_items(
            &format!("SELECT {ITEM_COLUMNS} FROM items WHERE vault_id = ?1 AND deleted = 0"),
            vault_id,
        )
    }

    pub fn dirty_items(&self, vault_id: &str) -> Result<Vec<ItemRow>> {
        self.query_items(
            &format!("SELECT {ITEM_COLUMNS} FROM items WHERE vault_id = ?1 AND dirty = 1"),
            vault_id,
        )
    }

    fn query_items(&self, sql: &str, vault_id: &str) -> Result<Vec<ItemRow>> {
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([vault_id], read_row)?;
        rows.map(|r| r?).collect()
    }

    pub fn transaction<T>(&mut self, f: impl FnOnce(&Store) -> Result<T>) -> Result<T> {
        self.conn.execute_batch("BEGIN IMMEDIATE")?;
        match f(self) {
            Ok(value) => {
                self.conn.execute_batch("COMMIT")?;
                Ok(value)
            }
            Err(e) => {
                let _ = self.conn.execute_batch("ROLLBACK");
                Err(e)
            }
        }
    }
}

fn read_row(r: &Row<'_>) -> rusqlite::Result<Result<ItemRow>> {
    let revision: i64 = r.get(2)?;
    let server_revision: Option<i64> = r.get(8)?;
    let row = (|| {
        Ok(ItemRow {
            id: r.get(0)?,
            vault_id: r.get(1)?,
            revision: from_sql(revision)?,
            wrapped_key: r.get(3)?,
            ciphertext: r.get(4)?,
            deleted: r.get(5)?,
            updated_at: r.get(6)?,
            dirty: r.get(7)?,
            server_revision: server_revision.map(from_sql).transpose()?,
        })
    })();
    Ok(row)
}

fn to_sql(revision: u64) -> Result<i64> {
    i64::try_from(revision).map_err(|_| VaultError::Corrupt("revision overflow"))
}

fn from_sql(revision: i64) -> Result<u64> {
    u64::try_from(revision).map_err(|_| VaultError::Corrupt("negative revision"))
}
