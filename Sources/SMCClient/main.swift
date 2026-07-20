import Darwin
import Foundation

private let socketPath = ProcessInfo.processInfo.environment["MAGSAFE_DARK_SOCKET"] ?? "/var/run/magsafe-dark.sock"
private let allowed = Set(["ping", "probe", "status", "system", "off", "green", "orange", "flash", "blink-slow", "blink-fast", "blink-off"])

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

let arguments = CommandLine.arguments
let command = arguments.count == 2 ? arguments[1] : ""
guard allowed.contains(command) else {
    fail("Usage: magsafe-led-client ping|probe|status|off|system|green|orange|flash|blink-slow|blink-fast|blink-off", code: 64)
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { fail("socket failed: \(String(cString: strerror(errno)))") }
defer { close(fd) }

var address = makeAddress()
let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else {
    fail("MagSafe Dark daemon is unavailable at \(socketPath): \(String(cString: strerror(errno))). Reinstall MagSafe Dark.", code: 69)
}

let request = command + "\n"
request.withCString { pointer in
    _ = Darwin.write(fd, pointer, strlen(pointer))
}
shutdown(fd, SHUT_WR)

var responseData = Data()
var buffer = [UInt8](repeating: 0, count: 512)
while true {
    let count = Darwin.read(fd, &buffer, buffer.count)
    if count < 0 {
        if errno == EINTR { continue }
        fail("read failed: \(String(cString: strerror(errno)))")
    }
    if count == 0 { break }
    responseData.append(contentsOf: buffer.prefix(Int(count)))
    if responseData.count > 4096 { fail("Daemon response is too large", code: 70) }
}

guard let response = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let separator = response.firstIndex(of: "\t"),
      let status = Int32(response[..<separator]) else {
    fail("Invalid daemon response", code: 70)
}

let body = String(response[response.index(after: separator)...])
if status == 0 {
    print(body)
    exit(0)
}
fail(body.isEmpty ? "Daemon request failed" : body, code: status)
