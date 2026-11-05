-- Accounts are identified by `login_id` = HKDF(Secret Key, "pm/login-id/v1")
-- instead of an email: the server stores no personal identifier and the id
-- can't be guessed. The OPAQUE records were bound to the email, so existing
-- accounts can't be carried over: start from scratch.
TRUNCATE accounts, pending_logins CASCADE;
DELETE FROM server_config WHERE key = 'sync_epoch';

ALTER TABLE accounts RENAME COLUMN email TO login_id;
-- Set from the invite used to register (e.g. a name or employee number),
-- so an operator can find and remove an account; NULL on open servers.
ALTER TABLE accounts ADD COLUMN label TEXT;
ALTER TABLE pending_logins RENAME COLUMN email TO login_id;

-- Device names are encrypted by the client with the Account Key and set
-- after sign-in (a new device only gets the key once logged in).
ALTER TABLE sessions DROP COLUMN device_name;
ALTER TABLE sessions ADD COLUMN device_name BYTEA;

-- Single-use registration codes for `ARCANUM_REGISTRATION=invite`.
CREATE TABLE invites (
    id         UUID PRIMARY KEY,
    code_hash  BYTEA NOT NULL UNIQUE,
    label      TEXT,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    used_by    UUID REFERENCES accounts(id) ON DELETE SET NULL,
    used_at    BIGINT
);
