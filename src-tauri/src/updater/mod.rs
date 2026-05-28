// Spec 007 — auto-updater domain.
//
// Replaces the spec 006 built-in Tauri updater modal with a non-modal
// Swedish in-app surface. Owns the 8-state UpdateState machine, the
// 4-hour background tick, and the per-zone-aware deferral gate.
//
// Module layout per `specs/007-auto-updater/plan.md`:
//   - state       — UpdateState enum + Updater struct
//   - status      — UpdateStatus mirrored value (Tauri event payload)
//   - errors      — UpdateFailure enum + Swedish copy + plugin mapping
//   - commands    — Tauri commands invocable from React
//   - tick        — 4-hour background ticker
//   - deferral    — any_zone_processing predicate + deferred-restart

pub mod commands;
pub mod deferral;
pub mod errors;
pub mod lifecycle;
pub mod state;
pub mod status;
pub mod tick;

pub use errors::UpdateFailure;
pub use lifecycle::RemoteUpdate;
pub use state::{SharedUpdater, UpdateState, Updater};
pub use status::UpdateStatus;
