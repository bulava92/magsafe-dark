import Foundation
import SMCHelper

let values: [String: UInt8] = ["system": 0, "off": 1, "green": 3, "orange": 4]
let args = CommandLine.arguments

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard geteuid() == 0 else { fail("Run as root.", code: 77) }

if args.count == 2, args[1] == "status" {
    var value: UInt8 = 0
    let result = smc_read_u8("ACLC", &value)
    guard result == 0 else { fail("Unable to read ACLC (IOKit error \(result)).") }
    print(value)
    exit(0)
}

guard args.count == 2, let value = values[args[1]] else {
    fail("Usage: magsafe-led-helper off|system|green|orange|status", code: 64)
}
let result = smc_write_u8("ACLC", value)
guard result == 0 else { fail("Unable to write ACLC (IOKit error \(result)).") }
print("ok")
