import Foundation

/// Immersive mode (Omarchy-style): the macOS menu bar auto-hides, so tiles and fullscreen windows use the
/// whole display. Changes the real macOS setting through System Events (asks for Automation permission once)
/// and puts back what it found when panespace quits. The Dock is never touched: it follows its own macOS
/// setting (System Settings → Desktop & Dock → "Automatically hide and show the Dock").
final class MacChrome {
    private(set) var isImmersive: Bool
    /// The user's own setting, from before immersive mode changed it. Kept on disk too: after a crash or a kill
    /// while immersive, the next launch must not take "hidden" for the user's choice.
    private var original: Bool? {
        didSet {
            if let o = original { UserDefaults.standard.set(o, forKey: MacChrome.originalKey) }
            else { UserDefaults.standard.removeObject(forKey: MacChrome.originalKey) }
        }
    }
    private static let originalKey = "immersiveOriginalMenuBarHidden"
    /// One osascript at a time, in order: quick toggles must land as the last one asked.
    private let queue = DispatchQueue(label: "panespace.chrome")

    init() {
        isImmersive = MacChrome.menuBarHidden()
        original = UserDefaults.standard.object(forKey: MacChrome.originalKey) as? Bool
    }

    static func menuBarHidden() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["_HIHideMenuBar"] as? Bool) ?? false
    }

    func set(_ on: Bool) {
        guard on != isImmersive else { return }
        if original == nil { original = MacChrome.menuBarHidden() }
        isImmersive = on
        queue.async { [weak self] in
            guard let self, !self.write(menuBarHidden: on) else { return }
            // Refused (no Automation permission): the menu must say what the Mac actually does.
            DispatchQueue.main.async { self.isImmersive = MacChrome.menuBarHidden() }
        }
    }

    /// Called on quit: leave the user's Mac as panespace found it.
    func restore() {
        guard let o = original else { return }
        queue.sync {}  // a toggle still in flight goes first
        if write(menuBarHidden: o) { original = nil }
    }

    /// Waits for osascript; true when System Events accepted it.
    @discardableResult
    private func write(menuBarHidden: Bool) -> Bool {
        let script = """
        tell application "System Events" to tell dock preferences
            set autohide menu bar to \(menuBarHidden)
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            log("immersive: could not run osascript: \(error)")
            return false
        }
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            log("immersive: System Events refused (\(msg.trimmingCharacters(in: .whitespacesAndNewlines))). "
                + "Allow Panespace under System Settings → Privacy & Security → Automation.")
            return false
        }
        return true
    }
}
