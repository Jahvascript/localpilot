import Foundation
import PilotCore

@MainActor final class Recorder: ActionExecutor {
    var actions: [TypedAction] = []
    var fail = false
    func execute(_ action: TypedAction) async throws -> String {
        actions.append(action)
        if fail { throw PilotError.rejected("Simulated verification failure") }
        return "verified"
    }
}
@main struct SmokeTests {
    @MainActor static func main() async throws {
        let engine = LocalDecisionEngine(), observation = Observation(activeApp: nil)
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fatalError("FAIL: " + label) }
            checks += 1; print("PASS: " + label)
        }
        func rejects(_ label: String, _ body: () throws -> Void) {
            do { try body(); check(false, label) } catch { check(true, label) }
        }
        for (command, app) in [("open notes", TargetApp.notes), ("OPEN SAFARI", .safari), ("open photobooth", .photoBooth)] {
            check(try engine.decide(command, observation: observation) == Plan([.open(app)]), command)
        }
        let title = "Hello 🎵 $(touch /tmp/nope)"
        check(try engine.decide("create a note called " + title, observation: observation) == Plan([.open(.notes), .createNote(title: title)]), "note content stays data")
        check(try engine.decide("take a photo", observation: observation) == Plan([.open(.photoBooth), .takePhoto]), "photo plan")
        for command in ["", "delete all notes", "open terminal", "open notes; rm -rf /", "run python", "open photo booth and set timer to 9 seconds", "create a note called ", "create a note called a\nb"] {
            rejects("reject unsupported input") { _ = try engine.decide(command, observation: observation) }
        }
        let search = try engine.decide("google Alfred Hitchcock & music", observation: observation)
        rejects("offline blocks web plan") { try PlanValidator.validate(search, allowWeb: false) }
        try PlanValidator.validate(search, allowWeb: true)
        if case .browse(let url) = search.actions.last {
            check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Alfred Hitchcock & music", "search encoding")
        } else { check(false, "search URL") }
        for plan in [Plan([]), Plan([.takePhoto]), Plan([.open(.safari), .createNote(title: "Wrong app")]), Plan([.open(.notes), .createNote(title: String(repeating: "x", count: 201))]), Plan([.open(.safari), .browse(URL(string: "file:///etc/passwd")!)]), Plan([.open(.safari), .browse(URL(string: "https://www.google.com.evil.test/search")!)])] {
            rejects("reject invalid engine plan") { try PlanValidator.validate(plan, allowWeb: true) }
        }
        let recorder = Recorder(), orchestrator = Orchestrator(engine: engine, executor: Recorder())
        _ = orchestrator
        let runner = Orchestrator(engine: engine, executor: recorder)
        do { try await runner.run("google private query", allowWeb: false, report: { _ in }); check(false, "offline rejection") } catch {}
        check(recorder.actions.isEmpty, "validate before side effects")
        recorder.fail = true
        do { try await runner.run("create a note called Hello", allowWeb: false, report: { _ in }); check(false, "failure propagation") } catch {}
        check(recorder.actions == [.open(.notes)], "stop on failed verification")
        recorder.fail = false; recorder.actions = []
        var reports: [String] = []
        try await runner.run("create a note called Hello", allowWeb: false, report: { reports.append($0) })
        check(recorder.actions == [.open(.notes), .createNote(title: "Hello")] && reports == ["verified", "verified"], "ordered execution and reports")
        let cancelled = Task { @MainActor in
            try Task.checkCancellation()
            try await runner.run("open notes", allowWeb: false, report: { _ in })
        }
        cancelled.cancel()
        do { try await cancelled.value; check(false, "cancelled task") } catch { check(recorder.actions.count == 2, "cancellation prevents next action") }
        check(try WindowSelection.choose(focused: "focused", main: "main", visible: ["main", "focused"]) == "focused", "focused window wins")
        check(try WindowSelection.choose(focused: nil, main: "main", visible: ["main", "other"]) == "main", "explicit main window fallback")
        check(try WindowSelection.choose(focused: nil, main: nil, visible: ["only"]) == "only", "single visible window fallback")
        check(try WindowSelection.choose(focused: nil, main: nil, visible: [String]()) == nil, "no window is pending, not success")
        rejects("never guess among windows") { _ = try WindowSelection.choose(focused: nil, main: nil, visible: ["one", "two"]) }
        var reads = 0, pauses = 0
        let ready: String = try await Readiness.wait(attempts: 4, message: "not ready", pause: { pauses += 1 }) {
            reads += 1
            return reads == 3 ? "window" : nil
        }
        check(ready == "window" && reads == 3 && pauses == 2, "wait through delayed window publication")
        reads = 0; pauses = 0
        do {
            let _: String = try await Readiness.wait(attempts: 3, message: "not ready", pause: { pauses += 1 }) { reads += 1; return nil }
            check(false, "missing window timeout")
        } catch { check(reads == 3 && pauses == 2, "missing window polling is bounded") }
        reads = 0; pauses = 0
        do {
            let _: String = try await Readiness.wait(attempts: 3, message: "not ready", pause: { pauses += 1 }) { reads += 1; throw PilotError.rejected("focus lost") }
            check(false, "focus loss propagation")
        } catch { check(reads == 1 && pauses == 0 && error.localizedDescription == "focus lost", "focus loss is not retried") }
        reads = 0
        let cancelledRead = Task { @MainActor in
            let _: String = try await Readiness.wait(message: "not ready", pause: {}) { reads += 1; return nil }
        }
        cancelledRead.cancel()
        do { try await cancelledRead.value; check(false, "cancelled readiness") }
        catch { check(reads == 0 && error is CancellationError, "cancelled readiness performs no observations") }
        print("All \(checks) checks passed. App UI integration requires a separate live test.")
    }
}
