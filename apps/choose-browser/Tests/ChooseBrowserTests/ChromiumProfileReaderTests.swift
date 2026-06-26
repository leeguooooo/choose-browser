import Foundation

#if canImport(XCTest)
import XCTest
@testable import ChooseBrowser

final class ChromiumProfileReaderTests: XCTestCase {
    func testParsesProfilesInDeclaredOrder() throws {
        let json = """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "Personal" },
              "Profile 1": { "name": "Work" }
            },
            "profiles_order": ["Default", "Profile 1"]
          }
        }
        """

        let profiles = LiveChromiumProfileReader.parseProfiles(localStateData: Data(json.utf8))

        XCTAssertEqual(
            profiles,
            [
                ChromiumProfile(directoryName: "Default", displayName: "Personal"),
                ChromiumProfile(directoryName: "Profile 1", displayName: "Work"),
            ]
        )
    }

    func testFallsBackToGaiaNameThenDirectory() throws {
        let json = """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "", "gaia_name": "leo@example.com" },
              "Profile 7": { }
            }
          }
        }
        """

        let profiles = LiveChromiumProfileReader.parseProfiles(localStateData: Data(json.utf8))
            .sorted { $0.directoryName < $1.directoryName }

        XCTAssertEqual(
            profiles,
            [
                ChromiumProfile(directoryName: "Default", displayName: "leo@example.com"),
                ChromiumProfile(directoryName: "Profile 7", displayName: "Profile 7"),
            ]
        )
    }

    func testMalformedPayloadReturnsEmpty() throws {
        XCTAssertEqual(LiveChromiumProfileReader.parseProfiles(localStateData: Data("not json".utf8)), [])
        XCTAssertEqual(LiveChromiumProfileReader.parseProfiles(localStateData: Data("{}".utf8)), [])
    }

    func testNonChromiumBundleHasNoProfiles() {
        let reader = LiveChromiumProfileReader()
        XCTAssertEqual(reader.profiles(forBundleIdentifier: "com.apple.Safari"), [])
    }
}
#endif
