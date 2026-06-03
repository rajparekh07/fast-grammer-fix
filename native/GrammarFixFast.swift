import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

struct HotkeyConfig {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String
}

final class Bubble {
    private var window: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    func show(_ message: String, autoHideAfter delay: TimeInterval? = nil) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.ensureWindow()
            self.label.stringValue = message
            self.reposition()
            self.window?.orderFrontRegardless()

            if let delay {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.window?.orderOut(nil)
                }
                self.hideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }

    private func ensureWindow() {
        guard window == nil else {
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 380, height: 64)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.appearance = NSAppearance(named: .vibrantDark)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        visualEffect.layer?.borderWidth = 1

        label.frame = NSRect(x: 22, y: 18, width: rect.width - 44, height: 28)
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            return shadow
        }()
        visualEffect.addSubview(label)

        panel.contentView = visualEffect
        window = panel
    }

    private func reposition() {
        guard let window else {
            return
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let x = screen.midX - window.frame.width / 2
        let y = screen.maxY - window.frame.height - 28
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class HotkeyController {
    private let bubble = Bubble()
    private var hotKeyRef: EventHotKeyRef?
    private var busy = false
    private var didRequestAccessibilityAccess = false
    private var hotkeyConfig = parseHotkey("ctrl+option+cmd+g")

    func start() {
        let config = parseHotkey(ProcessInfo.processInfo.environment["GRAMMER_FIX_HOTKEY"] ?? "ctrl+option+cmd+g")
        hotkeyConfig = config
        installHotkeyHandler()

        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            EventHotKeyID(signature: fourCharCode("GFix"), id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            fputs("Grammar Fix ready: \(config.displayName)\n", stdout)
            fflush(stdout)
            bubble.show("Grammar Fix ready: \(config.displayName)", autoHideAfter: 2.0)
        } else {
            fputs("Could not register hotkey: \(status)\n", stderr)
            fflush(stderr)
            bubble.show("Could not register hotkey", autoHideAfter: 4.0)
        }
    }

    func handleHotkey() {
        guard !busy else {
            bubble.show("Still working...", autoHideAfter: 1.5)
            return
        }

        guard isAccessibilityTrusted() else {
            requestAccessibilityAccess()
            bubble.show("Allow Accessibility access for Grammar Fix", autoHideAfter: 5.0)
            return
        }

        busy = true
        bubble.show("Reading selection...")

        let previousPasteboard = snapshotPasteboard()

        waitForHotkeyRelease {
            guard let selectedText = self.copySelectedText(), selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                self.restorePasteboard(previousPasteboard)
                self.busy = false
                self.bubble.show("No selected text", autoHideAfter: 2.0)
                return
            }

            self.bubble.show("Asking Codex...")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let replacement = try self.runRewrite(selectedText)
                    DispatchQueue.main.async {
                        self.pasteReplacement(replacement, restoreTo: previousPasteboard)
                        self.busy = false
                        self.bubble.show("Replaced selection", autoHideAfter: 1.8)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.restorePasteboard(previousPasteboard)
                        self.busy = false
                        self.bubble.show("Codex failed", autoHideAfter: 3.0)
                        fputs("Grammar Fix error: \(error)\n", stderr)
                    }
                }
            }
        }
    }

    private func waitForHotkeyRelease(completion: @escaping () -> Void) {
        waitForHotkeyRelease(until: Date().addingTimeInterval(0.8), completion: completion)
    }

    private func waitForHotkeyRelease(until deadline: Date, completion: @escaping () -> Void) {
        guard Date() < deadline, isAnyHotkeyKeyPressed() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.waitForHotkeyRelease(until: deadline, completion: completion)
        }
    }

    private func isAnyHotkeyKeyPressed() -> Bool {
        let keys: [UInt32] = [
            hotkeyConfig.keyCode,
            UInt32(kVK_Command),
            UInt32(kVK_RightCommand),
            UInt32(kVK_Control),
            UInt32(kVK_RightControl),
            UInt32(kVK_Option),
            UInt32(kVK_RightOption),
            UInt32(kVK_Shift),
            UInt32(kVK_RightShift),
        ]

        return keys.contains { keyCode in
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        }
    }

    private func installHotkeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                AppDelegate.shared?.controller.handleHotkey()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    private func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestAccessibilityAccess() {
        guard !didRequestAccessibilityAccess else {
            return
        }

        didRequestAccessibilityAccess = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openAccessibilitySettings()
    }

    private func openAccessibilitySettings() {
        guard ProcessInfo.processInfo.environment["GRAMMER_FIX_OPEN_ACCESSIBILITY_SETTINGS"] != "0",
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func copySelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let startingChangeCount = pasteboard.changeCount
        keyTap(UInt16(kVK_ANSI_C), flags: .maskCommand)

        let deadline = Date().addingTimeInterval(1.4)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
            if pasteboard.changeCount != startingChangeCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func pasteReplacement(_ text: String, restoreTo snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        keyTap(UInt16(kVK_ANSI_V), flags: .maskCommand)

        if ProcessInfo.processInfo.environment["GRAMMER_FIX_RESTORE_CLIPBOARD"] != "0" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.restorePasteboard(snapshot)
            }
        }
    }

    private func runRewrite(_ text: String) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let scriptPath = environment["GRAMMER_FIX_SCRIPT"], FileManager.default.fileExists(atPath: scriptPath) else {
            throw RuntimeError("GRAMMER_FIX_SCRIPT is missing or invalid.")
        }

        let nodePath = environment["GRAMMER_FIX_NODE"] ?? "/usr/bin/env"
        let process = Process()
        if nodePath == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", scriptPath]
        } else {
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [scriptPath]
        }

        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(text.utf8))
        inputPipe.fileHandleForWriting.closeFile()

        let timeout = TimeInterval(environment["GRAMMER_FIX_TIMEOUT_SECONDS"] ?? "210") ?? 210
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw RuntimeError("Timed out waiting for Codex.")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw RuntimeError(errorOutput.isEmpty ? "Rewrite command failed." : errorOutput)
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RuntimeError("Rewrite command returned empty output.")
        }

        return output
    }

    private func snapshotPasteboard() -> PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]] = NSPasteboard.general.pasteboardItems?.map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let items = snapshot.items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }

        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    let controller = HotkeyController()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func keyTap(_ keyCode: UInt16, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.localEventsSuppressionInterval = 0

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    keyDown?.post(tap: .cghidEventTap)

    usleep(35_000)

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags
    keyUp?.post(tap: .cghidEventTap)
}

func parseHotkey(_ value: String) -> HotkeyConfig {
    let parts = value
        .lowercased()
        .split(separator: "+")
        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var modifiers: UInt32 = 0
    var displayParts: [String] = []
    var key = "g"

    for part in parts {
        switch part {
        case "cmd", "command":
            modifiers |= UInt32(cmdKey)
            displayParts.append("cmd")
        case "ctrl", "control":
            modifiers |= UInt32(controlKey)
            displayParts.append("ctrl")
        case "opt", "option", "alt":
            modifiers |= UInt32(optionKey)
            displayParts.append("option")
        case "shift":
            modifiers |= UInt32(shiftKey)
            displayParts.append("shift")
        default:
            key = part
        }
    }

    let keyCode = keyCodes()[key] ?? UInt32(kVK_ANSI_G)
    displayParts.append(key.uppercased())

    return HotkeyConfig(keyCode: keyCode, modifiers: modifiers, displayName: displayParts.joined(separator: "+"))
}

func keyCodes() -> [String: UInt32] {
    return [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
    ]
}

func fourCharCode(_ value: String) -> OSType {
    return value.utf8.reduce(0) { result, char in
        return (result << 8) + OSType(char)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
