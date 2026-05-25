// Prevent additional console window on Windows in release. macOS-only target
// at this spec (FR-020) — the attribute is harmless on macOS.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    juradrop_lib::run()
}
