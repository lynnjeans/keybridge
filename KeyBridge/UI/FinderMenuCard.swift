import AppKit
import FinderSync
import SwiftUI

/// The Finder right-click menu on the Mouse page (KB-210): whether its
/// extension is on, and the way to System Settings, where it is switched on
/// and off. KeyBridge keeps no switch of its own, so the two cannot disagree.
struct FinderMenuCard: View {
    @State private var isEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        Card {
            HStack(spacing: 12) {
                IconTile(symbol: "contextualmenu.and.cursorarrow", tint: .blue, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finder right-click menu")
                        .font(.headline)
                    Text("Right-click empty space in a folder to create a new document there or open it in Terminal, like on Windows.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isEnabled
                         ? "On. Switch it off under KeyBridge in System Settings › General › Login Items & Extensions."
                         : "Off. Switch it on under KeyBridge in System Settings › General › Login Items & Extensions.")
                        .font(.callout)
                        .foregroundStyle(isEnabled ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                Spacer(minLength: 8)
                Button("Open System Settings") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
        }
        // Coming back from System Settings makes KeyBridge active again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}
