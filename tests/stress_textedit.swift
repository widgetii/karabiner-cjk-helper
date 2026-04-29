// Real-app end-to-end Pinyin/Russian/Colemak engagement test.
// Drives TextEdit via osascript, sends keystrokes via System Events
// (which routes through IME), reads document content via AppleScript.
//
// Compares 3 switching mechanisms side-by-side per cycle:
//   1. /usr/local/bin/karabiner-cjk-trigger  (daemon path)
//   2. /opt/homebrew/bin/macism              (baseline reference)
//   3. /usr/local/bin/karabiner-cjk-kicker   (skip the daemon's IPC)

import Carbon
import Foundation

setbuf(stdout, nil)

let TRIGGER = "/usr/local/bin/karabiner-cjk-trigger"
let MACISM  = "/opt/homebrew/bin/macism"
let KICKER  = "/usr/local/bin/karabiner-cjk-kicker"

let RU = "com.apple.keylayout.Russian"
let ZH = "com.apple.inputmethod.SCIM.ITABC"
let CO = "com.apple.keylayout.Colemak"

struct TestCase {
    let target: String
    let label: String
    let typeKeys: String        // characters to keystroke
    let classify: (String) -> Bool
}

let CASES: [TestCase] = [
    TestCase(target: CO, label: "Colemak", typeKeys: "abc",
             classify: { s in s == "abc" }),
    TestCase(target: RU, label: "Russian", typeKeys: "abc",
             classify: { s in s.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF } }),
    TestCase(target: ZH, label: "Chinese", typeKeys: "nihao1",
             classify: { s in s.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF } }),
]

func runOsa(_ script: String) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    let outPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return ""
    }
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func runProcess(_ path: String, _ args: [String]) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    do { try task.run(); task.waitUntilExit() } catch { }
}

func currentSource() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    return "(unknown)"
}

func resetTextEdit() {
    _ = runOsa("""
    tell application "TextEdit"
        activate
        if (count of documents) is 0 then make new document
        set text of document 1 to ""
    end tell
    """)
}

func readTextEdit() -> String {
    return runOsa(#"tell application "TextEdit" to return text of document 1"#)
}

func keystrokeChars(_ s: String) {
    // Send each character separately with a delay, so the IME can compose.
    var script = #"tell application "System Events""# + "\n"
    for ch in s {
        // Escape backslashes and quotes (none expected here, but safe).
        let safe = String(ch).replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        script += "    keystroke \"\(safe)\"\n"
        script += "    delay 0.07\n"
    }
    script += "end tell"
    _ = runOsa(script)
}

let mechanisms: [(name: String, switchTo: (String) -> Void)] = [
    ("trigger", { id in runProcess(TRIGGER, [id]) }),
    ("macism",  { id in runProcess(MACISM,  [id]) }),
    ("kicker",  { id in runProcess(KICKER,  [id]) }),
]

let cyclesPerMech = Int(CommandLine.arguments.dropFirst().first ?? "9") ?? 9

print("driving TextEdit; \(cyclesPerMech) cycles × \(mechanisms.count) mechanisms = \(cyclesPerMech * mechanisms.count) total")
print("DO NOT TOUCH KEYBOARD — TextEdit must keep focus throughout\n")

// Make sure TextEdit is up and ready.
_ = runOsa(#"tell application "TextEdit" to activate"#)
Thread.sleep(forTimeInterval: 1.5)
resetTextEdit()
Thread.sleep(forTimeInterval: 0.5)

// Always start from Colemak baseline.
runProcess(MACISM, [CO])
Thread.sleep(forTimeInterval: 0.3)

var summary: [(mech: String, target: String, pass: Bool)] = []

for (mechName, switchFn) in mechanisms {
    print("--- mechanism: \(mechName) ---")
    for i in 1...cyclesPerMech {
        let tc = CASES[i % CASES.count]

        resetTextEdit()
        Thread.sleep(forTimeInterval: 0.15)

        switchFn(tc.target)
        Thread.sleep(forTimeInterval: 0.4)

        // re-activate TextEdit in case kicker stole focus
        _ = runOsa(#"tell application "TextEdit" to activate"#)
        Thread.sleep(forTimeInterval: 0.15)

        let tis = currentSource()
        keystrokeChars(tc.typeKeys)
        Thread.sleep(forTimeInterval: 0.5)
        let typed = readTextEdit()
        let pass = tc.classify(typed)
        summary.append((mechName, tc.label, pass))

        let tisShort = tis.replacingOccurrences(of: "com.apple.", with: "")
        print("  \(i)/\(cyclesPerMech)  \(tc.label) (tis=\(tisShort))  typed=\"\(typed)\"  \(pass ? "OK" : "FAIL")")
    }
}

// restore Colemak before exit
runProcess(MACISM, [CO])

print("\n=== summary ===")
for mechName in mechanisms.map({ $0.name }) {
    for label in ["Colemak", "Russian", "Chinese"] {
        let attempts = summary.filter { $0.mech == mechName && $0.target == label }
        let passed   = attempts.filter { $0.pass }.count
        if !attempts.isEmpty {
            print("  \(mechName) × \(label): \(passed)/\(attempts.count)")
        }
    }
}
let total  = summary.count
let passed = summary.filter { $0.pass }.count
print("  TOTAL: \(passed)/\(total) (\(total > 0 ? passed * 100 / total : 0)%)")
