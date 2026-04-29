import Carbon
import Cocoa

setbuf(stdout, nil)

func prop(_ src: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(src, key) else { return "-" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

let fmt = DateFormatter()
fmt.dateFormat = "HH:mm:ss.SSS"

var lastID = ""
var lastMode = ""

print("Polling current input source. Tap your language-switch keys; only changes are printed.")
print("Press Ctrl-C to quit.\n")

while true {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let id = prop(s, kTISPropertyInputSourceID)
    let mode = prop(s, kTISPropertyInputModeID)
    let name = prop(s, kTISPropertyLocalizedName)
    if id != lastID || mode != lastMode {
        let t = fmt.string(from: Date())
        print("[\(t)] id=\(id)  mode=\(mode)  name=\(name)")
        lastID = id
        lastMode = mode
    }
    Thread.sleep(forTimeInterval: 0.1)
}
