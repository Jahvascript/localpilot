# LocalPilot — first offline Mac prototype

A native macOS 13+ Swift app. No package downloads, model service, telemetry, screenshots, AppleScript, or shell execution in the app. The initial decision engine is deterministic and local. It is not Jev and does not claim general natural-language understanding.

## First run

1. Open `LocalPilot.app` in this folder.
2. Click **Enable Accessibility**. In System Settings → Privacy & Security → Accessibility, enable LocalPilot. If it is not listed, add this app with the + button. Reopen it if macOS requires that.
3. Type `open notes` and click **Run**. Success means Notes is confirmed as the active application.
4. In Notes, select an **On My Mac** folder if you want the note to stay local. The agent does not change your account or sync settings. Return to LocalPilot and run `create a note called LocalPilot test`. The adapter checks that the editor is blank before entering the title, then reads it back.
5. Try `open safari` and `open photo booth`. These work without a network.
6. Try **Speak locally**, grant microphone and Speech permissions, say `open notes`, stop listening, review the transcript, and click **Run**. Recognition is limited to 15 seconds. It never executes partial transcripts automatically.
7. To test capture, run `take a photo`. This selects single-photo mode, invokes File → Take Photo once, and checks for a new collection item. Photo Booth saves a photo in its own library. Its normal countdown applies; arbitrary timer settings are not implemented.
8. Optional: enable **Enable web searches**, then run `google Alfred Hitchcock`. Safari sends the query to Google. This is an explicitly online operation. Opening Safari itself remains offline-capable.

If an adapter cannot find a unique accessible control, it stops. Use **Inspect app controls**, switch to the target app during the five-second delay, then return to LocalPilot to read the labels. This diagnostic is displayed in memory and may include document/window titles; clear it when finished. It does not export a log or read editor values for display.

## Commands

| Command | Verification |
| --- | --- |
| `open notes` | Notes is frontmost and an AX application handle is available |
| `create a note called Hello` | A blank editor is found after New Note; its value matches Hello |
| `open notes and create a note called Hello` | Same as above |
| `open safari` | Safari is frontmost |
| `google Alfred Hitchcock` | Safari AX web-area URL matches search host/path/query |
| `open safari and google Alfred Hitchcock` | Same as above |
| `open photo booth` | Photo Booth is frontmost |
| `take a photo` | The accessible photo collection gains an item |
| `open photo booth and take a photo` | Same as above |

English commands and English UI labels only in this version. Unsupported commands cause no action. Readback verifies UI state, not Notes durable storage or successful network content delivery. A verification timeout can follow a completed side effect: inspect the target before retrying. Stop prevents subsequent actions but cannot undo a note or cancel a shutter already pressed.

## Architecture

```text
Microphone → on-device Speech → reviewed transcript
                                      ↓
Typed command ─────────────────→ Orchestrator
                                      ↓
                              DecisionEngine
                            (local grammar v0)
                                      ↓
                         validate entire typed plan
                                      ↓
                           trusted ActionExecutor
                                      ↓
                          macOS AX → readback check

ReasoningPlane: separate interface, disabled implementation
```

`PilotCore/Decision.swift` defines the replaceable `DecisionEngine`, the action vocabulary, validator, orchestrator, and separate `ReasoningPlane`. Jev can later implement DecisionEngine, as can an offline policy model. Neither gets code execution, arbitrary selectors, arbitrary URLs, arbitrary app identifiers, or keyboard primitives. Add a bounded decoder and tests before accepting external model responses. No Jev integration or API key is needed for this prototype.

`AccessibilityExecutor.swift` owns the trusted app adapters. NSWorkspace launches the three allowlisted apps. Accessibility reads/presses controls and sets field values. The Safari adapter uses File → Open Location through AX and additionally owns the fixed Return key action, sent only to Safari's current process after checking foreground focus. These are not exposed to a model. The executor checks foreground focus before operations and uses bounded polling; it stops on ambiguity or timeout. Do not interact with a target app while a task runs.

`SpeechInput.swift` uses Apple's Speech framework only when `supportsOnDeviceRecognition` is true and sets `requiresOnDeviceRecognition = true`. Availability depends on hardware, language assets, and OS. If local recognition is unavailable, typed input remains available; the app does not download a model or silently use a server. A bundled Whisper engine is a future alternative for unsupported Macs. [Apple's on-device support documentation](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

## Build and test

Run from this folder:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

The scripts use the installed Swift compiler directly because this Mac's Swift Package Manager fails its PlatformPath lookup with the installed Command Line Tools. Full Xcode is not needed for these scripts. `Package.swift` and XCTest tests are also provided for environments with a working package toolchain. The app is locally ad-hoc signed, not notarized for distribution. Keep it at a stable path; rebuilds may require re-enabling Accessibility.

The dependency-free runner checks parsing, invalid plans, literal command-like note text, URL encoding, offline policy, validation before side effects, execution order, failure propagation, and cancellation. It uses a fake executor and does not count as a live UI integration test.

## Privacy and prototype limits

- No runtime HTTP client, cloud model, command/audio persistence, or screenshot capture. Audio buffers and transcript are held in memory during use. Clear removes visible transcript/status.
- Other applications retain their normal behavior. Notes may sync; Safari makes network requests; Photo Booth stores photos. Turning off web searches does not firewall those apps or the OS. Disconnect the network for a full offline acceptance test.
- Read-only AX traversal stays bounded to the active allowlisted application. UI text is not passed to any model. Only explicit diagnostics display labels.
- Live Notes editing, Safari search, Photo Booth capture, and microphone transcription require permission-gated testing on the actual Mac. Control labels and roles can differ across OS versions. Failures are reported instead of guessing coordinates or retrying side effects.
- No arbitrary timer control, continuous listening, wake word, multi-step general planner, Reaper/Photoshop adapters, local reasoning model, or cloud reasoning connection yet.

## Manual acceptance record

Disconnect Wi-Fi/network and test app launch, note creation in On My Mac, speech transcription, and photo capture. Confirm visible results yourself as well as the app's status. Try switching foreground apps during a task; subsequent actions should stop. Try an unsupported instruction and confirm no action. With web disabled, `google test` should reject before Safari launches. Test search separately with the network and web toggle enabled. Record actual results in `TESTING.md`; do not mark adapter scenarios passed solely because the unit tests pass.

---

## Everyone Is Welcome at JahvaScript

**Different backgrounds. Different experiences. One community.**

JahvaScript welcomes developers, students, beginners,
and contributors of all backgrounds and experience levels.

We believe in peace, respect, accessibility, learning,
and constructive collaboration.

Contributions are welcome through code, documentation,
testing, accessibility improvements, bug reports,
and thoughtful suggestions.

**Every contribution counts. Every voice deserves respect.**

### Community Standards

- [Code of Conduct](https://github.com/Jahvascript/.github/blob/main/CODE_OF_CONDUCT.md)
- [Contributing](https://github.com/Jahvascript/.github/blob/main/CONTRIBUTING.md)
- [Accessibility](https://github.com/Jahvascript/.github/blob/main/ACCESSIBILITY.md)
- [Support](https://github.com/Jahvascript/.github/blob/main/SUPPORT.md)

Community reporting: jahvascripts@gmail.com

### License

Original JahvaScript code in this project is released
under the MIT License. Third-party components retain
their own applicable licenses.

*JahvaScript — Code with purpose. Build with unity.*
