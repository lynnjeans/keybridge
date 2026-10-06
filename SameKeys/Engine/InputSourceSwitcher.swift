import Carbon
import Foundation
import OSLog

/// Switches between a keyboard layout and an input method, as Caps Lock does
/// between ABC and Pinyin (SK-277), for the Switch input source system
/// function.
///
/// Posting ⌃Space, the system's Select the previous input source, does the
/// same but shows the system's input source switcher every time; selecting
/// the source through Text Input Source Services shows nothing.
///
/// The other side is the source of the other kind used last: from ABC, the
/// input method last typed with (Pinyin rather than Japanese, if that is
/// what was in use), and back. The sources in use are followed through the
/// system's change notification, so a switch made any other way counts too.
@MainActor
final class InputSourceSwitcher {
    /// One selectable input source, as much of it as the choice needs.
    struct Source: Equatable {
        let id: String
        /// A keyboard layout such as ABC, as opposed to an input method or
        /// one of its modes such as Pinyin.
        let isLayout: Bool
    }

    /// The source of each kind selected last, by `isLayout`.
    private var lastUsed: [Bool: String] = [:]
    // Kept for the app's lifetime, so the observer is never removed.
    private var observer: NSObjectProtocol?

    init() {
        if let current = Self.current() { lastUsed[current.isLayout] = current.id }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = Self.current() else { return }
                self.lastUsed[current.isLayout] = current.id
            }
        }
    }

    /// Selects the other input source, if there is one.
    func toggle() {
        guard let current = Self.current() else { return }
        let enabled = Self.selectable()
        guard let target = Self.choose(current: current, enabled: enabled.map(\.source), lastUsed: lastUsed),
              let source = enabled.first(where: { $0.source == target })?.ref else {
            Logger.engine.notice("input source: nothing to switch to from \(current.id, privacy: .public)")
            return
        }
        let status = TISSelectInputSource(source)
        Logger.engine.info("input source: \(current.id, privacy: .public) → \(target.id, privacy: .public) (\(status))")
    }

    // MARK: - Pure rules, for the tests

    /// The source to switch to: of the other kind than `current`, the one
    /// used last if it is still enabled, else the first enabled one. With
    /// only one kind enabled, the next source of that kind, in the order the
    /// system lists them.
    static func choose(current: Source, enabled: [Source], lastUsed: [Bool: String]) -> Source? {
        let others = enabled.filter { $0.isLayout != current.isLayout }
        if !others.isEmpty {
            return others.first { $0.id == lastUsed[!current.isLayout] } ?? others.first
        }
        let same = enabled.filter { $0.isLayout == current.isLayout }
        guard same.count > 1, let index = same.firstIndex(of: current) else {
            return same.first { $0 != current }
        }
        return same[(index + 1) % same.count]
    }

    // MARK: - Text Input Source Services

    private static func current() -> Source? {
        source(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    /// The enabled sources a person can select from the input menu: keyboard
    /// layouts and input modes, not palettes, dictation or an input method's
    /// own entry when its modes are listed.
    private static func selectable() -> [(source: Source, ref: TISInputSource)] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { ref in source(ref).map { ($0, ref) } }
    }

    private static func source(_ ref: TISInputSource) -> Source? {
        guard let id = string(ref, kTISPropertyInputSourceID) else { return nil }
        return Source(id: id, isLayout: string(ref, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String)
    }

    private static func string(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
