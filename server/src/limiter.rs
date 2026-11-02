use std::collections::HashMap;
use std::sync::Mutex;

use crate::now_ms;

const MAX_FAILURES: u32 = 10;
const WINDOW_MS: i64 = 15 * 60 * 1000;

/// In-memory counter of unsuccessful login attempts per email (an attempt
/// counts from `login/start` until a successful finish). Good enough for a single
/// instance; a multi-instance deployment should move this to the database
/// or the reverse proxy.
#[derive(Default)]
pub struct LoginLimiter {
    failures: Mutex<HashMap<String, (u32, i64)>>,
}

impl LoginLimiter {
    pub fn is_blocked(&self, email: &str) -> bool {
        let now = now_ms();
        let Ok(mut map) = self.failures.lock() else {
            return false;
        };
        map.retain(|_, (_, start)| now - *start < WINDOW_MS);
        map.get(email)
            .is_some_and(|(count, _)| *count >= MAX_FAILURES)
    }

    pub fn record_failure(&self, email: &str) {
        let now = now_ms();
        if let Ok(mut map) = self.failures.lock() {
            let entry = map.entry(email.to_owned()).or_insert((0, now));
            entry.0 += 1;
        }
    }

    pub fn reset(&self, email: &str) {
        if let Ok(mut map) = self.failures.lock() {
            map.remove(email);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_after_max_failures() {
        let l = LoginLimiter::default();
        for _ in 0..MAX_FAILURES {
            assert!(!l.is_blocked("a@b.c"));
            l.record_failure("a@b.c");
        }
        assert!(l.is_blocked("a@b.c"));
        assert!(!l.is_blocked("other@b.c"));
        l.reset("a@b.c");
        assert!(!l.is_blocked("a@b.c"));
    }
}
