import Foundation

// Scaffold target for Chromium/Firefox native messaging host wiring.
// Security-hardening and signed distribution are intentionally out of scope for this scaffold.
let message = "NativeMessagingHost scaffold ready"
FileHandle.standardOutput.write(Data(message.utf8))
