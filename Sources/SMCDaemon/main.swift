import Darwin
import Foundation
import SMCHelper

private let socketPath = "/var/run/magsafe-dark.sock"
private let allowedValues: [String: UInt8] = [
    "system": 0,
    "off": 1,
    "green": 3,
    "orange": 4,
    "flash": 5,
    "blink-slow": 6,
    "blink-fast": 7,
    "blink-off": 19
]

private func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

private func makeAddress() -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    let maxLength = MemoryLayout.size(ofValue: address.sun_path)
    socketPath.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            destination.withMemoryRebound(to: CChar.self, capacity: maxLength) { pointer in
                strncpy(pointer, source, maxLength - 1)
                pointer[maxLength - 1] = 0
            }
        }
    }
    return address
}

private func consoleUserID() -> uid_t? {
    var info = stat()
    guard stat("/dev/console", &info) == 0 else { return nil }
    return info.st_uid
}

private func isAuthorized(peerUID: uid_t) -> Bool {
    if peerUID == 0 { return true }
    guard let consoleUID = consoleUserID(), consoleUID != 0 else { return false }
    return peerUID == consoleUID
}

private func sendResponse(_ fd: Int32, status: Int32, body: String) {
    let payload = "\(status)\t\(body.replacingOccurrences(of: "\n", with: " "))\n"
    payload.withCString { pointer in
        _ = Darwin.write(fd, pointer, strlen(pointer))
    }
}

private func process(_ command: String) -> (Int32, String) {
    if command == "ping" { return (0, "pong") }

    if command == "probe" || command == "status" {
        var value: UInt8 = 0
        let result = smc_read_u8("ACLC", &value)
        guard result == 0 else {
            return (69, "Unable to read ACLC (IOKit error \(result)). This Mac may not support MagSafe LED control.")
        }
        return command == "probe" ? (0, "supported") : (0, String(value))
    }

    guard let value = allowedValues[command] else {
        return (64, "Unknown command")
    }
    let result = smc_write_u8("ACLC", value)
    guard result == 0 else {
        return (69, "Unable to write ACLC (IOKit error \(result)). This Mac may not support MagSafe LED control.")
    }
    return (0, "ok")
}

guard geteuid() == 0 else { fail("magsafe-led-daemon must run as root", code: 77) }

unlink(socketPath)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { fail("socket failed: \(String(cString: strerror(errno)))") }

var address = makeAddress()
let bindResult = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(server, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bindResult == 0 else { fail("bind failed: \(String(cString: strerror(errno)))") }
guard chmod(socketPath, 0o666) == 0 else { fail("chmod failed: \(String(cString: strerror(errno)))") }
guard listen(server, 16) == 0 else { fail("listen failed: \(String(cString: strerror(errno)))") }

signal(SIGPIPE, SIG_IGN)

while true {
    let client = accept(server, nil, nil)
    if client < 0 {
        if errno == EINTR { continue }
        fail("accept failed: \(String(cString: strerror(errno)))")
    }

    autoreleasepool {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0 else {
            sendResponse(client, status: 77, body: "Unable to identify client")
            close(client)
            return
        }
        guard isAuthorized(peerUID: peerUID) else {
            sendResponse(client, status: 77, body: "Client is not the active console user")
            close(client)
            return
        }

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(client, &buffer, buffer.count - 1)
        guard count > 0 else {
            sendResponse(client, status: 64, body: "Empty command")
            close(client)
            return
        }

        let data = Data(buffer.prefix(Int(count)))
        let command = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.contains("\0"), command.count <= 64 else {
            sendResponse(client, status: 64, body: "Invalid command")
            close(client)
            return
        }
        let result = process(command)
        sendResponse(client, status: result.0, body: result.1)
        close(client)
    }
}
