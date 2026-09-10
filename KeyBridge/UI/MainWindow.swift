import SwiftUI

/// The settings window. A placeholder until the sidebar and pages arrive
/// (KB-070).
struct MainWindow: View {
    var body: some View {
        ContentUnavailableView(
            "KeyBridge",
            systemImage: "command",
            description: Text("Settings will appear here.")
        )
        .frame(minWidth: 720, minHeight: 480)
    }
}
