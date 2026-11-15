import Foundation

/// Unix-socket IPC, i3-msg style. Request: "<type>\n<payload>"; response: JSON.
public enum IPC {
    /// In the per-user temporary directory (only this user can create files there), not shared /tmp, where
    /// another account could take the name first.
    public static let socketPath: String = {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let dir = confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, buf.count) > 0 ? String(cString: buf) : NSTemporaryDirectory()
        return (dir.hasSuffix("/") ? dir : dir + "/") + "panespace.sock"
    }()
    /// Where versions before 0.2 listened: still tried by `send`, so a CLI can reach (and stop) an older daemon.
    static var legacySocketPath: String { "/tmp/panespace-\(getuid()).sock" }

    private static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(path.utf8.prefix(buf.count - 1))
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// No SIGPIPE when the other side is gone (it would kill the daemon), and no read or write that waits forever
    /// on a client that never finishes its request.
    private static func configure(_ fd: Int32, timeout seconds: Int) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return }
                off += n
            }
        }
    }

    /// Returns nil when no daemon is listening.
    public static func send(type: String, payload: String) -> String? {
        send(type: type, payload: payload, to: socketPath) ?? send(type: type, payload: payload, to: legacySocketPath)
    }

    private static func send(type: String, payload: String, to path: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        configure(fd, timeout: 15)  // a busy daemon can take a while; a wedged one mustn't hang the CLI forever
        guard withAddress(path, { connect(fd, $0, $1) }) == 0 else { return nil }
        writeAll(fd, Data("\(type)\n\(payload)".utf8))
        shutdown(fd, SHUT_WR)
        return String(decoding: readAll(fd), as: UTF8.self)
    }

    /// Accepts connections on a background thread; `handler` runs on the main thread.
    /// `offMain` answers first, on the IPC thread, for requests that would block the main thread (nil = not
    /// mine); everything else goes to `handler` on the main thread.
    public static func serve(_ handler: @escaping (_ type: String, _ payload: String) -> String,
                             offMain: ((_ type: String, _ payload: String) -> String?)? = nil) -> Bool {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withAddress(socketPath, { bind(fd, $0, $1) }) == 0, listen(fd, 16) == 0 else { return false }
        chmod(socketPath, 0o600)
        let thread = Thread {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                configure(client, timeout: 2)  // one stuck client must not block every later one
                let req = String(decoding: readAll(client), as: UTF8.self)
                let (type, payload) = req.firstIndex(of: "\n").map {
                    (String(req[..<$0]), String(req[req.index(after: $0)...]))
                } ?? (req, "")
                let resp = offMain?(type, payload) ?? DispatchQueue.main.sync { handler(type, payload) }
                writeAll(client, Data(resp.utf8))
                close(client)
            }
        }
        thread.name = "panespace.ipc"
        thread.start()
        return true
    }

    public static func json(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys]) else { return "null" }
        return String(decoding: d, as: UTF8.self)
    }
}
