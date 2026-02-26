import Foundation

// Scaffold target for Safari extension bridge transport wiring.
// Runtime broker integration remains in app module until packaging work starts.
let message = "SafariBridgeHost scaffold ready"
FileHandle.standardOutput.write(Data(message.utf8))
