import Foundation
import XCTest
@testable import FocusDesk

final class AppUpdateConfigurationTests: XCTestCase {
    private var settings: [String: Any] {
        ["SUFeedURL": "https://example.com/appcast.xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
         "SUVerifyUpdateBeforeExtraction": true,
         "SURequireSignedFeed": true,
         "SUEnableInstallerLauncherService": true,
         "SUSignedFeedFailureExpirationInterval": 0,
         "SUEnableAutomaticChecks": false,
         "SUAllowsAutomaticUpdates": false,
         "SUAutomaticallyUpdate": false,
         "SUSendProfileInfo": false]
    }

    func testProductionRequiresHTTPSAndValidPublicKey() throws {
        XCTAssertEqual(try AppUpdateConfiguration(info: settings).feedURL.host, "example.com")
        for address in ["http://example.com/feed", "file:///tmp/feed", "https://user:secret@example.com/feed",
                        "https://example.com/feed#fragment", "https://", "http://127.0.0.1/feed"] {
            var info = settings
            info["SUFeedURL"] = address
            XCTAssertThrowsError(try AppUpdateConfiguration(info: info), address)
        }
        for key in ["", "invalid", Data(repeating: 0, count: 31).base64EncodedString()] {
            var info = settings
            info["SUPublicEDKey"] = key
            XCTAssertThrowsError(try AppUpdateConfiguration(info: info))
        }
    }

    func testSecuritySettingsCannotBeMissingOrWeakened() {
        for key in settings.keys where key.hasPrefix("SU") {
            var info = settings
            info.removeValue(forKey: key)
            XCTAssertThrowsError(try AppUpdateConfiguration(info: info), key)
        }
        for (key, value) in settings where value is Bool {
            var info = settings
            info[key] = !(value as! Bool)
            XCTAssertThrowsError(try AppUpdateConfiguration(info: info), key)
        }
        var info = settings
        info["SUSignedFeedFailureExpirationInterval"] = 86400
        XCTAssertThrowsError(try AppUpdateConfiguration(info: info))
    }

    func testTestBuildExceptionIsLimitedToLoopback() throws {
        var info = settings
        info["SUFeedURL"] = "http://127.0.0.1:8765/appcast.xml"
        XCTAssertNoThrow(try AppUpdateConfiguration(info: info, allowLocalTesting: true))
        info["SUFeedURL"] = "http://example.com/appcast.xml"
        XCTAssertThrowsError(try AppUpdateConfiguration(info: info, allowLocalTesting: true))
    }
}
