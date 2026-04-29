// Minimal long-lived daemon. Listens on a UNIX socket and forwards each
// input-source-id received to /usr/local/bin/karabiner-cjk-kicker as a
// fresh, session-detached subprocess. Does NOT touch any Carbon/TIS APIs
// itself — empirically the mere presence of TIS-related code in the
// daemon (TISCreateInputSourceList at startup, DistributedNotificationCenter
// observer for kTISNotify…) appears to leak IME state and cause
// intermittent half-switch failures in real-time use even when the
// daemon's TIS calls are never invoked. The kicker is fully self-contained
// for input-source switching.

import Foundation

let SOCKET_PATH = "/tmp/karabiner-cjk-helper.sock"
let KICKER_PATH = "/usr/local/bin/karabiner-cjk-kicker"

var listenFd: Int32 = -1

func setupSocket() -> Bool {
    unlink(SOCKET_PATH)
    listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listenFd >= 0 else { return false }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = SOCKET_PATH.utf8CString
    withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
        for i in 0..<min(pathBytes.count, ptr.count) {
            ptr[i] = UInt8(bitPattern: pathBytes[i])
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(listenFd, $0, len)
        }
    }
    guard bindResult >= 0 else {
        NSLog("karabiner-cjk-helper: bind failed errno=\(errno)")
        return false
    }
    chmod(SOCKET_PATH, 0o666)
    return listen(listenFd, 16) >= 0
}

func spawnKicker(target: String) {
    var attrs = posix_spawnattr_t(nil as OpaquePointer?)
    posix_spawnattr_init(&attrs)
    // SETSID detaches the kicker from the daemon's session, which is
    // required for the kicker to be treated as a "valid TSM client" by
    // macOS — children of faceless launchd agents are otherwise treated
    // as background even with .accessory activation policy.
    posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID))
    defer { posix_spawnattr_destroy(&attrs) }

    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = [
        strdup(KICKER_PATH),
        strdup(target),
        nil,
    ]
    defer { for p in argv { free(p) } }

    let result = argv.withUnsafeBufferPointer { argvBuf -> Int32 in
        return posix_spawn(&pid, KICKER_PATH, nil, &attrs,
                           argvBuf.baseAddress, environ)
    }
    if result != 0 {
        NSLog("karabiner-cjk-helper: posix_spawn failed errno=\(result)")
    }
}

func handleClient(_ fd: Int32) {
    defer { close(fd) }
    var buf = [UInt8](repeating: 0, count: 256)
    let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
        return read(fd, bp.baseAddress, bp.count - 1)
    }
    guard n > 0 else { return }
    let id = String(bytes: buf[0..<n], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if id.isEmpty { return }
    NSLog("karabiner-cjk-helper: request id=\(id)")
    spawnKicker(target: id)
}

func acceptLoop() {
    while true {
        let client = accept(listenFd, nil, nil)
        if client < 0 {
            if errno == EINTR { continue }
            NSLog("karabiner-cjk-helper: accept failed errno=\(errno)")
            continue
        }
        DispatchQueue.global(qos: .userInteractive).async {
            handleClient(client)
        }
    }
}

guard setupSocket() else {
    NSLog("karabiner-cjk-helper: failed to set up socket")
    exit(1)
}

DispatchQueue.global(qos: .userInteractive).async {
    acceptLoop()
}

NSLog("karabiner-cjk-helper: ready, listening on \(SOCKET_PATH)")
CFRunLoopRun()
