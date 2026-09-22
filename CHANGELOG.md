# Development log

## 2026-09-22 — 0.1.1, stability build 2

First Git checkpoint of the current prototype. Earlier edits were not committed; this log summarizes them rather than inventing historical commits.

Implemented native local Speech input, reviewed transcripts, deterministic DecisionEngine, typed-action validation, separate disabled ReasoningPlane interface, and trusted Accessibility adapters for Notes, Safari, and Photo Booth. No cloud model or arbitrary model code execution.

Live testing found and corrected duplicate Notes controls, Photo Booth selector mismatches, a nonfunctional shutter-button action, transient photo-grid disappearance, and Safari address-label capitalization. The menu-based Photo Booth capture and readback were confirmed by the user. Safari search was also reported successful once.

Subsequent retesting exposed regressions: Notes/Photo Booth window availability and Safari address focus. Build 2 adds bounded window-readiness polling, explicit main/single-window fallback, ambiguity rejection, and Safari File → Open Location. Automated checks: 34 passed. Build compiles and signature validation passed. **Live regression tests for build 2 are pending; this is not a known-good release.**

Next: test Notes creation, Photo Booth capture, Safari search, and offline voice on this exact build, including cold and already-open apps. Record outcomes in TESTING.md before changing code again.

## Logging convention

For each meaningful change, record the problem, change, checks run, and unresolved live-test results. Commit source and these logs together. Record user-confirmed results as such; do not equate policy tests with live app verification. Never commit raw accessibility dumps, browsing history, speech recordings, secrets, or generated app bundles.
