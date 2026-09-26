import Foundation

struct AppUpdateConfiguration {
    let feedURL: URL

    init(info: [String: Any], allowLocalTesting: Bool = false) throws {
        guard let address = info["SUFeedURL"] as? String,
              let url = URL(string: address), url.user == nil, url.password == nil,
              url.fragment == nil, let host = url.host, !host.isEmpty,
              url.scheme == "https" || (allowLocalTesting && url.scheme == "http" && host == "127.0.0.1"),
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUEnableInstallerLauncherService"] as? Bool == true,
              info["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
              info["SUEnableAutomaticChecks"] as? Bool == false,
              info["SUAllowsAutomaticUpdates"] as? Bool == false,
              info["SUAutomaticallyUpdate"] as? Bool == false,
              info["SUSendProfileInfo"] as? Bool == false else {
            throw UpdatePreparationError.invalidConfiguration
        }
        feedURL = url
    }
}

enum UpdatePreparationError: LocalizedError {
    case invalidConfiguration
    case saveFailed
    case workspaceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "This build does not have a valid, signed update configuration."
        case .saveFailed: "Your changes could not be saved. The update has been postponed."
        case .workspaceUnavailable: "Restore or open your workspace before installing an update."
        }
    }
}
