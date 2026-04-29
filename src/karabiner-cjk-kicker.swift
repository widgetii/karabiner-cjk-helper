// Tiny short-lived helper. Spawned by karabiner-cjk-helper for every
// input-source switch. Calls TISSelectInputSource and, for CJK IMEs,
// runs the macism-style window-flash to engage the IME server.
//
// Critical wrinkle: macOS has a long-documented bug where switching
// directly between a non-ASCII keyboard layout (Russian, Arabic, …)
// and a CJK IME leaves the underlying ASCII layout half-resolved —
// menu bar updates, but typing routes through the wrong layout.
// Apple's own published workaround is to interpose an ASCII-capable
// layout (e.g. ABC) between the two. We do that here when needed.
//   See: https://discussions.apple.com/thread/8197631
//   And: TISSetInputMethodKeyboardLayoutOverride header documentation
//        ("most-recently-used ASCII-capable keyboard layout").

import AppKit
import Carbon

guard CommandLine.arguments.count >= 2 else { exit(1) }
let target = CommandLine.arguments[1]

// Build a snapshot of all keyboard input sources, indexed by id.
guard let unmanaged = TISCreateInputSourceList(nil, false) else { exit(2) }
let list = unmanaged.takeRetainedValue() as! [TISInputSource]

func id(of src: TISInputSource) -> String {
    if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    return ""
}

func isAsciiCapable(_ src: TISInputSource) -> Bool {
    guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsASCIICapable) else { return false }
    let b = Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue()
    return CFBooleanGetValue(b)
}

let byId: [String: TISInputSource] = Dictionary(uniqueKeysWithValues: list.map { (id(of: $0), $0) })
guard let targetSrc = byId[target] else { exit(3) }

func looksLikeCJK(_ id: String) -> Bool {
    return id.contains("inputmethod") || id.contains("SCIM") ||
           id.contains("TCIM") || id.contains("TYIM")
}

let isTargetCJK = looksLikeCJK(target)
let currentSrc = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let currentId = id(of: currentSrc)
let isCurrentCJK = looksLikeCJK(currentId)

// Pick the ASCII Latin layout we'll pin the IME to (and use as a transit
// layout when leaving a CJK IME for a non-ASCII target).
// The Latin layout we pin the IME to (and use as the transit layout when
// leaving a CJK IME for a non-ASCII target). Prefer Colemak first because
// the user types in Colemak — pinning Pinyin to ABC/QWERTY would mean
// their muscle-memory keystrokes produce the wrong pinyin syllables.
func pickAsciiLatin() -> TISInputSource? {
    let prefer = [
        "com.apple.keylayout.Colemak",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US",
    ]
    for pid in prefer { if let s = byId[pid] { return s } }
    for s in list where isAsciiCapable(s) && !looksLikeCJK(id(of: s)) {
        return s
    }
    return nil
}

if isTargetCJK {
    // If we're coming from a non-ASCII layout (e.g. Russian), pre-switch
    // through ABC so the IME has a clean ASCII layout to bind to. Then
    // select the IME, give the IME server a moment, and pin the override.
    if !isAsciiCapable(currentSrc), let abc = pickAsciiLatin() {
        TISSelectInputSource(abc)
        usleep(20_000)
    }
    TISSelectInputSource(targetSrc)
    usleep(15_000)
    if let abc = pickAsciiLatin() {
        TISSetInputMethodKeyboardLayoutOverride(abc)
    }
} else if isCurrentCJK && !isAsciiCapable(targetSrc) {
    // Leaving a CJK IME for a non-ASCII target (e.g. Pinyin → Russian).
    // Two-step via ABC with a brief gap so the second call isn't coalesced.
    if let abc = pickAsciiLatin() {
        TISSelectInputSource(abc)
        usleep(40_000) // 40 ms
    }
    TISSelectInputSource(targetSrc)
} else {
    // Plain switch (Colemak ↔ Russian, or back to a Latin layout).
    TISSelectInputSource(targetSrc)
}

// Non-CJK targets are done. CJK still needs the activation window.
if !isTargetCJK { exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else { exit(0) }
let frame = screen.visibleFrame
let rect = NSRect(x: frame.maxX - 11, y: frame.minY + 8, width: 3, height: 3)

let window = NSWindow(contentRect: rect,
                      styleMask: [.titled],
                      backing: .buffered,
                      defer: false)
window.isOpaque = true
window.backgroundColor = .purple
window.titlebarAppearsTransparent = true
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.makeKeyAndOrderFront(nil)

if #available(macOS 14, *) {
    app.activate()
} else {
    app.activate(ignoringOtherApps: true)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.080) {
    app.terminate(nil)
}
app.run()
