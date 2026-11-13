//! Replay protection: a timestamp window plus the ids seen inside it.

use std::collections::HashMap;

use crate::BridgeError;

pub struct ReplayGuard {
    window_ms: i64,
    seen: HashMap<String, i64>,
}

impl ReplayGuard {
    pub fn new(window_ms: i64) -> Self {
        Self {
            window_ms,
            seen: HashMap::new(),
        }
    }

    /// Accepts `id` once, and only if `ts` is within the window of `now`.
    pub fn check(&mut self, id: &str, ts: i64, now: i64) -> Result<(), BridgeError> {
        if (now - ts).abs() > self.window_ms {
            return Err(BridgeError::Stale);
        }
        let window = self.window_ms;
        self.seen.retain(|_, seen_at| now - *seen_at <= 2 * window);
        if self.seen.contains_key(id) {
            return Err(BridgeError::Replay);
        }
        self.seen.insert(id.to_owned(), now);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.seen.len()
    }

    pub fn is_empty(&self) -> bool {
        self.seen.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::BridgeError;

    const NOW: i64 = 1_000_000_000;

    #[test]
    fn fresh_id_accepted() {
        let mut g = ReplayGuard::new(60_000);
        assert_eq!(g.check("a", NOW, NOW), Ok(()));
    }

    #[test]
    fn replay_same_id_rejected() {
        let mut g = ReplayGuard::new(60_000);
        g.check("a", NOW, NOW).unwrap();
        assert_eq!(g.check("a", NOW, NOW + 10), Err(BridgeError::Replay));
    }

    #[test]
    fn stale_ts_rejected() {
        let mut g = ReplayGuard::new(60_000);
        assert_eq!(g.check("a", NOW - 60_001, NOW), Err(BridgeError::Stale));
    }

    #[test]
    fn future_ts_rejected() {
        let mut g = ReplayGuard::new(60_000);
        assert_eq!(g.check("a", NOW + 60_001, NOW), Err(BridgeError::Stale));
    }

    #[test]
    fn old_ids_forgotten_after_window() {
        let mut g = ReplayGuard::new(60_000);
        g.check("a", NOW, NOW).unwrap();
        g.check("b", NOW + 130_000, NOW + 130_000).unwrap();
        assert_eq!(g.len(), 1);
    }
}
