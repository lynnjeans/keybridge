// Records the keys and mouse buttons pressed while a demo video is being
// recorded (SK-290), so the video can show a keycap for what was pressed.
//
//   swiftc -O scripts/site/demo/keylog.swift -o build/keylog
//   build/keylog <log.jsonl>        runs until SIGTERM or SIGINT
//
// It reads raw HID input through IOHIDManager, which comes before every event
// tap: Ctrl+C on a PC keyboard is logged as Left Control + C, not as the ⌘C
// SameKeys turns it into. Each press or release is one JSON line:
//
//   {"t":1791345600.123,"device":"RK-KB5.0","kind":"key","name":"C","down":true}
//
// kind is "key", "button" (1 left, 2 right, 3 middle, 4 back, 5 forward) or
// "wheel" (name "up"/"down"/"left"/"right", no down). t is seconds since 1970,
// taken from the event's own timestamp, so it lines up with a screen
// recording's clock. Needs Input Monitoring; nothing leaves the Mac.
import Foundation
import IOKit.hid

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: keylog <log.jsonl>\n".data(using: .utf8)!)
    exit(2)
}
let path = CommandLine.arguments[1]
FileManager.default.createFile(atPath: path, contents: nil)
// Not a guard let: the HID callback is a C function and can't capture one.
let output: FileHandle = {
    if let handle = FileHandle(forWritingAtPath: path) { return handle }
    FileHandle.standardError.write("keylog: cannot write \(path)\n".data(using: .utf8)!)
    exit(1)
}()

// Event timestamps are in mach ticks; one reading of both clocks at the start
// turns them into wall-clock time.
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let startTicks = mach_absolute_time()
let startDate = Date().timeIntervalSince1970

func wallClock(_ ticks: UInt64) -> Double {
    let nanoseconds = (Double(ticks) - Double(startTicks)) * Double(timebase.numer) / Double(timebase.denom)
    return startDate + nanoseconds / 1e9
}

/// Names for HID keyboard usages (page 7), as a PC keyboard prints them.
let keyNames: [UInt32: String] = {
    var names: [UInt32: String] = [:]
    for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { names[0x04 + UInt32(offset)] = String(letter) }
    for (offset, digit) in "1234567890".enumerated() { names[0x1E + UInt32(offset)] = String(digit) }
    for number in 1...12 { names[0x39 + UInt32(number)] = "F\(number)" }
    let others: [UInt32: String] = [
        0x28: "Enter", 0x29: "Esc", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
        0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'",
        0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "Caps Lock",
        0x46: "Print Screen", 0x49: "Insert", 0x4A: "Home", 0x4B: "Page Up",
        0x4C: "Delete", 0x4D: "End", 0x4E: "Page Down",
        0x4F: "Right", 0x50: "Left", 0x51: "Down", 0x52: "Up", 0x65: "Menu",
        0xE0: "Left Control", 0xE1: "Left Shift", 0xE2: "Left Alt", 0xE3: "Left GUI",
        0xE4: "Right Control", 0xE5: "Right Shift", 0xE6: "Right Alt", 0xE7: "Right GUI",
    ]
    names.merge(others) { $1 }
    return names
}()

func write(_ record: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
    output.write(data)
    output.write("\n".data(using: .utf8)!)
}

var count = 0
/// The last few events written. Some mice (a ProClick) report through two
/// interfaces, so every press arrives twice with the same timestamp, often
/// with pointer movement in between.
var recent: [(time: Double, key: String)] = []

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(manager, [
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
] as CFArray)

IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let integer = IOHIDValueGetIntegerValue(value)
    let time = wallClock(IOHIDValueGetTimeStamp(value))
    let device = IOHIDElementGetDevice(element)
    let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown")
        .trimmingCharacters(in: .whitespaces)
    var record: [String: Any] = ["t": time, "device": product]

    switch (Int(page), Int(usage)) {
    case (kHIDPage_KeyboardOrKeypad, _):
        // Usages below 4 are roll-over and error reports, not keys.
        guard usage >= 0x04, usage != 0xFFFF_FFFF else { return }
        record["kind"] = "key"
        record["name"] = keyNames[usage] ?? String(format: "usage 0x%02X", usage)
        record["down"] = integer != 0
    case (0xFF, 0x03), (0xFF01, 0x03):
        // An Apple keyboard's fn key comes on Apple's own usage page.
        record["kind"] = "key"
        record["name"] = "fn"
        record["down"] = integer != 0
    case (kHIDPage_Button, _):
        record["kind"] = "button"
        record["name"] = String(usage)
        record["down"] = integer != 0
    case (kHIDPage_GenericDesktop, kHIDUsage_GD_Wheel):
        guard integer != 0 else { return }
        record["kind"] = "wheel"
        record["name"] = integer > 0 ? "up" : "down"
    case (kHIDPage_Consumer, kHIDUsage_Csmr_ACPan):
        guard integer != 0 else { return }
        record["kind"] = "wheel"
        record["name"] = integer > 0 ? "right" : "left"
    default:
        return
    }
    let key = "\(page) \(usage) \(integer)"
    guard !recent.contains(where: { $0.key == key && abs($0.time - time) < 0.002 }) else { return }
    recent = Array((recent + [(time, key)]).suffix(16))
    write(record)
    count += 1
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard opened == kIOReturnSuccess else {
    FileHandle.standardError.write("keylog: cannot open HID devices (\(opened)); grant Input Monitoring\n".data(using: .utf8)!)
    exit(1)
}

// Stop on SIGTERM or SIGINT, after the last line is on disk.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        try? output.synchronize()
        try? output.close()
        FileHandle.standardError.write("keylog: \(count) events in \(path)\n".data(using: .utf8)!)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
let names = devices.compactMap { IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String }
FileHandle.standardError.write("keylog: recording from \(Set(names).sorted().joined(separator: ", "))\n".data(using: .utf8)!)
CFRunLoopRun()
