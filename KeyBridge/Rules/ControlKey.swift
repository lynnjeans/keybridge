/// The key that plays the part of Windows' Ctrl.
///
/// Many people coming from Windows keep their thumb-side habit on a Mac
/// keyboard by pressing fn (🌐) where Ctrl used to be. With fn, Ctrl keeps its
/// Mac meaning, which also means Ctrl+C still interrupts in a terminal.
enum ControlKey: String, Codable, CaseIterable, Sendable {
    /// Ctrl+C copies, as on Windows.
    case control
    /// fn+C copies; Ctrl is left alone.
    case function = "fn"
    /// Both work.
    case both

    /// Rewrites the Ctrl shortcuts among `rules` for this choice.
    ///
    /// Only triggers that hold Ctrl and not fn change, and never those on
    /// keys that report fn by themselves (arrows, Home, F-keys): fn+Home
    /// would read as plain Home. An fn version applies in terminals too,
    /// since fn+C means nothing to a shell.
    func apply(to rules: [Rule]) -> [Rule] {
        guard self != .control else { return rules }
        return rules.flatMap { rule -> [Rule] in
            guard let fn = Self.fnVersion(of: rule) else { return [rule] }
            return self == .both ? [rule, fn] : [fn]
        }
    }

    /// The trigger as it is pressed with this choice, for display.
    func trigger(of rule: Rule) -> Trigger {
        guard self == .function, let fn = Self.fnVersion(of: rule) else { return rule.trigger }
        return fn.trigger
    }

    private static func fnVersion(of rule: Rule) -> Rule? {
        guard case .key(var combo) = rule.trigger,
              combo.modifiers.contains(.control), !combo.modifiers.contains(.function),
              !combo.key.carriesImplicitFunctionFlag else { return nil }
        combo.modifiers.remove(.control)
        combo.modifiers.insert(.function)
        var fn = rule
        fn.id = rule.id + ".fn"
        fn.trigger = .key(combo: combo)
        if case .except = fn.scope.applications {
            fn.scope.applications = .all
        }
        return fn
    }
}
