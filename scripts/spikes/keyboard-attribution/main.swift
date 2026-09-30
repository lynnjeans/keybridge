// KB-021 spike: can a key event seen by an event tap be attributed to the
// keyboard it came from?
//
// Listens only: a listen-only event tap next to an IOHIDManager that reports
// every keyboard's key values with the device they came from. Nothing is
// changed or posted, and no key codes are printed.
//
//   swiftc -O scripts/spikes/keyboard-attribution/main.swift -o /tmp/keyboard-attribution
//   /tmp/keyboard-attribution [--seconds 300] [--count 120] [--idle 20] [--fields]
//
// Ends with its report at the first limit reached, or on TERM. The numbers
// it gave on macOS 26.6 are in docs/testing-notes.md, Keyboards.

import ApplicationServices
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)

func argument(_ name: String, default value: Double) -> Double {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return value }
    return Double(CommandLine.arguments[index + 1]) ?? value
}
let maxSeconds = argument("--seconds", default: 300)
let maxCount = Int(argument("--count", default: 120))
let idleSeconds = argument("--idle", default: 20)
let dumpFields = CommandLine.arguments.contains("--fields")

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func nanoseconds(_ ticks: UInt64) -> UInt64 { ticks * UInt64(timebase.numer) / UInt64(timebase.denom) }
func now() -> UInt64 { nanoseconds(mach_absolute_time()) }

struct Device {
    let name: String
    let vendor: Int
    let product: Int
    let transport: String
    let registryID: UInt64
    let builtIn: Bool
}

struct HIDRecord {
    let device: Int
    let isModifier: Bool
    let down: Bool
    /// The value's own time, as ticks and as nanoseconds.
    let ticks: UInt64
    let time: UInt64
    let arrived: UInt64
}

struct TapRecord {
    let type: CGEventType
    let keyboardType: Int64
    let time: UInt64
    let arrived: UInt64
    /// How many HID values had arrived when the tap callback ran.
    let hidSeen: Int
    /// The device of the latest key-down value that had arrived by then.
    let latestDevice: Int?
    let isRepeat: Bool
    /// Undocumented field 87, which looked like a registry ID in the first run.
    let sender: UInt64
    let fields: [Int: Int64]
}

final class State: @unchecked Sendable {
    let lock = NSLock()
    var devices: [Device] = []
    var deviceIndex: [UnsafeMutableRawPointer: Int] = [:]
    var hid: [HIDRecord] = []
    var taps: [TapRecord] = []
    var latestDownDevice: Int?
    var lastEvent = now()
    var fieldDumps: [Int64: Int] = [:]
}
let state = State()

func describe(_ device: IOHIDDevice) -> Device {
    func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
    var registryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
    return Device(
        name: property(kIOHIDProductKey) as? String ?? "?",
        vendor: property(kIOHIDVendorIDKey) as? Int ?? 0,
        product: property(kIOHIDProductIDKey) as? Int ?? 0,
        transport: property(kIOHIDTransportKey) as? String ?? "?",
        registryID: registryID,
        builtIn: (property(kIOHIDBuiltInKey) as? Bool) ?? ((property(kIOHIDBuiltInKey) as? Int ?? 0) != 0)
    )
}

// MARK: - IOHIDManager, on its own thread

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(manager, [
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
] as CFArray)

let valueCallback: IOHIDValueCallback = { _, _, sender, value in
    let arrived = now()
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad) else { return }
    let usage = Int(IOHIDElementGetUsage(element))
    // 0–3 are rollover and error codes; above 231 nothing a keyboard sends.
    guard (4...231).contains(usage), let sender else { return }
    let ticks = IOHIDValueGetTimeStamp(value)
    state.lock.lock()
    defer { state.lock.unlock() }
    let index: Int
    if let known = state.deviceIndex[sender] {
        index = known
    } else {
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        state.devices.append(describe(device))
        index = state.devices.count - 1
        state.deviceIndex[sender] = index
    }
    let down = IOHIDValueGetIntegerValue(value) != 0
    state.hid.append(HIDRecord(device: index, isModifier: usage >= 224, down: down,
                               ticks: ticks, time: nanoseconds(ticks), arrived: arrived))
    if down { state.latestDownDevice = index }
}
IOHIDManagerRegisterInputValueCallback(manager, valueCallback, nil)

let hidThread = Thread {
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    print("IOHIDManagerOpen: \(result == kIOReturnSuccess ? "ok" : String(format: "0x%08x", result))")
    if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
        for device in devices {
            let info = describe(device)
            print(String(format: "  keyboard device: %@  vendor 0x%04x product 0x%04x  %@  registry 0x%llx  built-in %@",
                         info.name, info.vendor, info.product, info.transport, info.registryID, info.builtIn ? "yes" : "no"))
        }
    }
    CFRunLoopRun()
}
hidThread.qualityOfService = .userInteractive
hidThread.start()

// MARK: - The event tap, listening only

let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let arrived = now()
    guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
    state.lock.lock()
    var fields: [Int: Int64] = [:]
    if dumpFields, type == .keyDown, state.fieldDumps[keyboardType, default: 0] < 2 {
        state.fieldDumps[keyboardType, default: 0] += 1
        for raw in 0..<200 {
            guard let field = CGEventField(rawValue: UInt32(raw)) else { continue }
            let value = event.getIntegerValueField(field)
            if value != 0 { fields[raw] = value }
        }
    }
    state.taps.append(TapRecord(
        type: type, keyboardType: keyboardType, time: event.timestamp, arrived: arrived,
        hidSeen: state.hid.count, latestDevice: state.latestDownDevice,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        sender: CGEventField(rawValue: 87).map { UInt64(bitPattern: event.getIntegerValueField($0)) } ?? 0, fields: fields))
    state.lastEvent = arrived
    state.lock.unlock()
    return Unmanaged.passUnretained(event)
}

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
print("CGPreflightListenEventAccess: \(CGPreflightListenEventAccess())")
print("IOHIDCheckAccess(listen): \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue) (0 granted, 1 denied, 2 unknown)")

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                  eventsOfInterest: CGEventMask(mask), callback: tapCallback, userInfo: nil) else {
    print("CGEvent.tapCreate: refused")
    exit(2)
}
print("CGEvent.tapCreate: ok")
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// MARK: - Report

/// The IOHIDDevice above the registry entry with this ID, and the entry's class.
@Sendable func hidDevice(aboveEntry id: UInt64) -> (device: UInt64, entryClass: String)? {
    var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
    guard entry != 0 else { return nil }
    let entryClass = IOObjectCopyClass(entry)?.takeRetainedValue() as String? ?? "?"
    while entry != 0 {
        if IOObjectConformsTo(entry, "IOHIDDevice") != 0 {
            var device: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &device)
            IOObjectRelease(entry)
            return (device, entryClass)
        }
        var parent: io_registry_entry_t = 0
        let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
        IOObjectRelease(entry)
        guard result == KERN_SUCCESS else { return nil }
        entry = parent
    }
    return nil
}

func report() {
    state.lock.lock()
    let devices = state.devices, hid = state.hid, taps = state.taps
    state.lock.unlock()

    print("\n== Devices that sent key values ==")
    for (index, device) in devices.enumerated() {
        print(String(format: "  [%d] %@  vendor 0x%04x product 0x%04x  %@  registry 0x%llx  built-in %@",
                     index, device.name, device.vendor, device.product, device.transport, device.registryID,
                     device.builtIn ? "yes" : "no"))
    }
    print("HID key values: \(hid.count)   tap events: \(taps.count) (\(taps.filter(\.isRepeat).count) auto-repeats, left out below)")

    // Pair each tap event with the HID value whose own time is nearest.
    struct Pair { let tap: TapRecord; let hidIndex: Int; let gap: Int64 }
    var pairs: [Pair] = []
    var unmatched = 0
    for record in taps where !record.isRepeat {
        var best: (index: Int, gap: Int64)?
        for (index, value) in hid.enumerated() {
            if record.type == .flagsChanged { guard value.isModifier else { continue } }
            else { guard !value.isModifier, value.down == (record.type == .keyDown) else { continue } }
            let gap = Int64(bitPattern: record.time &- value.time)
            if best == nil || abs(gap) < abs(best!.gap) { best = (index, gap) }
        }
        // Anything further than 20 ms from every HID value did not come from a keyboard we saw.
        if let best, abs(best.gap) < 20_000_000 { pairs.append(Pair(tap: record, hidIndex: best.index, gap: best.gap)) }
        else {
            unmatched += 1
            let kind = record.type == .flagsChanged ? "flagsChanged" : record.type == .keyDown ? "keyDown" : "keyUp"
            let resolved = hidDevice(aboveEntry: record.sender)
            print(String(format: "  no HID value: %@  keyboard type %lld  field 87 0x%llx → %@", kind, record.keyboardType,
                         record.sender, resolved.map { String(format: "%@, IOHIDDevice 0x%llx", $0.entryClass, $0.device) } ?? "no registry entry"))
        }
    }
    print("Paired by time: \(pairs.count)   without a HID value within 20 ms: \(unmatched)")
    guard !pairs.isEmpty else { return }

    func percentile(_ values: [Int64], _ p: Double) -> Int64 {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }
    let gaps = pairs.map { abs($0.gap) }
    print("\n== 1. Is the tap event's timestamp the HID value's timestamp? ==")
    print("  |tap time − HID time| in ns: exact \(gaps.filter { $0 == 0 }.count)/\(gaps.count), median \(percentile(gaps, 0.5)), p95 \(percentile(gaps, 0.95)), max \(gaps.max()!)")

    print("\n== 2. Had the HID value arrived when the tap callback ran? ==")
    let present = pairs.filter { $0.hidIndex < $0.tap.hidSeen }
    print("  yes \(present.count)/\(pairs.count) (\(String(format: "%.1f", 100 * Double(present.count) / Double(pairs.count)))%)")
    let lead = pairs.map { Int64(bitPattern: $0.tap.arrived &- hid[$0.hidIndex].arrived) / 1000 }
    print("  tap callback − HID callback, in µs (positive: HID first): min \(lead.min()!), p5 \(percentile(lead, 0.05)), median \(percentile(lead, 0.5)), p95 \(percentile(lead, 0.95)), max \(lead.max()!)")
    let tapDelay = pairs.map { Int64(bitPattern: $0.tap.arrived &- $0.tap.time) / 1000 }
    print("  key time → tap callback, in µs: median \(percentile(tapDelay, 0.5)), p95 \(percentile(tapDelay, 0.95))")

    print("\n== 3. Would \"the keyboard of the latest key-down value\" have named the right one? ==")
    let keyDowns = pairs.filter { $0.tap.type == .keyDown }
    let right = keyDowns.filter { $0.tap.latestDevice == hid[$0.hidIndex].device }
    print("  key-downs: right \(right.count)/\(keyDowns.count)")
    var switches = 0, switchesRight = 0
    var previous: Int?
    for pair in keyDowns {
        let device = hid[pair.hidIndex].device
        if let previous, previous != device {
            switches += 1
            if pair.tap.latestDevice == device { switchesRight += 1 }
        }
        previous = device
    }
    print("  first key-down after changing keyboards: right \(switchesRight)/\(switches)")

    print("\n== 4. kCGKeyboardEventKeyboardType per keyboard ==")
    var types: [Int: [Int64: Int]] = [:]
    for pair in pairs { types[hid[pair.hidIndex].device, default: [:]][pair.tap.keyboardType, default: 0] += 1 }
    for (device, counts) in types.sorted(by: { $0.key < $1.key }) {
        print("  [\(device)] \(devices[device].name): " + counts.sorted(by: { $0.key < $1.key }).map { "type \($0.key) ×\($0.value)" }.joined(separator: ", "))
    }

    print("\n== 5. Field 87 (undocumented): does it name the keyboard? ==")
    var senders: [UInt64: [Int: Int]] = [:]
    for pair in pairs { senders[pair.tap.sender, default: [:]][hid[pair.hidIndex].device, default: 0] += 1 }
    var senderRight = 0
    for (sender, counts) in senders.sorted(by: { $0.key < $1.key }) {
        let resolved = hidDevice(aboveEntry: sender)
        let from = counts.sorted(by: { $0.key < $1.key }).map { "[\($0.key)] ×\($0.value)" }.joined(separator: ", ")
        print(String(format: "  0x%llx → %@, IOHIDDevice 0x%llx; on events paired with %@",
                     sender, resolved?.entryClass ?? "no registry entry", resolved?.device ?? 0, from))
        for (device, count) in counts where resolved?.device == devices[device].registryID { senderRight += count }
    }
    print("  events whose field 87 leads to the keyboard the HID value came from: \(senderRight)/\(pairs.count)")

    if dumpFields {
        print("\n== 6. Non-zero integer fields of the first key-downs (field: value) ==")
        for pair in pairs where !pair.tap.fields.isEmpty {
            let device = devices[hid[pair.hidIndex].device]
            // 9 is the key code; left out.
            let text = pair.tap.fields.sorted(by: { $0.key < $1.key }).filter { $0.key != 9 }
                .map { String(format: "%d: 0x%llx", $0.key, UInt64(bitPattern: $0.value)) }.joined(separator: "  ")
            print(String(format: "  %@ (registry 0x%llx): %@", device.name, device.registryID, text))
        }
    }
}

let started = now()
let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
    state.lock.lock()
    let downs = state.taps.filter { $0.type == .keyDown && !$0.isRepeat }.count
    let idle = Double(now() - state.lastEvent) / 1e9
    state.lock.unlock()
    let elapsed = Double(now() - started) / 1e9
    if downs >= maxCount || elapsed > maxSeconds || (downs > 0 && idle > idleSeconds) {
        // Let values still on their way arrive before pairing.
        Thread.sleep(forTimeInterval: 0.3)
        report()
        exit(0)
    }
}
RunLoop.main.add(timer, forMode: .common)
// `pkill -TERM keyboard-attribution` ends the run with its report.
signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { report(); exit(0) }
terminate.resume()
print("Listening: up to \(maxCount) key presses, \(Int(idleSeconds)) s without one, or \(Int(maxSeconds)) s.")
RunLoop.main.run()
