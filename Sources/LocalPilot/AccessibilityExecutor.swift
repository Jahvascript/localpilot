import AppKit
import ApplicationServices
import PilotCore

@MainActor final class AccessibilityExecutor: ActionExecutor {
    private var stage = "checking the target app"
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }
    private func tree(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root], result: [AXUIElement] = []
        var seen: [CFHashCode: [AXUIElement]] = [:]
        while !queue.isEmpty && result.count < 1500 {
            let next = queue.removeFirst()
            // Hash collisions do not establish AX element identity.
            let hash = CFHash(next)
            guard !(seen[hash] ?? []).contains(where: { CFEqual($0, next) }) else { continue }
            seen[hash, default: []].append(next)
            result.append(next)
            queue += attribute(next, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return result
    }
    private func root(_ app: TargetApp) throws -> AXUIElement {
        guard Self.trusted else { throw PilotError.rejected("Enable LocalPilot in System Settings → Privacy & Security → Accessibility, then retry.") }
        let foreground = NSWorkspace.shared.frontmostApplication
        guard let running = foreground, running.bundleIdentifier == app.rawValue else {
            throw PilotError.rejected("Target app lost focus while \(stage). Frontmost app: \(foreground?.localizedName ?? "unavailable"). Stopped to avoid acting in another app.")
        }
        let result = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(result, 1)
        return result
    }
    private func focusedWindow(_ app: TargetApp) throws -> AXUIElement {
        guard let window = try availableWindow(app) else { throw PilotError.rejected("The target window is temporarily unavailable. Stopped before acting.") }
        return window
    }
    private func availableWindow(_ app: TargetApp) throws -> AXUIElement? {
        let application = try root(app)
        func usable(_ element: AXUIElement) -> Bool {
            string(element, kAXRoleAttribute) == kAXWindowRole && attribute(element, kAXMinimizedAttribute) as? Bool == false
        }
        func windowAttribute(_ name: String) -> AXUIElement? {
            guard let value = attribute(application, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let element = unsafeBitCast(value, to: AXUIElement.self)
            return usable(element) ? element : nil
        }
        let windows = (attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter(usable)
        return try WindowSelection.choose(focused: windowAttribute(kAXFocusedWindowAttribute), main: windowAttribute(kAXMainWindowAttribute), visible: windows)
    }
    private func readyWindow(_ app: TargetApp) async throws -> AXUIElement {
        stage = "waiting for the target window"
        return try await Readiness.wait(message: "The app is active but its window did not become accessible. Open its main window and retry; no task action was taken.") {
            try self.availableWindow(app)
        }
    }
    private func requireWindow(_ window: AXUIElement, app: TargetApp) throws {
        guard CFEqual(window, try focusedWindow(app)) else { throw PilotError.rejected("The target window changed. Stopped before editing.") }
    }
    private func unique(_ app: TargetApp, role: String, labels: [String], within scope: AXUIElement? = nil) throws -> AXUIElement {
        let matches = tree(try scope ?? root(app)).filter { element in
            string(element, kAXRoleAttribute) == role &&
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { labels.contains(string(element, $0)) } &&
            (attribute(element, kAXEnabledAttribute) as? Bool ?? true)
        }
        guard matches.count == 1 else { throw PilotError.rejected("Expected one accessible \(labels.joined(separator: "/")) control\(scope == nil ? "" : " within the selected window region"); found \(matches.count). Stopped. This app layout may need an adapter update.") }
        return matches[0]
    }
    private func press(_ element: AXUIElement, app: TargetApp) throws {
        _ = try root(app)
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { throw PilotError.rejected("The app refused the accessibility action.") }
    }
    private func waitUntil(attempts: Int = 40, timeoutMessage: () -> String = { "Verification timed out. The action may have occurred; inspect the app before retrying." }, _ condition: () throws -> Bool) async throws {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            if try condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw PilotError.rejected(timeoutMessage())
    }
    private func setValue(_ element: AXUIElement, text: String, app: TargetApp) throws {
        _ = try root(app)
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue else { throw PilotError.rejected("This editor does not expose a writable accessibility value.") }
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success else { throw PilotError.rejected("Could not set the accessible editor value.") }
    }
    func execute(_ action: TypedAction) async throws -> String {
        stage = "checking the target app"
        try Task.checkCancellation()
        guard Self.trusted else { throw PilotError.rejected("Accessibility permission is required. Click Enable Accessibility first.") }
        switch action {
        case .open(let app):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.rawValue) else { throw PilotError.rejected("The requested app is not installed.") }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try await waitUntil { NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier }
            _ = try root(app)
            return "Verified: \(running.localizedName ?? app.rawValue) is active."
        case .createNote(let title):
            let window = try await readyWindow(.notes)
            let nodes = tree(window)
            guard !nodes.contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole }) else {
                throw PilotError.rejected("Close the Notes dialog before creating a note.")
            }
            let toolbars = nodes.filter { string($0, kAXRoleAttribute) == kAXToolbarRole }
            guard toolbars.count == 1 else { throw PilotError.rejected("Expected one toolbar in the active Notes window; found \(toolbars.count). Stopped.") }
            let newNote = try unique(.notes, role: kAXButtonRole, labels: ["New Note", "Create a note", "New note"], within: toolbars[0])
            try requireWindow(window, app: .notes)
            try press(newNote, app: .notes)
            // Never fall back to an arbitrary text field or existing note.
            var editor: AXUIElement?
            try await waitUntil {
                try self.requireWindow(window, app: .notes)
                let candidates = self.tree(window).filter { element in
                    guard self.string(element, kAXRoleAttribute) == kAXTextAreaRole,
                          let value = self.attribute(element, kAXValueAttribute) as? String else { return false }
                    return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if candidates.count == 1 { editor = candidates[0]; return true }; return false
            }
            guard let editor = editor else { throw PilotError.rejected("No unique blank note editor.") }
            try requireWindow(window, app: .notes)
            try setValue(editor, text: title, app: .notes)
            try await waitUntil { try self.requireWindow(window, app: .notes); return self.string(editor, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines) == title }
            return "Verified: new note editor contains the requested title."
        case .browse(let url):
            let window = try await readyWindow(.safari)
            // Use Safari's observed AX menu action to focus the address field.
            // Return remains a fixed, executor-owned submission capability.
            stage = "focusing Safari's address field"
            let fileMenu = try unique(.safari, role: kAXMenuBarItemRole, labels: ["File"])
            let openLocation = try unique(.safari, role: kAXMenuItemRole, labels: ["Open Location…"], within: fileMenu)
            try requireWindow(window, app: .safari)
            try press(openLocation, app: .safari)
            var field: AXUIElement?
            try await waitUntil(timeoutMessage: { "Safari's address field could not be identified. No search URL was entered." }) {
                try self.requireWindow(window, app: .safari)
                let candidates = self.tree(window).filter { element in
                    self.string(element, kAXRoleAttribute) == kAXTextFieldRole &&
                    ["address and search", "smart search field", "search or enter website name"].contains(self.string(element, kAXDescriptionAttribute).lowercased()) &&
                    self.attribute(element, kAXEnabledAttribute) as? Bool == true
                }
                guard candidates.count <= 1 else { throw PilotError.rejected("Multiple Safari address fields found. No URL was entered.") }
                guard let element = candidates.first else { return false }
                let application = try self.root(.safari)
                let appFocused = self.attribute(application, kAXFocusedUIElementAttribute)
                guard self.attribute(element, kAXFocusedAttribute) as? Bool == true || appFocused.map({ CFEqual($0, element) }) == true else { return false }
                field = element; return true
            }
            guard let field = field else { throw PilotError.rejected("Safari address field unavailable.") }
            stage = "entering the search URL"
            try requireWindow(window, app: .safari)
            try setValue(field, text: url.absoluteString, app: .safari)
            guard string(field, kAXValueAttribute) == url.absoluteString else { throw PilotError.rejected("Address entry verification failed.") }
            try key(36, flags: [], app: .safari)
            stage = "verifying Safari's search page"
            try await waitUntil(timeoutMessage: { "The search URL was entered and Return was sent, but Safari's page URL could not be verified. Check whether the search page loaded." }) {
                try self.requireWindow(window, app: .safari)
                return self.tree(window).contains { element in
                    guard self.string(element, kAXRoleAttribute) == "AXWebArea", let actual = self.attribute(element, "AXURL") as? URL else { return false }
                    return actual.host == url.host && actual.path == url.path && URLComponents(url: actual, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value
                }
            }
            return "Verified: Safari navigated to the requested Google search."
        case .takePhoto:
            // Photo Booth's normal still-photo shutter includes its own countdown.
            // Do not claim a configurable timer: this app does not expose one.
            let window = try await readyWindow(.photoBooth)
            guard !tree(window).contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole }) else {
                throw PilotError.rejected("Close the Photo Booth dialog before taking a photo.")
            }
            // Roles and labels confirmed from this Mac's accessible control list.
            let photoMode = try unique(.photoBooth, role: kAXRadioButtonRole, labels: ["picture"], within: window)
            try requireWindow(window, app: .photoBooth)
            if (attribute(photoMode, kAXValueAttribute) as? NSNumber)?.intValue != 1 {
                try press(photoMode, app: .photoBooth)
            }
            try await waitUntil(timeoutMessage: { "Single-photo mode could not be verified. The shutter was NOT pressed. Use Inspect app controls and share the AXRadioButton lines." }) {
                try self.requireWindow(window, app: .photoBooth)
                return (self.attribute(photoMode, kAXValueAttribute) as? NSNumber)?.intValue == 1
            }
            guard let before = try photoCount(in: window) else {
                throw PilotError.rejected("Photo collection is unavailable before capture. No photo was requested; wait for Photo Booth to finish updating.")
            }
            // The window shutter accepted AXPress without capturing on this
            // Mac. Use the observed File menu command as the sole capture path.
            // Never automatically retry or fall back after a capture request.
            let fileMenu = try unique(.photoBooth, role: kAXMenuBarItemRole, labels: ["File"])
            let capture = try unique(.photoBooth, role: kAXMenuItemRole, labels: ["Take Photo"], within: fileMenu)
            guard attribute(capture, kAXEnabledAttribute) as? Bool == true else {
                throw PilotError.rejected("Photo Booth's File → Take Photo command is not enabled. No capture was requested.")
            }
            try Task.checkCancellation()
            try requireWindow(window, app: .photoBooth)
            try press(capture, app: .photoBooth)
            var lastObservedCount: Int?
            try await waitUntil(attempts: 80, timeoutMessage: { "Capture was requested once, but automatic verification timed out (before: \(before), last readable count: \(lastObservedCount.map(String.init) ?? "unavailable")). A photo may have been saved. Inspect Photo Booth before retrying." }) {
                // Countdown/capture can temporarily remove or rebuild the grid.
                // Only retry observation, never the capture action.
                guard let after = try self.photoCount(in: window) else { return false }
                lastObservedCount = after
                return after > before
            }
            return "Verified: Photo Booth added a photo to its accessible collection."
        }
    }
    private func photoCount(in window: AXUIElement) throws -> Int? {
        try requireWindow(window, app: .photoBooth)
        let collections = tree(window).filter { element in
            string(element, kAXRoleAttribute) == "AXGrid" &&
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { string(element, $0) == "photo" }
        }
        guard collections.count <= 1 else { throw PilotError.rejected("Multiple photo grids found; cannot safely verify capture. Inspect Photo Booth before retrying.") }
        // Missing/unreadable is unknown, never a count of zero. Polling may
        // recover once the capture transition ends. Ambiguity still fails.
        guard let collection = collections.first,
              let items = attribute(collection, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        return items.filter { string($0, kAXRoleAttribute) == kAXImageRole }.count
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags, app: TargetApp) throws {
        _ = try root(app)
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw PilotError.rejected("Cannot create fixed keyboard action.") }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
    }
    // Explicit, in-memory diagnostic: labels/roles and Photo Booth control
    // state only. Never show editor values or image content.
    func diagnostics() -> String {
        guard let app = TargetApp.allCases.first(where: { $0.rawValue == NSWorkspace.shared.frontmostApplication?.bundleIdentifier }), let root = try? focusedWindow(app) else { return "Activate a window in Notes, Safari, or Photo Booth during the countdown; Accessibility permission must be enabled." }
        return tree(root).map { element in
            let role = string(element, kAXRoleAttribute)
            var line = "\(role) | \(string(element, kAXTitleAttribute)) | \(string(element, kAXDescriptionAttribute))"
            if app == .photoBooth && role == kAXRadioButtonRole {
                let value = attribute(element, kAXValueAttribute).map { String(describing: $0) } ?? "unavailable"
                let selected = attribute(element, kAXSelectedAttribute).map { String(describing: $0) } ?? "unavailable"
                line += " | value=\(value) | selected=\(selected)"
            }
            if app == .photoBooth && role == "AXGrid" {
                if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                    let images = children.filter { string($0, kAXRoleAttribute) == kAXImageRole }.count
                    line += " | children=\(children.count) | images=\(images)"
                } else { line += " | children=unavailable" }
                var count: CFIndex = 0
                if AXUIElementGetAttributeValueCount(element, kAXRowsAttribute as CFString, &count) == .success {
                    line += " | rows=\(count)"
                }
            }
            return line
        }.joined(separator: "\n")
    }
}
