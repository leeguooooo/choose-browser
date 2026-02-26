import Foundation

protocol AppSettingsStoring: AnyObject {
    var fallbackBundleIdentifier: String? { get set }
    var hiddenBundleIdentifiers: Set<String> { get set }
    func reset()
}

final class UserDefaultsAppSettingsStore: AppSettingsStoring {
    private enum Keys {
        static let fallbackBundleIdentifier = "settings.fallbackBundleIdentifier"
        static let hiddenBundleIdentifiers = "settings.hiddenBundleIdentifiers"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var fallbackBundleIdentifier: String? {
        get {
            userDefaults.string(forKey: Keys.fallbackBundleIdentifier)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.fallbackBundleIdentifier)
        }
    }

    var hiddenBundleIdentifiers: Set<String> {
        get {
            let values = userDefaults.array(forKey: Keys.hiddenBundleIdentifiers) as? [String] ?? []
            return Set(values)
        }
        set {
            userDefaults.set(Array(newValue).sorted(), forKey: Keys.hiddenBundleIdentifiers)
        }
    }

    func reset() {
        userDefaults.removeObject(forKey: Keys.fallbackBundleIdentifier)
        userDefaults.removeObject(forKey: Keys.hiddenBundleIdentifiers)
    }
}
