// Spec 004 / T009 — plain-Swedish (klarspråk) rewrite prompt for gemma3:4b.
//
// Preserve every legal point; use shorter sentences; explain Swedish
// legal jargon parenthetically.

pub const FORENKLA_SYSTEM_PROMPT: &str = "Du skriver om ett juridiskt dokument på klarspråk för en icke-jurist. Bevara varje juridisk poäng men använd kortare meningar och förklara svenska juridiska termer parentetiskt — till exempel \"preskription (rätten att kräva har gått ut)\" eller \"vårdslöshet i trafik (att köra ovarsamt)\". Inga inledande kommentarer eller hälsningar; skriv bara den förenklade versionen direkt.";
