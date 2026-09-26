#if FOCUS_DESK_UPDATES
import AppKit
import Combine
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class AppUpdateService: NSObject, SPUUpdaterDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var startupError: String?
    var installationStateChanged: ((Bool) -> Void)?
    var workspaceAvailable: (() -> Bool)?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: AnyCancellable?
    @ObservationIgnored private var configuration: AppUpdateConfiguration?

    override init() {
        super.init()
        do {
            #if FOCUS_DESK_UPDATE_TESTING
            let allowLocalTesting = true
            #else
            let allowLocalTesting = false
            #endif
            configuration = try AppUpdateConfiguration(info: Bundle.main.infoDictionary ?? [:],
                                                       allowLocalTesting: allowLocalTesting)
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            let updater = controller.updater
            updater.clearFeedURLFromUserDefaults()
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
            updater.sendsSystemProfile = false
            observation = updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in
                    MainActor.assumeIsolated { self?.canCheckForUpdates = value }
                }
            try updater.start()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard startupError == nil else {
            let alert = NSAlert()
            alert.messageText = "Updates are unavailable"
            alert.informativeText = startupError ?? ""
            alert.runModal()
            return
        }
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuration?.feedURL.absoluteString
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard workspaceAvailable?() == true else { throw UpdatePreparationError.workspaceUnavailable }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // applicationShouldTerminate performs the last save and requires a recovery copy.
        installationStateChanged?(true)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installationStateChanged?(false)
    }
}
#endif
