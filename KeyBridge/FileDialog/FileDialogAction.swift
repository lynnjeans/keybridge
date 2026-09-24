/// What a rule does in an open or save dialog (KB-217), the way Listary's
/// quick switch works on Windows.
///
/// A rule with one of these matches only while such a dialog has the
/// keyboard, whatever its scope says, so its trigger stays free everywhere
/// else. Raw values are saved in the configuration and must never change.
enum FileDialogAction: String, Codable, CaseIterable, Sendable {
    /// Takes the dialog to the folder Finder's front window is showing, or to
    /// Finder's most recent folder when it has no window open.
    case finderFolder
}

extension Action {
    /// Whether the rule may match only inside an open or save dialog.
    var needsFileDialog: Bool {
        if case .fileDialog = self { true } else { false }
    }
}
