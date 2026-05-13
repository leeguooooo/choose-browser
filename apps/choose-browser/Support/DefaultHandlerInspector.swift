import AppKit
import CoreServices
import Foundation

enum DefaultBrowserStatus: String, Equatable {
    case configured
    case partial
    case notConfigured = "not configured"
}

struct DefaultHandlerSnapshot: Equatable {
    let appBundleIdentifier: String
    let httpHandlerBundleIdentifier: String?
    let httpsHandlerBundleIdentifier: String?
    let htmlDocumentHandlerBundleIdentifier: String?
    let xhtmlDocumentHandlerBundleIdentifier: String?

    var status: DefaultBrowserStatus {
        let matchesHTTP = httpHandlerBundleIdentifier == appBundleIdentifier
        let matchesHTTPS = httpsHandlerBundleIdentifier == appBundleIdentifier
        let matchesHTML = htmlDocumentHandlerBundleIdentifier == appBundleIdentifier
        let matchesXHTML = xhtmlDocumentHandlerBundleIdentifier == appBundleIdentifier

        if matchesHTTP && matchesHTTPS && matchesHTML && matchesXHTML {
            return .configured
        }

        if matchesHTTP || matchesHTTPS || matchesHTML || matchesXHTML {
            return .partial
        }

        return .notConfigured
    }
}

protocol DefaultHandlerInspecting {
    func currentDefaultHandlerBundleIdentifier(for scheme: String) -> String?
    func currentDefaultDocumentHandlerBundleIdentifier(forContentType contentType: String) -> String?
    func snapshot(appBundleIdentifier: String) -> DefaultHandlerSnapshot
    func openSystemDefaultBrowserSettings() -> Bool
    func setAsDefaultBrowser(bundleIdentifier: String) -> Bool
}

struct DefaultHandlerInspector: DefaultHandlerInspecting {
    func currentDefaultHandlerBundleIdentifier(for scheme: String) -> String? {
        LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?
    }

    func currentDefaultDocumentHandlerBundleIdentifier(forContentType contentType: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(contentType as CFString, .viewer)?.takeRetainedValue() as String?
    }

    func snapshot(appBundleIdentifier: String) -> DefaultHandlerSnapshot {
        DefaultHandlerSnapshot(
            appBundleIdentifier: appBundleIdentifier,
            httpHandlerBundleIdentifier: currentDefaultHandlerBundleIdentifier(for: "http"),
            httpsHandlerBundleIdentifier: currentDefaultHandlerBundleIdentifier(for: "https"),
            htmlDocumentHandlerBundleIdentifier: currentDefaultDocumentHandlerBundleIdentifier(forContentType: "public.html"),
            xhtmlDocumentHandlerBundleIdentifier: currentDefaultDocumentHandlerBundleIdentifier(forContentType: "public.xhtml")
        )
    }

    func openSystemDefaultBrowserSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.general?DefaultWebBrowser") else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    func setAsDefaultBrowser(bundleIdentifier: String) -> Bool {
        let statusHTTP = LSSetDefaultHandlerForURLScheme("http" as CFString, bundleIdentifier as CFString)
        let statusHTTPS = LSSetDefaultHandlerForURLScheme("https" as CFString, bundleIdentifier as CFString)
        let statusHTML = LSSetDefaultRoleHandlerForContentType("public.html" as CFString, .viewer, bundleIdentifier as CFString)
        let statusXHTML = LSSetDefaultRoleHandlerForContentType("public.xhtml" as CFString, .viewer, bundleIdentifier as CFString)
        let statusesSucceeded = [statusHTTP, statusHTTPS, statusHTML, statusXHTML].allSatisfy { $0 == noErr }

        // LaunchServices may return non-zero while defaults are already/effectively configured.
        if snapshot(appBundleIdentifier: bundleIdentifier).status == .configured {
            return true
        }

        return statusesSucceeded
    }
}
