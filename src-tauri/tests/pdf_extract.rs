// Spec 005 / T015 — PDF extraction integration tests.
//
// Fixtures are built in-memory via lopdf instead of checked-in binary
// files. This keeps the test suite self-contained, reproducible
// without external tools, and friendly to git diffs.

use juradrop_lib::zones::pdf_extract::extract_text_from_bytes;
use juradrop_lib::zones::ZoneFailure;
use lopdf::content::{Content, Operation};
use lopdf::{dictionary, Document, Object, Stream};

/// Build a minimal valid PDF with one page containing `text` rendered
/// at (72, 720) with the Helvetica font. The returned bytes parse
/// cleanly with `pdf-extract::extract_text_from_mem`.
fn build_text_pdf(text: &str) -> Vec<u8> {
    let mut doc = Document::with_version("1.4");

    let pages_id = doc.new_object_id();
    let font_id = doc.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "Type1",
        "BaseFont" => "Helvetica",
    });
    let resources_id = doc.add_object(dictionary! {
        "Font" => dictionary! { "F1" => font_id },
    });

    let content = Content {
        operations: vec![
            Operation::new("BT", vec![]),
            Operation::new("Tf", vec!["F1".into(), 12.into()]),
            Operation::new("Td", vec![72.into(), 720.into()]),
            Operation::new("Tj", vec![Object::string_literal(text)]),
            Operation::new("ET", vec![]),
        ],
    };
    let content_id = doc.add_object(Stream::new(dictionary! {}, content.encode().unwrap()));

    let page_id = doc.add_object(dictionary! {
        "Type" => "Page",
        "Parent" => pages_id,
        "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
        "Contents" => content_id,
        "Resources" => resources_id,
    });

    doc.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => vec![page_id.into()],
            "Count" => 1,
        }),
    );

    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);

    let mut bytes = Vec::new();
    doc.save_to(&mut bytes).expect("PDF save should not fail");
    bytes
}

/// Build a PDF with N pages, each containing a single line of text.
fn build_multi_page_pdf(per_page_text: &[&str]) -> Vec<u8> {
    let mut doc = Document::with_version("1.4");
    let pages_id = doc.new_object_id();

    let font_id = doc.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "Type1",
        "BaseFont" => "Helvetica",
    });
    let resources_id = doc.add_object(dictionary! {
        "Font" => dictionary! { "F1" => font_id },
    });

    let mut page_ids: Vec<Object> = Vec::with_capacity(per_page_text.len());
    for text in per_page_text {
        let content = Content {
            operations: vec![
                Operation::new("BT", vec![]),
                Operation::new("Tf", vec!["F1".into(), 12.into()]),
                Operation::new("Td", vec![72.into(), 720.into()]),
                Operation::new("Tj", vec![Object::string_literal(*text)]),
                Operation::new("ET", vec![]),
            ],
        };
        let content_id = doc.add_object(Stream::new(dictionary! {}, content.encode().unwrap()));
        let page_id = doc.add_object(dictionary! {
            "Type" => "Page",
            "Parent" => pages_id,
            "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
            "Contents" => content_id,
            "Resources" => resources_id,
        });
        page_ids.push(page_id.into());
    }

    let count = page_ids.len();
    doc.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => page_ids,
            "Count" => count as i32,
        }),
    );

    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);

    let mut bytes = Vec::new();
    doc.save_to(&mut bytes).expect("PDF save should not fail");
    bytes
}

/// Build a PDF with N pages but no text content streams (image-only
/// stand-in — used to exercise the NoExtractableText path).
fn build_pageless_text_pdf(page_count: usize) -> Vec<u8> {
    let mut doc = Document::with_version("1.4");
    let pages_id = doc.new_object_id();
    let resources_id = doc.add_object(dictionary! {});

    let mut page_ids: Vec<Object> = Vec::with_capacity(page_count);
    for _ in 0..page_count {
        let page_id = doc.add_object(dictionary! {
            "Type" => "Page",
            "Parent" => pages_id,
            "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
            "Resources" => resources_id,
            // No Contents key → no text content stream.
        });
        page_ids.push(page_id.into());
    }

    let count = page_ids.len();
    doc.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => page_ids,
            "Count" => count as i32,
        }),
    );

    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);

    let mut bytes = Vec::new();
    doc.save_to(&mut bytes).expect("PDF save should not fail");
    bytes
}

// ============================================================
// Tests
// ============================================================

#[test]
fn happy_path_extracts_text_from_single_page_pdf() {
    let bytes = build_text_pdf("Sammanfattning av kontrakt");
    let result = extract_text_from_bytes(&bytes).expect("happy path must succeed");
    let text = result.raw.as_inner();
    assert!(
        text.contains("Sammanfattning av kontrakt"),
        "extracted text was {text:?}"
    );
    assert!(!result.was_truncated);
    assert!(!result.was_partial); // one page, one block → not partial
    assert_eq!(result.frontmatter, None);
}

#[test]
fn multi_page_pdf_with_text_on_every_page_does_not_flag_partial() {
    let bytes = build_multi_page_pdf(&["Page one text.", "Page two text.", "Page three text."]);
    let result = extract_text_from_bytes(&bytes).expect("3-page extract must succeed");
    // Conservative heuristic: blocks_recovered must be ≥ page count
    // for was_partial to stay false. Three single-line pages should
    // produce at least 3 non-empty blocks.
    assert!(
        !result.was_partial,
        "3 text-bearing pages should not flag was_partial"
    );
}

#[test]
fn pdf_with_zero_text_content_streams_returns_no_extractable_text() {
    let bytes = build_pageless_text_pdf(2);
    let result = extract_text_from_bytes(&bytes);
    assert!(
        matches!(result, Err(ZoneFailure::NoExtractableText)),
        "image-only PDF must surface NoExtractableText, got {result:?}"
    );
}

#[test]
fn garbage_bytes_return_parse_error() {
    let result = extract_text_from_bytes(b"this is not a pdf");
    assert!(matches!(result, Err(ZoneFailure::ParseError)));
}

#[test]
fn empty_bytes_return_parse_error() {
    let result = extract_text_from_bytes(b"");
    assert!(matches!(result, Err(ZoneFailure::ParseError)));
}

#[test]
fn extracted_text_is_redacted_so_debug_does_not_leak_content() {
    // FR-019 — Redacted wrapping must mask the inner value from
    // accidental Debug logging.
    let bytes = build_text_pdf("VERY SECRET CASE INFO");
    let result = extract_text_from_bytes(&bytes).expect("must extract");
    let debug_repr = format!("{:?}", result.raw);
    assert!(
        !debug_repr.contains("VERY SECRET"),
        "Redacted Debug leaked content: {debug_repr}"
    );
}

#[test]
fn happy_path_pdf_has_no_partial_flag_set() {
    // Single-page PDF — was_partial heuristic only fires for >1 page
    // documents (pages_total > 1 && blocks < pages).
    let bytes = build_text_pdf("Court ruling section 3.1");
    let result = extract_text_from_bytes(&bytes).unwrap();
    assert!(!result.was_partial);
}
