import Foundation
import Security

/// Who sent a `keybridge://` request (KB-254). The scheme is open to every
/// app, and to any web page the user lets open KeyBridge, so a request is
/// carried out only when KeyBridge's own Finder extension sent it: otherwise
/// a page could have Terminal opened in a folder of its choosing.
///
/// The Apple event that delivers a URL carries the sender's audit token,
/// whether KeyBridge was running or the URL launched it (measured on macOS
/// 26.6 with a sandboxed sender). The sender's code signature is checked
/// against it: the extension's identifier, signed by the same team as
/// KeyBridge. The extension keeps running while Finder does, so its
/// signature can still be read when the request arrives.
enum FinderMenuSender {
    static let extensionIdentifier = "io.github.lynnjeans.KeyBridge.Finder"

    /// The code requirement a sender must meet, given KeyBridge's own team.
    /// An ad-hoc development build has no team, and can ask for the
    /// identifier only; every release has one. A team that is not a team ID
    /// is never written into the requirement, and nothing meets it then.
    static func requirement(teamID: String?) -> String {
        let identifier = "identifier \"\(extensionIdentifier)\""
        guard let teamID, !teamID.isEmpty else { return identifier }
        guard teamID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return "\(identifier) and never" }
        return "\(identifier) and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Whether `event` was sent by KeyBridge's Finder extension. False when
    /// it names no sender, or one that has already gone.
    static func isFinderExtension(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let code = sender(of: event) else { return false }
        return satisfies(code, requirement(teamID: ownTeamID))
    }

    /// The sender's signing identifier, for the log; never the request
    /// itself, whose folder is the user's.
    static func describe(_ event: NSAppleEventDescriptor?) -> String {
        guard let code = sender(of: event) else { return "an unknown sender" }
        return signing(of: code).identifier ?? "unsigned code"
    }

    /// The sending process's code, read from the audit token the event
    /// carries.
    static func sender(of event: NSAppleEventDescriptor?) -> SecCode? {
        guard let token = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data else {
            return nil
        }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code)
            == errSecSuccess else { return nil }
        return code
    }

    /// Whether running `code` is validly signed and meets `requirement`.
    static func satisfies(_ code: SecCode, _ requirement: String) -> Bool {
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
              let compiled else { return false }
        return SecCodeCheckValidity(code, [], compiled) == errSecSuccess
    }

    /// KeyBridge's own team, from its own signature; nil for an ad-hoc build.
    static let ownTeamID: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        return signing(of: code).teamID
    }()

    private static func signing(of code: SecCode) -> (identifier: String?, teamID: String?) {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let info = info as? [String: Any] else { return (nil, nil) }
        return (info[kSecCodeInfoIdentifier as String] as? String, info[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}
