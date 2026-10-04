/// What a rule does in an open or save dialog (KB-217, KB-219), the way
/// Listary's quick switch works on Windows.
///
/// A rule with one of these matches only while such a dialog has the
/// keyboard — or, for an action that also means something there, while
/// Finder is in front — whatever its scope says, so its trigger stays free
/// everywhere else. Raw values are saved in the configuration and must
/// never change.
enum FileDialogAction: String, Codable, CaseIterable, Sendable {
    /// Takes the dialog to the folder Finder's front window is showing, or to
    /// Finder's most recent folder when it has no window open.
    case finderFolder
    /// Lists favorite and recent folders to go to (KB-219): in a dialog the
    /// chosen one is jumped to, in Finder it is opened.
    case recentLocations

    /// Whether the action also works with Finder in front, dialog or not.
    var worksInFinder: Bool { self == .recentLocations }
}

extension Action {
    /// The dialog action, for a rule that may match only inside an open or
    /// save dialog (or Finder, for some).
    var fileDialogAction: FileDialogAction? {
        if case .fileDialog(let action) = self { action } else { nil }
    }
}
