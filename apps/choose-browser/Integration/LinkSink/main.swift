import Foundation

struct LinkSinkRecord: Codable {
    let requestURL: String
    let targetBundleIdentifier: String
    let receivedAt: TimeInterval
}

@discardableResult
private func writeRecord() -> Int32 {
    let outputPath = ProcessInfo.processInfo.environment["LINKSINK_OUTPUT_PATH"] ??
        (NSTemporaryDirectory() as NSString).appendingPathComponent("choose-browser-linksink.json")
    let arguments = CommandLine.arguments.dropFirst()
    guard let requestURL = arguments.first else {
        return 2
    }

    let record = LinkSinkRecord(
        requestURL: requestURL,
        targetBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.choosebrowser.linksink",
        receivedAt: Date().timeIntervalSince1970
    )

    let outputURL = URL(fileURLWithPath: outputPath)
    do {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(record)
        try data.write(to: outputURL, options: .atomic)
        return 0
    } catch {
        return 1
    }
}

exit(writeRecord())
