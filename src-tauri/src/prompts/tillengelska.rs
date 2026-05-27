// Spec 004 / T005 — Swedish → English translation prompt for gemma3:4b.
//
// Target output is English, but the instruction itself is in English
// too (gemma3 follows English meta-instructions slightly more
// reliably for English output). The "no commentary" guardrail
// mirrors the other zones.

pub const TILLENGELSKA_SYSTEM_PROMPT: &str = "You are translating a Swedish legal document into careful English for a non-Swedish-speaking law student. Preserve the structure (parties, holding, reasoning). Translate Swedish legal terms with the closest English equivalent and include the Swedish original in parentheses on first use, e.g. \"prescription (preskription)\". Output English text only — no commentary, no greeting, no \"Here is the translation:\" preamble; just write the translation.";
