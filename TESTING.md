# Test record

## Current stabilization build: 0.1.1 (2), 2026-09-22

Prior passes below are historical; they did not establish repeatable reliability. User reports Notes creation and Photo Booth capture regressed with missing focused-window errors, and Safari search regressed with an unidentified address field. App launch and offline voice still work by user report.

This build adds bounded window-readiness polling, explicit main-window/single-window fallback, and ambiguity rejection. Safari uses its observed File → Open Location menu action and identifies a unique, focused address field in the target window. The UI displays the build number so live results can be tied to the installed binary.

Automated checks: **34 passed**, including delayed window publication, absent windows, main-window fallback, ambiguous windows, focus-loss propagation, and cancellation. These are deterministic policy tests, not live AX integration tests.

| Same-build live regression check | Result |
| --- | --- |
| open notes | Pending build 2 retest |
| create a note called hello | Pending build 2 retest |
| take a photo | Pending build 2 retest; creates one photo |
| google Alfred Hitchcock, web enabled | Pending build 2 retest |
| offline voice → open notes | Pending build 2 retest |

Test each relevant command with the app already open and again after quitting it. Do not mark a scenario stable after only one successful launch. No action is automatically repeated after a side effect.

## Earlier build history

Environment: Intel Mac, macOS 13.7.8, Swift 5.8.1.

| Check | Result |
| --- | --- |
| Core dependency-free tests | 25 checks passed |
| Native app compilation and packaging | Passed; ad-hoc signature and Info.plist validated |
| Swift Package Manager tests | Toolchain blocked: installed CLT cannot resolve SDK PlatformPath; direct compiler runner used instead |
| Accessibility permission | Working in current build, confirmed by user-reported Notes creation and readback after refreshing permission |
| Notes launch | Passed live, user-reported: “ran. notes is active” |
| On-device speech capability | Supported for en-US; user subsequently confirmed successful network-disconnected voice-to-Notes test |
| Notes create + readback | Passed live, user-reported: “Verified: Notes is active.” and “Verified: new note editor contains the requested title.” Fixed duplicate controls by restricting lookup to the focused window toolbar and editor/readback to that same window. Network-disconnected test not yet recorded. |
| Safari launch | Passed live, user-reported: “safari is active” following the requested voice test; transcript not supplied |
| Safari search + URL verification | User reported “worked thats a w” on 2026-09-22 after retrying the corrected Safari adapter. Search scenario passed by user report; exact final verification status was not supplied. Fixed lowercase smart-search-field label matching and scoped page verification to the focused window. |
| Photo Booth launch | Passed live, user-reported: “Verified: Photo Booth is active.” |
| Photo Booth capture + collection verification | PASSED live, user-reported: “Verified: Photo Booth is active.” and “Verified: Photo Booth added a photo to its accessible collection”. Previous live attempt also confirmed the three-second countdown and a saved photo visually. File → Take Photo is invoked once; verification waits through temporary grid disappearance and confirms image-count growth. Network-disconnected photo capture not separately tested. |
| Microphone + offline transcription | Passed live, user-reported: “worked notes active” after instructions to disconnect all internet, speak “open Notes,” review the transcript, and run. Confirms this simple voice-to-action scenario offline. |

Adapter implementations are provisional until those live scenarios pass. No live task success should be inferred from the core checks.
