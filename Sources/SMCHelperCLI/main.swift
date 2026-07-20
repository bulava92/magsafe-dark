import Foundation
import SMCHelper

let values: [String: UInt8] = [
    "system": 0,
    "off": 1,
    "green": 3,
    "orange": 4,
    "flash": 5,
    "blink-slow": 6,
    "blink-fast": 7,
    "blink-off": 19
]
let args = CommandLine.arguments

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func readACLC() -> UInt8 {
    var value: UInt8 = 0
    let result = smc_read_u8("ACLC", &value)
    guard result == 0 else {
        fail("ACLC is unavailable on this Mac (IOKit error \(result)).", code: 69)
    }
    return value
}

guard geteuid() == 0 else { fail("Run as root.", code: 77) }

if args.count == 2, args[1] == "probe" {
    _ = readACLC()
    print("supported")
    exit(0)
}

if args.count == 2, args[1] == "status" {
    print(readACLC())
    exit(0)
}

guard args.count == 2, let value = values[args[1]] else {
    fail("Usage: magsafe-led-helper off|system|green|orange|flash|blink-slow|blink-fast|blink-off|status|probe", code: 64)
}

let result = smc_write_u8("ACLC", value)
guard result == 0 else {
    fail("Unable to write ACLC (IOKit error \(result)).", code: 69)
}
print("ok")
