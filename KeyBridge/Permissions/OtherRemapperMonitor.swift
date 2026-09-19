import Darwin
import Foundation
import Observation
import OSLog

/// Watches for other tools that remap keys, mouse buttons or scrolling.
///
/// They act on the same input as KeyBridge, before it or alongside it, so
/// their rules and KeyBridge's collide: Karabiner-Elements can turn fn+C
/// into ⌘C before KeyBridge ever sees fn+C, and mouse drivers take the side
/// buttons for themselves. KeyBridge cannot work around that, so it says so.
///
/// Most of these tools do their work in a background agent that launchd
/// starts, which `NSWorkspace.runningApplications` does not list; so the
/// check reads the process list instead, and only the user's own processes:
/// Karabiner-Elements keeps root daemons running after the user quits it.
@MainActor
@Observable
final class OtherRemapperMonitor {
    /// The tools running now, by name, in the order of `Tool.known`.
    private(set) var running: [String] = []

    @ObservationIgnored private let read: () -> [RunningProcess]
    @ObservationIgnored private var timer: Timer?
    /// Whether the list has been read yet; the first reading is logged even
    /// when it is empty, so the log always says what was running at launch.
    @ObservationIgnored private var hasRead = false

    init(read: @escaping () -> [RunningProcess] = OtherRemapperMonitor.userProcesses) {
        self.read = read
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let now = Self.tools(in: read())
        guard now != running || !hasRead else { return }
        hasRead = true
        Logger.permissions.notice("Other remappers running: \(now.isEmpty ? "none" : now.joined(separator: ", "), privacy: .public)")
        running = now
    }

    /// A process, as far as matching needs it.
    struct RunningProcess: Equatable {
        var bundleID: String?
        var executableName: String
    }

    /// A tool and how to recognize the process that does its remapping.
    struct Tool {
        var name: String
        /// Bundle identifiers, each matching itself and anything beneath it
        /// (`com.example.app` also matches `com.example.app.helper`).
        var bundleIDs: [String] = []
        /// For agents shipped without a bundle identifier of their own.
        var executableNames: [String] = []

        func matches(_ process: RunningProcess) -> Bool {
            if let id = process.bundleID,
               bundleIDs.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) {
                return true
            }
            return executableNames.contains(process.executableName)
        }

        /// Only the part of each tool that is running while it remaps: for
        /// Karabiner-Elements that is the user's console server, which quits
        /// with it, and not its settings window or its root daemons.
        static let known: [Tool] = [
            Tool(name: "Karabiner-Elements", bundleIDs: ["org.pqrs.Karabiner-Console-User-Server"]),
            Tool(name: "BetterTouchTool", bundleIDs: ["com.hegenberg.BetterTouchTool"]),
            Tool(name: "SteerMouse", bundleIDs: ["jp.plentycom.app.SteerMouse", "jp.plentycom.SteerMouse"]),
            Tool(name: "LinearMouse", bundleIDs: ["com.lujjjh.LinearMouse"]),
            Tool(name: "Mac Mouse Fix", bundleIDs: ["com.nuebling.mac-mouse-fix"]),
            Tool(name: "USB Overdrive", bundleIDs: ["com.montalcini.usboverdrive"]),
            Tool(name: "Logi Options+", bundleIDs: ["com.logi.cp-dev-mgr", "com.logi.optionsplus"],
                 executableNames: ["logioptionsplus_agent"]),
            Tool(name: "Scroll Reverser", bundleIDs: ["com.pilotmoon.scroll-reverser"]),
            Tool(name: "Mos", bundleIDs: ["com.caldis.Mos"]),
            Tool(name: "Hammerspoon", bundleIDs: ["org.hammerspoon.Hammerspoon"]),
        ]
    }

    /// The known tools among the processes, each named once.
    nonisolated static func tools(in processes: [RunningProcess]) -> [String] {
        Tool.known.filter { tool in processes.contains(where: tool.matches) }.map(\.name)
    }

    // MARK: - Reading the process list

    /// The current user's processes, with the bundle identifier of the app
    /// each one runs from.
    nonisolated static func userProcesses() -> [RunningProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        let uid = getuid()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return pids.prefix(Int(filled)).compactMap { pid in
            var info = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard pid > 0,
                  proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size,
                  info.pbsi_uid == uid
            else { return nil }
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { return nil }
            let executable = String(decoding: path[..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return RunningProcess(bundleID: bundleID(ofExecutable: executable),
                                  executableName: (executable as NSString).lastPathComponent)
        }
    }

    /// The identifier of the innermost app bundle the executable sits in.
    /// Foundation keeps each `Bundle` it has read, so repeating this every
    /// few seconds does not read the Info.plist files again.
    nonisolated private static func bundleID(ofExecutable path: String) -> String? {
        path.range(of: ".app/Contents/MacOS/", options: .backwards).flatMap { range in
            Bundle(path: String(path[..<range.lowerBound]) + ".app")?.bundleIdentifier
        }
    }
}
