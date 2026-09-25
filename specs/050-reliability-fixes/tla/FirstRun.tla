---------------------------- MODULE FirstRun ----------------------------
(* Spec 050 — first-run consent/pull recovery machine.
   Mirrors src-tauri/src/sidecar/commands.rs (give_consent, cancel_consent,
   cancel_model_pull, spawn_pull_task, after_sidecar_ready) and
   src/lib/use-wizard-state.ts (deriveWizardPhase).
   Fixed = TRUE models the spec-050 code; Fixed = FALSE models v0.4.1, so
   the invariants are shown to BITE (they must fail on the old code). *)
EXTENDS Naturals

CONSTANT Fixed

VARIABLES consent, model, override, diskOk

vars == <<consent, model, override, diskOk>>

Consents  == {"not_asked", "fortsatt", "avbryt"}
Models    == {"not_present", "downloading", "ready", "download_failed"}
Overrides == {"none", "fel_disk_full", "modell_saknas_avbruten", "fel_ovantat"}

Init == /\ consent \in Consents
        /\ model \in {"not_present", "ready"}
        /\ override = "none"
        /\ diskOk \in BOOLEAN

\* deriveWizardPhase (use-wizard-state.ts), with visible = override if set.
Phase ==
  IF consent \in {"not_asked", "avbryt"} THEN "welcome"
  ELSE IF model = "not_present" \/ override = "modell_saknas_avbruten" THEN "welcome"
  ELSE IF model = "download_failed" \/ override \in {"fel_disk_full", "fel_ovantat"} THEN "error"
  ELSE IF model = "downloading" THEN "progress"
  ELSE IF model = "ready" THEN "hidden"
  ELSE "welcome"

CancelAllowed ==
  IF Fixed
  THEN \/ consent = "not_asked"
       \/ consent = "fortsatt" /\ model \in {"not_present", "download_failed"}
  ELSE consent = "not_asked"

GiveConsent ==
  /\ model /= "downloading"
  /\ consent' = "fortsatt"
  /\ LET cleared == IF Fixed THEN "none" ELSE override IN
       IF Fixed /\ model = "ready"          \* GAP-1 fix: consent only
       THEN /\ model' = model /\ override' = cleared
       ELSE IF diskOk
       THEN /\ model' = "downloading" /\ override' = cleared
       ELSE /\ model' = model /\ override' = "fel_disk_full"
  /\ UNCHANGED diskOk

CancelConsent ==
  /\ CancelAllowed
  /\ consent' = "avbryt"
  /\ override' = IF Fixed THEN "none" ELSE override
  /\ UNCHANGED <<model, diskOk>>

CancelPull ==
  /\ model = "downloading"
  /\ model' = "not_present"
  /\ override' = "modell_saknas_avbruten"
  /\ UNCHANGED <<consent, diskOk>>

PullCompleted == /\ model = "downloading" /\ model' = "ready"
                 /\ UNCHANGED <<consent, override, diskOk>>
PullFailed    == /\ model = "downloading" /\ model' = "download_failed"
                 /\ UNCHANGED <<consent, override, diskOk>>

\* after_sidecar_ready at boot: tags exhausted → FelOvantat (FR-008).
TagsExhausted == /\ model /= "downloading"
                 /\ override' = IF Fixed THEN "fel_ovantat" ELSE override
                 /\ model' = IF Fixed THEN "not_present" ELSE model   \* GAP-2 fix
                 /\ UNCHANGED <<consent, diskOk>>

FreeOrFillDisk == /\ diskOk' = ~diskOk /\ UNCHANGED <<consent, model, override>>

Next == \/ GiveConsent \/ CancelConsent \/ CancelPull
        \/ PullCompleted \/ PullFailed \/ TagsExhausted \/ FreeOrFillDisk

Spec == Init /\ [][Next]_vars /\ WF_vars(PullCompleted \/ PullFailed)

TypeOK == /\ consent \in Consents /\ model \in Models
          /\ override \in Overrides /\ diskOk \in BOOLEAN

\* FR-002 — a live download is never hidden behind a stale override.
DownloadVisible == model = "downloading" => Phase = "progress"

\* The wizard only collapses onto the zones when the model is really there.
HiddenImpliesReady == Phase = "hidden" => model = "ready"

\* FR-003 — the error panel's Avbryt always does something.
ErrorAvbrytWorks == Phase = "error" /\ model /= "downloading" => ENABLED CancelConsent

\* No dead end: from welcome or error the user can always start again.
NoDeadEnd == Phase \in {"welcome", "error"} => ENABLED GiveConsent

\* Liveness: a started download always ends.
DownloadEnds == model = "downloading" ~> model \in {"ready", "download_failed", "not_present"}
=============================================================================
