// Spec 003 / T016 — Sammanfatta zone state machine + dispatch pipeline.
//
// Implementation arrives in US1 phase. The zone owns a single-flight
// `Arc<RwLock<Option<DropJob>>>` and orchestrates the extract → truncate
// → model-call → write → open pipeline.
