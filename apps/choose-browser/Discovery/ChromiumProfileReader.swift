import Foundation

/// A single Chromium-family browser profile (Chrome, Edge, Brave, …).
struct ChromiumProfile: Equatable {
    /// On-disk profile directory, e.g. `Default` or `Profile 1`. This is the
    /// value passed to the browser via `--profile-directory=`.
    let directoryName: String
    /// Human-facing profile name, e.g. `Work` or `leo@example.com`.
    let displayName: String
}

protocol ChromiumProfileReading {
    /// Returns the profiles configured for the given browser bundle identifier,
    /// or an empty array when the browser is not Chromium-based, has no
    /// per-profile data, or exposes only a single profile.
    func profiles(forBundleIdentifier bundleIdentifier: String) -> [ChromiumProfile]
}

/// Reads Chromium's `Local State` JSON to enumerate user profiles.
///
/// Every Chromium-based browser stores a `Local State` file at the root of its
/// user-data directory containing a `profile.info_cache` map keyed by profile
/// directory name. We read it directly (read-only) rather than launching the
/// browser, so it is cheap and side-effect free.
struct LiveChromiumProfileReader: ChromiumProfileReading {
    /// Maps a browser bundle identifier to its user-data directory, relative to
    /// `~/Library/Application Support`. Arc/Dia are intentionally absent: they
    /// do not honor `--profile-directory`, and discovery already flags them as
    /// not supporting profile selection.
    static let userDataRelativePaths: [String: String] = [
        "com.google.chrome": "Google/Chrome",
        "com.google.chrome.beta": "Google/Chrome Beta",
        "com.google.chrome.dev": "Google/Chrome Dev",
        "com.google.chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.dev": "Microsoft Edge Dev",
        "com.brave.browser": "BraveSoftware/Brave-Browser",
        "com.brave.browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.vivaldi.vivaldi": "Vivaldi",
        "com.operasoftware.opera": "com.operasoftware.Opera",
        "ru.yandex.desktop.yandex-browser": "Yandex/YandexBrowser",
    ]

    private let fileManager: FileManager
    private let applicationSupportURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.applicationSupportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    func profiles(forBundleIdentifier bundleIdentifier: String) -> [ChromiumProfile] {
        guard let relativePath = Self.userDataRelativePaths[bundleIdentifier.lowercased()] else {
            return []
        }

        let localStateURL = applicationSupportURL
            .appendingPathComponent(relativePath, isDirectory: true)
            .appendingPathComponent("Local State", isDirectory: false)

        guard let data = try? Data(contentsOf: localStateURL) else {
            return []
        }

        return Self.parseProfiles(localStateData: data)
    }

    /// Pure parser over a Chromium `Local State` payload. Exposed for testing.
    static func parseProfiles(localStateData: Data) -> [ChromiumProfile] {
        guard
            let root = (try? JSONSerialization.jsonObject(with: localStateData)) as? [String: Any],
            let profileSection = root["profile"] as? [String: Any],
            let infoCache = profileSection["info_cache"] as? [String: Any]
        else {
            return []
        }

        let orderedDirectories = orderedDirectoryNames(
            infoCache: infoCache,
            profilesOrder: profileSection["profiles_order"] as? [String]
        )

        return orderedDirectories.compactMap { directoryName in
            guard let info = infoCache[directoryName] as? [String: Any] else {
                return nil
            }

            return ChromiumProfile(
                directoryName: directoryName,
                displayName: displayName(for: info, directoryName: directoryName)
            )
        }
    }

    private static func orderedDirectoryNames(
        infoCache: [String: Any],
        profilesOrder: [String]?
    ) -> [String] {
        let allDirectories = Array(infoCache.keys)

        guard let profilesOrder, !profilesOrder.isEmpty else {
            return allDirectories.sorted(by: defaultDirectoryOrder)
        }

        // Honor Chromium's own profile ordering, appending any directories it
        // does not mention (sorted) so nothing is dropped.
        let known = Set(profilesOrder)
        let remainder = allDirectories.filter { !known.contains($0) }.sorted(by: defaultDirectoryOrder)
        return profilesOrder.filter { infoCache[$0] != nil } + remainder
    }

    private static func defaultDirectoryOrder(_ lhs: String, _ rhs: String) -> Bool {
        // "Default" always sorts first; the rest case-insensitively.
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private static func displayName(for info: [String: Any], directoryName: String) -> String {
        let candidateKeys = ["name", "gaia_name", "shortcut_name", "user_name"]

        for key in candidateKeys {
            if let value = info[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return directoryName
    }
}
