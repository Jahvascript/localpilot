import SwiftUI
import AppKit
import PilotCore
import Speech

@MainActor final class PilotModel: ObservableObject {
    @Published var command = "open notes"
    @Published var status = "Ready. Commands and audio stay in memory."
    @Published var allowWeb = false
    @Published var busy = false
    @Published var listening = false
    private let executor = AccessibilityExecutor()
    private let speech = SpeechInput()
    private var task: Task<Void, Never>?
    func run() {
        guard !busy, !listening else { return }
        busy = true; status = "Running…"
        let command = command, allowWeb = allowWeb
        task = Task {
            defer { busy = false; task = nil }
            do {
                let orchestrator = Orchestrator(engine: LocalDecisionEngine(), executor: executor)
                try await orchestrator.run(command, allowWeb: allowWeb) { self.status += "\n" + $0 }
            } catch is CancellationError { status += "\nStopped. Completed actions are not undone." }
            catch { status += "\n" + error.localizedDescription }
        }
    }
    func listen() {
        guard !busy else { return }
        if listening { speech.stop(); listening = false; status = "Review the transcript, then click Run."; return }
        busy = true
        task = Task {
            defer { busy = false; task = nil }
            do {
                try await speech.start(update: { self.command = $0 }, ended: { message in self.listening = false; self.status = message ?? "Review the transcript, then click Run." })
                listening = true; status = "Listening locally, up to 15 seconds. Click Stop listening when done."
            } catch { status = error.localizedDescription }
        }
    }
    func stop() { task?.cancel(); speech.stop(); listening = false }
    func diagnose() {
        guard !busy, !listening else { return }
        busy = true; status = "Switch to the target app within 5 seconds. Labels will be shown here, in memory only."
        task = Task {
            defer { busy = false; task = nil }
            do { try await Task.sleep(nanoseconds: 5_000_000_000); status = executor.diagnostics() }
            catch { status = "Inspection cancelled." }
        }
    }
}
@main struct LocalPilotApp: App {
    init() {
        if CommandLine.arguments.contains("--health-check") {
            print("Accessibility permission: \(AccessibilityExecutor.trusted)")
            print("On-device en-US speech supported: \(SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false)")
            for app in TargetApp.allCases { print("Installed \(app.rawValue): \(NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.rawValue) != nil)") }
            exit(0)
        }
    }
    @StateObject private var model = PilotModel()
    var body: some Scene {
        WindowGroup("LocalPilot — offline prototype") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LocalPilot").font(.largeTitle.bold())
                    Text("0.1.1 · Stability build 2").font(.caption).foregroundColor(.secondary)
                }
                Text("Local speech → decision engine → typed actions → verified Mac controls")
                    .font(.subheadline).foregroundColor(.secondary)
                TextField("Command", text: $model.command).textFieldStyle(.roundedBorder).disabled(model.busy || model.listening)
                HStack {
                    Button(model.listening ? "Stop listening" : "Speak locally") { model.listen() }.disabled(model.busy)
                    Button("Run") { model.run() }.disabled(model.busy || model.listening)
                    Button("Stop") { model.stop() }.disabled(!model.busy && !model.listening)
                }
                Toggle("Enable web searches (Safari sends your query to Google)", isOn: $model.allowWeb).disabled(model.busy)
                Text("Try: open notes • create a note called Hello • open safari • google Alfred Hitchcock • open photo booth • take a photo")
                    .font(.callout).textSelection(.enabled)
                Text("Photo capture uses Photo Booth’s normal countdown and saves a photo in its library. Notes may sync through your existing Notes account. Use an On My Mac folder for local notes.")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button("Enable Accessibility") { AccessibilityExecutor.requestPermission() }
                    Button("Inspect app controls (5-second delay)") { model.diagnose() }.disabled(model.busy || model.listening)
                    Button("Clear") { model.command = ""; model.status = "Cleared." }.disabled(model.busy || model.listening)
                }
                ScrollView { Text(model.status).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(10).background(Color.primary.opacity(0.04)).cornerRadius(8)
                Text("English app labels • No screenshots • No shell tools • No model connection • Review speech before running")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(22).frame(minWidth: 720, minHeight: 520)
        }
    }
}
