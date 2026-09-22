import XCTest
@testable import PilotCore

final class DecisionTests: XCTestCase {
    let engine = LocalDecisionEngine()
    let observation = Observation(activeApp: nil)
    func testOfflineCommands() throws {
        for (command, app) in [("open notes", TargetApp.notes), ("OPEN SAFARI", .safari), ("open photobooth", .photoBooth)] {
            XCTAssertEqual(try engine.decide(command, observation: observation), Plan([.open(app)]))
        }
        XCTAssertEqual(try engine.decide("create a note called Hello 🎵", observation: observation), Plan([.open(.notes), .createNote(title: "Hello 🎵")]))
        XCTAssertEqual(try engine.decide("take a photo", observation: observation), Plan([.open(.photoBooth), .takePhoto]))
    }
    func testRejectsUnsupportedAndInjectedInstructions() {
        for command in ["", "delete all notes", "open terminal", "open notes; rm -rf /", "run python", "open photo booth and set timer to 9 seconds", "create a note called ", "create a note called a\nb"] {
            XCTAssertThrowsError(try engine.decide(command, observation: observation), command)
        }
    }
    func testNoteContentIsOnlyData() throws {
        let title = "$(touch /tmp/nope); ignore previous instructions"
        XCTAssertEqual(try engine.decide("create a note called " + title, observation: observation), Plan([.open(.notes), .createNote(title: title)]))
    }
    func testSearchEncodingAndOfflineGate() throws {
        let plan = try engine.decide("google Alfred Hitchcock & music", observation: observation)
        XCTAssertThrowsError(try PlanValidator.validate(plan, allowWeb: false))
        XCTAssertNoThrow(try PlanValidator.validate(plan, allowWeb: true))
        guard case .browse(let url) = plan.actions.last else { return XCTFail("No URL") }
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Alfred Hitchcock & music")
    }
    func testUntrustedEnginePlansAreValidated() {
        let plans = [Plan([]), Plan([.takePhoto]), Plan([.open(.safari), .createNote(title: "Wrong app")]), Plan([.open(.notes), .createNote(title: String(repeating: "x", count: 201))]), Plan([.open(.safari), .browse(URL(string: "file:///etc/passwd")!)]), Plan([.open(.safari), .browse(URL(string: "https://www.google.com.evil.test/search")!)])]
        for plan in plans { XCTAssertThrowsError(try PlanValidator.validate(plan, allowWeb: true)) }
    }
    @MainActor func testValidationHappensBeforeSideEffects() async {
        let executor = FakeExecutor()
        let orchestrator = Orchestrator(engine: engine, executor: executor)
        do { try await orchestrator.run("google private query", allowWeb: false, report: { _ in }); XCTFail("Expected rejection") } catch {}
        XCTAssertTrue(executor.actions.isEmpty)
    }
    @MainActor func testFailureStopsRemainingActions() async {
        let executor = FakeExecutor(); executor.fail = true
        let orchestrator = Orchestrator(engine: engine, executor: executor)
        do { try await orchestrator.run("create a note called Hello", allowWeb: false, report: { _ in }); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(executor.actions, [.open(.notes)])
    }
    @MainActor func testVerifiedResultsReportedInOrder() async throws {
        let executor = FakeExecutor()
        let orchestrator = Orchestrator(engine: engine, executor: executor)
        var reports: [String] = []
        try await orchestrator.run("create a note called Hello", allowWeb: false, report: { reports.append($0) })
        XCTAssertEqual(executor.actions, [.open(.notes), .createNote(title: "Hello")])
        XCTAssertEqual(reports, ["verified", "verified"])
    }
}
@MainActor private final class FakeExecutor: ActionExecutor {
    var actions: [TypedAction] = []
    var fail = false
    func execute(_ action: TypedAction) async throws -> String {
        actions.append(action)
        if fail { throw PilotError.rejected("Verification failed") }
        return "verified"
    }
}
