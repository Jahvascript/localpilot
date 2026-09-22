import Foundation

public enum WindowSelection {
    // Explicit OS focus/main-window evidence takes priority. Never guess among
    // multiple windows when both AX attributes are temporarily unavailable.
    public static func choose<T>(focused: T?, main: T?, visible: [T]) throws -> T? {
        if let focused = focused { return focused }
        if let main = main { return main }
        guard visible.count <= 1 else { throw PilotError.rejected("Multiple visible windows and no focused/main window. Select the intended window and retry.") }
        return visible.first
    }
}

@MainActor public enum Readiness {
    // Callers supply observations only; a missing observation can be retried,
    // but errors (including focus loss) and cancellation propagate immediately.
    public static func wait<T>(attempts: Int = 40, message: String,
                               pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 200_000_000) },
                               read: () throws -> T?) async throws -> T {
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            if let value = try read() { return value }
            if attempt + 1 < attempts { try await pause() }
        }
        throw PilotError.rejected(message)
    }
}
