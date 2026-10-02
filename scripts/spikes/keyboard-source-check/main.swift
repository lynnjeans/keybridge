// Runs KeyBridge's own KeyboardSource (KB-021) on real key presses, outside
// the app: a listen-only event tap that prints the keyboard each time it
// changes. Nothing is changed or posted, and no key codes are printed.
//
// Modifiers pressed on their own arrive as flagsChanged events; those are
// counted separately, with the modifier's name, since clicks and scrolling
// made while one is held must follow its keyboard (KB-020, KB-243). Clicks
// and scrolls are counted by sender too.
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

    var modifierCounts: [String: Int] = [:]
    var pointerCounts: [String: Int] = [:]
    var lastFlags = CGEventFlags()

    /// A modifier going down or up on its own.
    func flagsChanged(_ event: CGEvent) {
        let names: [(CGEventFlags, String)] = [(.maskSecondaryFn, "fn"), (.maskControl, "Ctrl"), (.maskAlternate, "Option"),
                                               (.maskCommand, "Command"), (.maskShift, "Shift"), (.maskAlphaShift, "Caps Lock")]
        let changed = names.filter { event.flags.contains($0.0) != lastFlags.contains($0.0) }
        let pressed = changed.filter { event.flags.contains($0.0) }.map(\.1)
        lastFlags = event.flags
        guard !pressed.isEmpty else { return }
        let keyboard = source.keyboard(of: event)
        let line = "\(pressed.joined(separator: "+")) down on \(name(keyboard))"
        modifierCounts[line, default: 0] += 1
        print("  modifier: \(line)")
    }

    /// What a click or scroll says about its sender: a mouse is no keyboard.
    func pointer(_ event: CGEvent, _ kind: String) {
        let keyboard = source.keyboard(of: event)
        pointerCounts["\(kind) from \(keyboard.map { name($0) } ?? "no keyboard")", default: 0] += 1
    }

    func report() {
        print("\nKey presses by keyboard (\(changes) changes):")
        for (name, count) in counts.sorted(by: { $0.key < $1.key }) { print("  \(count) × \(name)") }
        print("Modifiers pressed:")
        for (name, count) in modifierCounts.sorted(by: { $0.key < $1.key }) { print("  \(count) × \(name)") }
        print("Clicks and scrolls:")
        for (name, count) in pointerCounts.sorted(by: { $0.key < $1.key }) { print("  \(count) × \(name)") }
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
    MainActor.assumeIsolated {
        switch type {
        case .keyDown where event.getIntegerValueField(.keyboardEventAutorepeat) == 0: Check.shared.keyDown(event)
        case .flagsChanged: Check.shared.flagsChanged(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: Check.shared.pointer(event, "click")
        case .scrollWheel: Check.shared.pointer(event, "scroll")
        default: break
        }
    }
    return Unmanaged.passUnretained(event)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                  eventsOfInterest: [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
                                                     .otherMouseDown, .scrollWheel].reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue },
                                  callback: callback, userInfo: nil) else {
    print("The event tap was refused: Accessibility or Input Monitoring is missing.")
    exit(2)
}
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { MainActor.assumeIsolated { Check.shared.report() }; exit(0) }
terminate.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + 600) { MainActor.assumeIsolated { Check.shared.report() }; exit(0) }
print("Listening. Type on each keyboard in turn, and press each modifier on its own.")
RunLoop.main.run()
