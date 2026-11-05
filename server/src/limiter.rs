//! In-memory rate limits. Good enough for a single instance; a
//! multi-instance deployment should move them to the database or the
//! reverse proxy.
//!
//! Both maps are bounded and swept at most once per sweep interval (or when
//! full), so a flood of distinct keys can neither exhaust memory nor make
//! every request scan the whole map.

use std::collections::HashMap;
use std::hash::Hash;
use std::net::IpAddr;
use std::sync::Mutex;

use crate::now_ms;

const MAX_LOGIN_FAILURES: u32 = 10;
const LOGIN_WINDOW_MS: i64 = 15 * 60 * 1000;
/// Upper bound on tracked keys per limiter.
pub const MAX_ENTRIES: usize = 100_000;
const SWEEP_INTERVAL_MS: i64 = 60 * 1000;

/// Fixed-window counters per key, bounded in size.
struct Windows<K> {
    map: HashMap<K, (u32, i64)>,
    window_ms: i64,
    max_entries: usize,
    last_sweep: i64,
}

impl<K: Eq + Hash> Windows<K> {
    fn new(window_ms: i64, max_entries: usize) -> Self {
        Self {
            map: HashMap::new(),
            window_ms,
            max_entries,
            last_sweep: 0,
        }
    }

    fn sweep_if_due(&mut self, now: i64) {
        if now - self.last_sweep >= SWEEP_INTERVAL_MS || self.map.len() >= self.max_entries {
            let window = self.window_ms;
            self.map.retain(|_, (_, start)| now - *start < window);
            self.last_sweep = now;
        }
    }

    /// Current count for `key` in its live window.
    fn count(&mut self, key: &K, now: i64) -> u32 {
        self.sweep_if_due(now);
        match self.map.get(key) {
            Some((n, start)) if now - start < self.window_ms => *n,
            _ => 0,
        }
    }

    /// Adds one to `key` and returns the new count. When the map is full of
    /// live keys a new key is not tracked (and counts as 1): failing open
    /// keeps real users in, and the other limits still apply.
    fn bump(&mut self, key: K, now: i64) -> u32 {
        self.sweep_if_due(now);
        let window = self.window_ms;
        if let Some(entry) = self.map.get_mut(&key) {
            if now - entry.1 >= window {
                *entry = (0, now);
            }
            entry.0 = entry.0.saturating_add(1);
            return entry.0;
        }
        if self.map.len() >= self.max_entries {
            tracing::warn!("rate limiter full, not tracking new keys");
            return 1;
        }
        self.map.insert(key, (1, now));
        1
    }

    fn remove(&mut self, key: &K) {
        self.map.remove(key);
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.map.len()
    }
}

/// Unsuccessful login attempts per login id (an attempt counts from
/// `login/start` until a successful finish). The login id can't be guessed,
/// so this only slows down someone who stole an Emergency Kit and is now
/// guessing the master password online.
pub struct LoginLimiter {
    inner: Mutex<Windows<String>>,
}

impl Default for LoginLimiter {
    fn default() -> Self {
        Self::with_capacity(MAX_ENTRIES)
    }
}

impl LoginLimiter {
    fn with_capacity(max_entries: usize) -> Self {
        Self {
            inner: Mutex::new(Windows::new(LOGIN_WINDOW_MS, max_entries)),
        }
    }

    pub fn is_blocked(&self, login_id: &str) -> bool {
        let now = now_ms();
        self.inner
            .lock()
            .is_ok_and(|mut w| w.count(&login_id.to_owned(), now) >= MAX_LOGIN_FAILURES)
    }

    pub fn record_failure(&self, login_id: &str) {
        let now = now_ms();
        if let Ok(mut w) = self.inner.lock() {
            w.bump(login_id.to_owned(), now);
        }
    }

    pub fn reset(&self, login_id: &str) {
        if let Ok(mut w) = self.inner.lock() {
            w.remove(&login_id.to_owned());
        }
    }
}

/// Requests per client IP in a fixed window.
pub struct IpLimiter {
    limit: u32,
    inner: Mutex<Windows<IpAddr>>,
}

impl IpLimiter {
    pub fn new(limit: u32, window_ms: i64) -> Self {
        Self::with_capacity(limit, window_ms, MAX_ENTRIES)
    }

    fn with_capacity(limit: u32, window_ms: i64, max_entries: usize) -> Self {
        Self {
            limit,
            inner: Mutex::new(Windows::new(window_ms, max_entries)),
        }
    }

    /// Counts a request from `ip`; false once the limit is exceeded.
    pub fn allow(&self, ip: IpAddr) -> bool {
        self.allow_at(ip, now_ms())
    }

    fn allow_at(&self, ip: IpAddr, now: i64) -> bool {
        let key = limit_key(ip);
        self.inner
            .lock()
            .map_or(true, |mut w| w.bump(key, now) <= self.limit)
    }
}

/// IPv4 addresses are limited one by one; IPv6 ones by /64, the smallest
/// block usually assigned to a single customer (otherwise one host could
/// rotate through 2^64 addresses, each with a fresh limit).
fn limit_key(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => {
                let prefix = u128::from(v6) & !((1u128 << 64) - 1);
                IpAddr::V6(prefix.into())
            }
        },
        v4 => v4,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_after_max_failures() {
        let l = LoginLimiter::default();
        for _ in 0..MAX_LOGIN_FAILURES {
            assert!(!l.is_blocked("a"));
            l.record_failure("a");
        }
        assert!(l.is_blocked("a"));
        assert!(!l.is_blocked("other"));
        l.reset("a");
        assert!(!l.is_blocked("a"));
    }

    #[test]
    fn maps_stay_bounded() {
        let l = LoginLimiter::with_capacity(100);
        for i in 0..1000 {
            l.record_failure(&format!("id-{i}"));
        }
        assert!(l.inner.lock().unwrap().len() <= 100);
        // Keys already tracked keep counting.
        for _ in 0..MAX_LOGIN_FAILURES {
            l.record_failure("id-0");
        }
        assert!(l.is_blocked("id-0"));
    }

    #[test]
    fn windows_expire() {
        let mut w = Windows::new(1000, 10);
        assert_eq!(w.bump("k", 0), 1);
        assert_eq!(w.bump("k", 500), 2);
        assert_eq!(w.count(&"k", 999), 2);
        assert_eq!(w.count(&"k", 1000), 0);
        assert_eq!(w.bump("k", 1000), 1);
    }

    #[test]
    fn ip_limit_per_address() {
        let l = IpLimiter::with_capacity(3, 60_000, 10);
        let a: IpAddr = "192.0.2.1".parse().unwrap();
        let b: IpAddr = "192.0.2.2".parse().unwrap();
        for _ in 0..3 {
            assert!(l.allow_at(a, 0));
        }
        assert!(!l.allow_at(a, 1));
        assert!(l.allow_at(b, 1));
        assert!(l.allow_at(a, 60_000), "new window");
    }

    #[test]
    fn ipv6_is_limited_per_64() {
        let l = IpLimiter::with_capacity(2, 60_000, 10);
        let a: IpAddr = "2001:db8:1:2::1".parse().unwrap();
        let b: IpAddr = "2001:db8:1:2:ffff::9".parse().unwrap();
        let other: IpAddr = "2001:db8:1:3::1".parse().unwrap();
        assert!(l.allow_at(a, 0));
        assert!(l.allow_at(b, 0));
        assert!(!l.allow_at(a, 0), "same /64 shares the limit");
        assert!(l.allow_at(other, 0));
        let mapped: IpAddr = "::ffff:192.0.2.1".parse().unwrap();
        assert_eq!(limit_key(mapped), "192.0.2.1".parse::<IpAddr>().unwrap());
    }
}
