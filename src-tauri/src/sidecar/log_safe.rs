// Log-safe redaction newtype.
//
// Wrapping inference prompts and responses in Redacted<T> ensures any Debug
// or Display formatting prints `<redacted>` regardless of the inner value.
// Per FR-012 + spec.allium NoPromptOrResponseInLogs invariant + research.md R-007.

use std::fmt;

pub struct Redacted<T>(pub T);

impl<T> Redacted<T> {
    pub fn new(inner: T) -> Self {
        Self(inner)
    }

    pub fn into_inner(self) -> T {
        self.0
    }

    pub fn as_inner(&self) -> &T {
        &self.0
    }
}

impl<T: AsRef<str>> Redacted<T> {
    pub fn len(&self) -> usize {
        self.0.as_ref().len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.as_ref().is_empty()
    }
}

impl<T> fmt::Debug for Redacted<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "<redacted>")
    }
}

impl<T> fmt::Display for Redacted<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "<redacted>")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_redacts_content() {
        let s = Redacted::new(String::from("super-secret"));
        assert_eq!(format!("{}", s), "<redacted>");
    }

    #[test]
    fn debug_redacts_content() {
        let s = Redacted::new(String::from("super-secret"));
        assert_eq!(format!("{:?}", s), "<redacted>");
    }

    #[test]
    fn len_returns_inner_length() {
        let s = Redacted::new(String::from("hello"));
        assert_eq!(s.len(), 5);
    }

    #[test]
    fn into_inner_returns_original() {
        let s = Redacted::new(String::from("hello"));
        assert_eq!(s.into_inner(), "hello");
    }
}
