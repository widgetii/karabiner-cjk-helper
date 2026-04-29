// Focused Russian↔Pinyin alternation test through the daemon, in TextEdit.

import Carbon
import Foundation

setbuf(stdout, nil)

let TRIGGER = "/usr/local/bin/karabiner-cjk-trigger"
let RU = "com.apple.keylayout.Russian"
let ZH = "com.apple.inputmethod.SCIM.ITABC"
let CO = "com.apple.keylayout.Colemak"

func runOsa(_ script: String) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
    do { try task.run(); task.waitUntilExit() } catch { return "" }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func runTrigger(_ id: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: TRIGGER)
    task.arguments = [id]
    do { try task.run(); task.waitUntilExit() } catch { }
}

func currentSource() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    return "?"
}

func resetTextEdit() {
    _ = runOsa(#"""
    tell application "TextEdit"
        activate
        if (count of documents) is 0 then make new document
        set text of document 1 to ""
    end tell
    """#)
}

func keystroke(_ s: String) {
    var script = #"tell application "System Events""# + "\n"
    for ch in s {
        script += "    keystroke \"\(ch)\"\n    delay 0.07\n"
    }
    script += "end tell"
    _ = runOsa(script)
}

func readDoc() -> String {
    return runOsa(#"tell application "TextEdit" to return text of document 1"#)
}

let n = Int(CommandLine.arguments.dropFirst().first ?? "20") ?? 20
print("focused RU↔ZH stress in TextEdit: \(n) cycles")

_ = runOsa(#"tell application "TextEdit" to activate"#)
Thread.sleep(forTimeInterval: 1.0)
runTrigger(CO)
Thread.sleep(forTimeInterval: 0.3)

var results: [(target: String, typed: String, pass: Bool)] = []

for i in 1...n {
    let target = (i % 2 == 1) ? RU : ZH
    let label = (target == RU) ? "RU" : "ZH"
    let keys = (target == RU) ? "abc" : "nihao1"

    resetTextEdit()
    Thread.sleep(forTimeInterval: 0.15)
    runTrigger(target)
    Thread.sleep(forTimeInterval: 0.4)
    _ = runOsa(#"tell application "TextEdit" to activate"#)
    Thread.sleep(forTimeInterval: 0.15)

    let tis = currentSource()
    keystroke(keys)
    Thread.sleep(forTimeInterval: 0.5)
    let typed = readDoc()

    let pass: Bool
    if target == RU {
        pass = typed.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
    } else {
        pass = typed.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
    }
    results.append((label, typed, pass))
    let tisShort = tis.replacingOccurrences(of: "com.apple.", with: "")
    print("\(i)/\(n)  \(label) (tis=\(tisShort))  typed=\"\(typed)\"  \(pass ? "OK" : "FAIL")")
}

runTrigger(CO)
let ru = results.filter { $0.target == "RU" }
let zh = results.filter { $0.target == "ZH" }
print("\nRU: \(ru.filter { $0.pass }.count)/\(ru.count)")
print("ZH: \(zh.filter { $0.pass }.count)/\(zh.count)")
