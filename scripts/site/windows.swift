// Prints KeyBridge's on-screen windows as "id layer width height name", one
// per line, for scripts/site/screenshots.sh to pick one to capture.
import CoreGraphics

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in list where window[kCGWindowOwnerName as String] as? String == "KeyBridge" {
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let name = window[kCGWindowName as String] as? String ?? ""
    print(id, layer, Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0), name)
}
