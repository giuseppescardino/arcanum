-- All timestamps are Unix milliseconds (BIGINT).

CREATE TABLE server_config (
    key   TEXT PRIMARY KEY,
    value BYTEA NOT NULL
);

CREATE TABLE accounts (
    id            UUID PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    -- OPAQUE registration record: lets the server run the protocol, but
    -- reveals nothing usable to brute-force the password.
    opaque_record BYTEA NOT NULL,
    -- Argon2 params, salt and the Account Key wrapped by the client's MUK.
    account_keys  JSONB NOT NULL,
    created_at    BIGINT NOT NULL
);

CREATE TABLE vaults (
    id          UUID PRIMARY KEY,
    account_id  UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    wrapped_key BYTEA NOT NULL
);
CREATE INDEX vaults_account ON vaults(account_id);

CREATE SEQUENCE item_seq;

CREATE TABLE items (
    id          UUID PRIMARY KEY,
    vault_id    UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    revision    BIGINT NOT NULL,
    wrapped_key BYTEA NOT NULL,
    ciphertext  BYTEA NOT NULL,
    deleted     BOOLEAN NOT NULL,
    updated_at  BIGINT NOT NULL,
    -- Monotonic change counter used as the pull cursor.
    seq         BIGINT NOT NULL
);
CREATE INDEX items_vault_seq ON items(vault_id, seq);

CREATE TABLE sessions (
    id           UUID PRIMARY KEY,
    token_hash   BYTEA NOT NULL UNIQUE,
    account_id   UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    device_name  TEXT NOT NULL,
    created_at   BIGINT NOT NULL,
    last_used_at BIGINT NOT NULL,
    expires_at   BIGINT NOT NULL
);
CREATE INDEX sessions_account ON sessions(account_id);

-- Server half of an in-flight OPAQUE login (single use, short-lived).
CREATE TABLE pending_logins (
    id         UUID PRIMARY KEY,
    email      TEXT NOT NULL,
    state      BYTEA NOT NULL,
    expires_at BIGINT NOT NULL
);
