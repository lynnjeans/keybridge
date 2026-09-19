import AppKit
import SwiftUI

/// The language KeyBridge shows itself in: the system's choice, or one the
/// user picks here. macOS reads it once, at launch, so a change asks for a
/// restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"

    var id: Self { self }

    /// Each language in its own words, so it can be found whatever the
    /// current one is.
    var name: String {
        switch self {
        case .system: String(localized: "Follow System")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .japanese: "日本語"
        }
    }

    /// Stored as the app's own AppleLanguages, which is what macOS's
    /// per-app language setting in System Settings writes too. A launch with
    /// `-AppleLanguages` among the arguments shows that language instead.
    static var current: AppLanguage {
        let defaults = UserDefaults.standard
        let languages = (defaults.volatileDomain(forName: UserDefaults.argumentDomain)["AppleLanguages"]
            ?? defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"]) as? [String]
        return languages?.first.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// The language menu at the foot of the sidebar, as in the mockup.
struct LanguagePicker: View {
    @State private var choice = AppLanguage.current
    /// The language in use since launch; a different choice needs a restart.
    @State private var launched = AppLanguage.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: $choice) {
                ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
            } label: {
                Image(systemName: "globe")
            }
            .fixedSize()
            .onChange(of: choice) { _, language in language.apply() }

            if choice != launched {
                Button("Restart to Switch Language") { Self.relaunch() }
                    .controlSize(.small)
            }
        }
    }

    /// Opens a new copy of KeyBridge and quits this one.
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}
