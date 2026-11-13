//! End-to-end tests for Arcanum live in `tests/`; this crate has no code.
//!
//! They start the `arcanum-server` binary (build it first with `cargo build`
//! in `server/`, or point `ARCANUM_SERVER_BIN` at it) against PostgreSQL
//! (`TEST_DATABASE_URL`) and drive it with the core sync client.
