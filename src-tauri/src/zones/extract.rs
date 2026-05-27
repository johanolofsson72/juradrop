// Spec 005 — top-level extract dispatcher + the unified `ExtractedText` shape.
//
// The dispatcher picks the right per-format extractor based on
// `InputFormat`, then applies the shared post-processing: blank-line
// collapse (FR-002 — runs of 3+ blank lines → exactly 2) and the
// 24,000-UTF-8-character truncation cap (FR-016, inherited from
// spec 003 FR-019). Per-format extractors only need to produce the
// raw text + the format-specific flags.

use std::path::Path;

use crate::sidecar::log_safe::Redacted;

use super::errors::ZoneFailure;
use super::input_format::InputFormat;

/// FR-016 / spec 003 FR-019 — character-count proxy for ~6,000 tokens,
/// conservative for Swedish where chars-per-token is slightly higher
/// than English.
pub const TRUNCATION_CHAR_LIMIT: usize = 24_000;

/// FR-002 — runs of ≥ `BLANK_LINE_COLLAPSE_MIN` consecutive blank
/// lines collapse down to exactly `BLANK_LINE_COLLAPSE_TARGET`.
pub const BLANK_LINE_COLLAPSE_MIN: usize = 3;
pub const BLANK_LINE_COLLAPSE_TARGET: usize = 2;

/// FR-008a — the leading frontmatter block must close within the
/// first `FRONTMATTER_SCAN_BYTES` bytes; otherwise it's treated as no
/// frontmatter and the whole file is body.
pub const FRONTMATTER_SCAN_BYTES: usize = 8 * 1024;

#[derive(Debug)]
pub struct ExtractedText {
    /// The raw extracted text. Wrapped in `Redacted` so it cannot leak
    /// into `Debug` / `Display` log calls (Principle I privacy boundary).
    pub raw: Redacted<String>,
    /// Length in UTF-8 characters AFTER truncation, if any.
    pub char_count: usize,
    /// True iff the input exceeded `TRUNCATION_CHAR_LIMIT` and was
    /// truncated. The writer uses this to flip the truncation notice
    /// paragraph in the sidecar (spec 003 FR-019).
    pub was_truncated: bool,
    /// (Spec 005 FR-002a) True when PDF extraction recovered text from
    /// fewer than 100% of the source pages OR pdf-extract reported any
    /// per-page error. The docx writer prepends a Swedish partial-extraction
    /// notice when this is true. False for every non-PDF input format.
    pub was_partial: bool,
    /// (Spec 005 FR-008a) Captured Markdown frontmatter block (YAML or
    /// TOML), if the input was `.md` and a leading fenced block was
    /// found within the first 8 KB. Stored verbatim including both
    /// fences and the trailing newline. `None` for every other format.
    pub frontmatter: Option<String>,
}

/// FR-002 — collapse runs of 3+ consecutive blank lines down to
/// exactly 2 blank lines. Applied uniformly across all four formats so
/// the model sees a consistent input shape regardless of source.
///
/// Single and double blank lines pass through unchanged.
pub fn collapse_blank_lines(input: &str) -> String {
    // A "blank line" between content lines is `\n\n` — a doubled newline.
    // We want to never produce more than 3 newlines in a row (which is
    // 2 blank lines between content). Replace runs of `\n` with at most
    // 3 consecutive `\n`.
    let mut out = String::with_capacity(input.len());
    let mut run_len = 0usize;
    for ch in input.chars() {
        if ch == '\n' {
            run_len += 1;
            if run_len <= BLANK_LINE_COLLAPSE_TARGET + 1 {
                out.push(ch);
            }
            // runs longer than (target + 1) drop the extra newlines
        } else {
            run_len = 0;
            out.push(ch);
        }
    }
    out
}

/// FR-016 — truncate `text` at the first `limit` UTF-8 characters on
/// a char boundary. Returns `(possibly_truncated_text, was_truncated)`.
/// Swedish characters (å, ä, ö, é) are multi-byte; a naive byte-slice
/// would corrupt the boundary.
pub fn truncate_to_char_limit(text: String, limit: usize) -> (String, bool) {
    if text.chars().count() <= limit {
        return (text, false);
    }
    let truncated: String = text.chars().take(limit).collect();
    (truncated, true)
}

/// Top-level extractor dispatcher. Routes to the right per-format
/// extractor based on `InputFormat`, then applies the shared
/// blank-line collapse + truncation cap.
///
/// Per-format extractors return raw text (no collapse, no truncation);
/// this function owns both shared post-processing passes so every
/// format gets identical treatment.
pub fn extract_text(path: &Path, format: InputFormat) -> Result<ExtractedText, ZoneFailure> {
    match format {
        InputFormat::Docx => super::docx_extract::extract_text(path),
        InputFormat::Pdf => super::pdf_extract::extract_text(path),
        InputFormat::Txt => super::txt_extract::extract_text(path),
        InputFormat::Md => super::md_extract::extract_text(path),
    }
}

/// Helper used by every per-format extractor to finalise the
/// `ExtractedText`. Applies blank-line collapse + truncation +
/// `Redacted` wrapping in one place.
///
/// Returns `Err(ZoneFailure::EmptyText)` if the cleaned text is
/// whitespace-only — the boundary clarified in spec.md FR-004.
pub fn finalise(
    raw: String,
    was_partial: bool,
    frontmatter: Option<String>,
) -> Result<ExtractedText, ZoneFailure> {
    let collapsed = collapse_blank_lines(&raw);
    if collapsed.trim().is_empty() {
        return Err(ZoneFailure::EmptyText);
    }
    let (final_text, was_truncated) = truncate_to_char_limit(collapsed, TRUNCATION_CHAR_LIMIT);
    let char_count = final_text.chars().count();
    Ok(ExtractedText {
        raw: Redacted::new(final_text),
        char_count,
        was_truncated,
        was_partial,
        frontmatter,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collapses_three_blank_lines_to_two() {
        // Input: "a\n\n\n\nb" (3 blank lines between a and b) → output:
        // "a\n\n\nb" (2 blank lines).
        let input = "a\n\n\n\nb";
        let out = collapse_blank_lines(input);
        assert_eq!(out, "a\n\n\nb");
    }

    #[test]
    fn preserves_single_blank_line() {
        // "a\n\nb" — one blank line — should pass through unchanged.
        let input = "a\n\nb";
        assert_eq!(collapse_blank_lines(input), "a\n\nb");
    }

    #[test]
    fn preserves_double_blank_line() {
        // "a\n\n\nb" — 2 blank lines — should pass through unchanged.
        let input = "a\n\n\nb";
        assert_eq!(collapse_blank_lines(input), "a\n\n\nb");
    }

    #[test]
    fn collapses_run_of_ten_newlines() {
        let input = "a".to_string() + &"\n".repeat(10) + "b";
        let out = collapse_blank_lines(&input);
        // Expect 3 newlines (target+1) = 2 blank lines maximum.
        assert_eq!(out, "a\n\n\nb");
    }

    #[test]
    fn truncates_swedish_text_on_char_boundary() {
        // "åäö" is 3 chars, 6 bytes. Truncating at 2 chars must yield "åä",
        // not corrupt UTF-8.
        let (out, truncated) = truncate_to_char_limit("åäö".to_string(), 2);
        assert_eq!(out, "åä");
        assert!(truncated);
        assert_eq!(out.chars().count(), 2);
    }

    #[test]
    fn truncate_within_limit_returns_unchanged() {
        let (out, truncated) = truncate_to_char_limit("hi".to_string(), 100);
        assert_eq!(out, "hi");
        assert!(!truncated);
    }

    #[test]
    fn finalise_rejects_whitespace_only() {
        let result = finalise("   \n\n\t  ".to_string(), false, None);
        assert!(matches!(result, Err(ZoneFailure::EmptyText)));
    }

    #[test]
    fn finalise_carries_partial_flag() {
        let r = finalise("hello world".to_string(), true, None).unwrap();
        assert!(r.was_partial);
        assert_eq!(r.frontmatter, None);
    }

    #[test]
    fn finalise_carries_frontmatter() {
        let fm = Some("---\ntitle: x\n---\n".to_string());
        let r = finalise("body".to_string(), false, fm.clone()).unwrap();
        assert_eq!(r.frontmatter, fm);
        assert!(!r.was_partial);
    }
}
