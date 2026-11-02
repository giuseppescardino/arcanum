use std::sync::OnceLock;

const RAW: &str = include_str!("../data/eff_large_wordlist.txt");
#[cfg(test)]
const WORD_COUNT: usize = 7776;

/// The EFF Large Wordlist (7776 words, ~12.9 bits each), parsed once.
pub fn words() -> &'static [&'static str] {
    static WORDS: OnceLock<Vec<&'static str>> = OnceLock::new();
    WORDS.get_or_init(|| {
        RAW.lines()
            .filter_map(|line| line.split_once('\t').map(|(_, w)| w.trim()))
            .collect()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_is_complete_and_unique() {
        let w = words();
        assert_eq!(w.len(), WORD_COUNT);
        let mut sorted = w.to_vec();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), WORD_COUNT);
        assert_eq!(w[0], "abacus");
        assert_eq!(w[WORD_COUNT - 1], "zoom");
    }
}
