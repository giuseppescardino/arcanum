/// Associated data builder.
///
/// Starts with a domain-separation label and appends every field with a
/// 4-byte little-endian length prefix, so `("ab", "c")` and `("a", "bc")`
/// can never produce the same bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Aad(Vec<u8>);

impl Aad {
    pub fn new(label: &str) -> Self {
        Self(Vec::with_capacity(64)).field(label.as_bytes())
    }

    pub fn field(mut self, bytes: &[u8]) -> Self {
        let len = u32::try_from(bytes.len()).unwrap_or(u32::MAX);
        self.0.extend_from_slice(&len.to_le_bytes());
        self.0.extend_from_slice(bytes);
        self
    }

    pub fn u64(self, value: u64) -> Self {
        self.field(&value.to_le_bytes())
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn length_prefix_prevents_ambiguity() {
        let a = Aad::new("t").field(b"ab").field(b"c");
        let b = Aad::new("t").field(b"a").field(b"bc");
        assert_ne!(a, b);
    }

    #[test]
    fn label_separates_domains() {
        assert_ne!(Aad::new("x").field(b"1"), Aad::new("y").field(b"1"));
    }
}
