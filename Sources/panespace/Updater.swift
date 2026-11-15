import AppKit
import Sparkle

/// Sparkle auto-updates from the appcast attached to each GitHub release (`SUFeedURL` in Info.plist).
///
/// Only runs from a real Panespace.app that carries the release signing key (`SUPublicEDKey`, added by
/// `make app` from Resources/sparkle-public-key): a dev build run out of .build, or the CLI, never checks.
final class Updater {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?

    /// Updates are possible in this build (bundled app with a signing key).
    var isAvailable: Bool { controller != nil }

    func start() {
        guard controller == nil, Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else {
            return log("updates: off (not a release build with a signing key)")
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// From the menu: Panespace has no Dock icon, so come to the front for Sparkle's window.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
}
