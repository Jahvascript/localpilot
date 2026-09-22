import Foundation

public enum TargetApp: String, Codable, CaseIterable {
    case notes = "com.apple.Notes", safari = "com.apple.Safari", photoBooth = "com.apple.PhotoBooth"
}
// This is the entire execution vocabulary. Engines cannot supply code, keys,
// selectors, bundle identifiers, shell commands, or arbitrary file paths.
public enum TypedAction: Equatable {
    case open(TargetApp)
    case createNote(title: String)
    case browse(URL)
    case takePhoto
}
public struct Plan: Equatable {
    public let actions: [TypedAction]
    public init(_ actions: [TypedAction]) { self.actions = actions }
}
public struct Observation { public let activeApp: TargetApp?; public init(activeApp: TargetApp?) { self.activeApp = activeApp } }
public protocol DecisionEngine { func decide(_ command: String, observation: Observation) throws -> Plan }
public protocol ReasoningPlane { func reason(about request: String) async throws -> String }
public enum PilotError: Error, LocalizedError {
    case rejected(String)
    public var errorDescription: String? { if case let .rejected(message) = self { return message }; return nil }
}
public struct DisabledReasoningPlane: ReasoningPlane {
    public init() {}
    public func reason(about request: String) async throws -> String { throw PilotError.rejected("Reasoning is not connected. No data was sent.") }
}
// Jev or a local policy model can replace this implementation, but still must
// return this vocabulary and pass the executor's independent validation.
public struct LocalDecisionEngine: DecisionEngine {
    public init() {}
    public func decide(_ command: String, observation: Observation) throws -> Plan {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        switch lower {
        case "open notes": return Plan([.open(.notes)])
        case "open safari": return Plan([.open(.safari)])
        case "open photo booth", "open photobooth": return Plan([.open(.photoBooth)])
        case "take a photo", "take photo", "open photo booth and take a photo", "open photobooth and take a photo": return Plan([.open(.photoBooth), .takePhoto])
        default: break
        }
        for prefix in ["open notes and create a note called ", "open notes and create a note titled ", "create a note called ", "create note called "] {
            if lower.hasPrefix(prefix) {
                let title = String(text.dropFirst(prefix.count))
                let plan = Plan([.open(.notes), .createNote(title: title)])
                try PlanValidator.validate(plan, allowWeb: false)
                return plan
            }
        }
        for prefix in ["open safari and google ", "google "] where lower.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { throw PilotError.rejected("Say what to search for.") }
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return Plan([.open(.safari), .browse(components.url!)])
        }
        throw PilotError.rejected("Unsupported command. Use one of the examples. No action was taken.")
    }
}
public enum PlanValidator {
    public static func validate(_ plan: Plan, allowWeb: Bool) throws {
        guard !plan.actions.isEmpty, plan.actions.count <= 2 else { throw PilotError.rejected("Invalid plan size.") }
        var target: TargetApp?
        for (index, action) in plan.actions.enumerated() {
            switch action {
            case .open(let app):
                guard index == 0 else { throw PilotError.rejected("App launch must be first.") }
                target = app
            case .createNote(let title):
                guard target == .notes, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
                      !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw PilotError.rejected("Invalid note title or target.") }
            case .browse(let url):
                guard allowWeb, target == .safari, url.scheme == "https", url.host == "www.google.com", url.path == "/search", url.user == nil, url.password == nil, url.port == nil else { throw PilotError.rejected("Web searches require Enable web searches. The query is sent by Safari to Google.") }
            case .takePhoto:
                guard target == .photoBooth else { throw PilotError.rejected("Invalid camera target.") }
            }
        }
    }
}
@MainActor public protocol ActionExecutor { func execute(_ action: TypedAction) async throws -> String }
@MainActor public final class Orchestrator {
    private let engine: any DecisionEngine
    private let executor: any ActionExecutor
    public init(engine: any DecisionEngine, executor: any ActionExecutor) { self.engine = engine; self.executor = executor }
    public func run(_ command: String, allowWeb: Bool, report: (String) -> Void) async throws {
        let plan = try engine.decide(command, observation: Observation(activeApp: nil))
        try PlanValidator.validate(plan, allowWeb: allowWeb) // validate whole plan before any side effect
        for action in plan.actions {
            try Task.checkCancellation()
            report(try await executor.execute(action))
        }
    }
}
