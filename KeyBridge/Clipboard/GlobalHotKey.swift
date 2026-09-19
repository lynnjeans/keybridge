import Carbon.HIToolbox
import OSLog

/// A system-wide shortcut, registered with the system rather than read from
/// KeyBridge's event tap. The system tells KeyBridge only when this exact
/// combination is pressed, so it works without Input Monitoring, and the
/// press never reaches the app in front.
@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private let action: @MainActor () -> Void

    /// Hot keys by the identifier the system reports them with.
    private static var registered: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private let id: UInt32

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
    }

    enum Failure: Error, Equatable {
        /// fn cannot be part of a system shortcut.
        case unsupportedModifier
        /// Another app has already registered the combination.
        case taken
        case failed(OSStatus)
    }

    /// Registers `combo`, replacing any earlier combination.
    func register(_ combo: KeyCombo) throws(Failure) {
        unregister()
        guard !combo.modifiers.contains(.function) else { throw .unsupportedModifier }
        Self.installHandler()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.key.rawValue), Self.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &reference
        )
        switch status {
        case noErr:
            self.reference = reference
            Self.registered[id] = self
        case OSStatus(eventHotKeyExistsErr):
            throw .taken
        default:
            throw .failed(status)
        }
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registered[id] = nil
    }

    private static let signature: OSType = 0x4B42_7267 // "KBrg"

    private static func carbonModifiers(_ modifiers: Modifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Carbon events arrive on the main thread.
            MainActor.assumeIsolated { GlobalHotKey.registered[hotKeyID.id]?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
