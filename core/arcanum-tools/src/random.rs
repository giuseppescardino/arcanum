use rand_core::{OsRng, RngCore};

/// Uniform integer in `0..n` from the OS CSPRNG, by rejection sampling
/// (plain `% n` would bias small values).
pub fn below(n: usize) -> usize {
    assert!(n > 0 && u32::try_from(n).is_ok(), "range must fit in u32");
    let n = n as u32;
    let zone = u32::MAX - (u32::MAX % n);
    loop {
        let v = OsRng.next_u32();
        if v < zone {
            return (v % n) as usize;
        }
    }
}

/// Fisher–Yates shuffle with [`below`].
pub fn shuffle<T>(items: &mut [T]) {
    for i in (1..items.len()).rev() {
        items.swap(i, below(i + 1));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn below_stays_in_range_and_covers_it() {
        let mut seen = [false; 7];
        for _ in 0..2000 {
            let v = below(7);
            assert!(v < 7);
            seen[v] = true;
        }
        assert!(seen.iter().all(|s| *s));
    }

    #[test]
    fn shuffle_is_a_permutation() {
        let mut v: Vec<u32> = (0..50).collect();
        shuffle(&mut v);
        let mut sorted = v.clone();
        sorted.sort_unstable();
        assert_eq!(sorted, (0..50).collect::<Vec<_>>());
    }
}
