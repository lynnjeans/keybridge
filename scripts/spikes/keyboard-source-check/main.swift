// Runs KeyBridge's own KeyboardSource (KB-021) on real key presses, outside
// the app: a listen-only event tap that prints the keyboard each time it
// changes. Nothing is changed or posted, and no key codes are printed.
//
//   swiftc -O KeyBridge/Engine/KeyboardSource.swift scripts/spikes/keyboard-source-check/main.swift -o /tmp/keyboard-source-check
//   /tmp/keyboard-source-check          # type on each keyboard in turn; ends on TERM or after 10 minutes

import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

@MainActor final class Check {
    static let shared = Check()
    let source = KeyboardSource()
    var current: Keyboard??
    var counts: [String: Int] = [:]
    var changes = 0

    func name(_ keyboard: Keyboard?) -> String {
        guard let keyboard else { return "no keyboard (posted by software, or not said)" }
        return String(format: "%@  vendor 0x%04x product 0x%04x%@", keyboard.name, keyboard.vendorID, keyboard.productID,
                      keyboard.isBuiltIn ? "  built-in" : "")
    }

    func keyDown(_ event: CGEvent) {
        let keyboard = source.keyboard(of: event)
        counts[name(keyboard), default: 0] += 1
        if current == nil || current! != keyboard {
            if current != nil { changes += 1 }
            current = keyboard
            print("→ \(name(keyboard))")
        }
    }

    func report() {
        print("\nKey presses by keyboard (\(changes) changes):")
        for (name, count) in counts.sorted(by: { $0.key < $1.key }) { print("  \(count) × \(name)") }
        print("Gave up looking: \(source.hasGivenUp)")
    }
}

for id in CommandLine.arguments.dropFirst().compactMap({ UInt64($0.dropFirst(2), radix: 16) }) {
    let start = DispatchTime.now().uptimeNanoseconds
    let keyboard = KeyboardSource.keyboard(ofRegistryEntry: id)
    let microseconds = (DispatchTime.now().uptimeNanoseconds - start) / 1000
    print(String(format: "registry 0x%llx: %@ (%llu µs)", id, keyboard.map { "\($0)" } ?? "nil", microseconds))
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        MainActor.assumeIsolated { Check.shared.keyDown(event) }
    }
    return Unmanaged.passUnretained(event)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                  eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                  callback: callback, userInfo: nil) else {
    print("The event tap was refused: Accessibility or Input Monitoring is missing.")
    exit(2)
}
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { Check.shared.report(); exit(0) }
terminate.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + 600) { Check.shared.report(); exit(0) }
print("Listening. Type on each keyboard in turn.")
RunLoop.main.run()
