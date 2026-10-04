import Carbon
import Foundation
import Security
import Testing

/// Only KeyBridge's own Finder extension may send keybridge:// requests
/// (KB-254). The sender's audit token is set by the system, so a test cannot
/// make an event that names one; what can be checked is the requirement and
/// that the signature check works on real code.
@Suite struct FinderMenuSenderTests {
    private let extensionOnly = #"identifier "io.github.lynnjeans.KeyBridge.Finder""#

    @Test func aSignedBuildAsksForTheExtensionSignedByItsOwnTeam() {
        #expect(FinderMenuSender.requirement(teamID: "JTCAH836NB")
            == extensionOnly + #" and anchor apple generic and certificate leaf[subject.OU] = "JTCAH836NB""#)
    }

    @Test func anAdHocBuildAsksForTheIdentifierOnly() {
        #expect(FinderMenuSender.requirement(teamID: nil) == extensionOnly)
        #expect(FinderMenuSender.requirement(teamID: "") == extensionOnly)
    }

    @Test func aTeamThatIsNotATeamIDLetsNothingThrough() {
        #expect(FinderMenuSender.requirement(teamID: #"X" or identifier "evil"#) == extensionOnly + " and never")
    }

    @Test func everyRequirementCompiles() {
        for team in ["JTCAH836NB", nil, "not a team"] {
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(FinderMenuSender.requirement(teamID: team) as CFString, [], &requirement)
                == errSecSuccess)
        }
    }

    @Test func anEventThatNamesNoSenderIsRefused() {
        #expect(!FinderMenuSender.isFinderExtension(nil))
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(!FinderMenuSender.isFinderExtension(event))
        #expect(FinderMenuSender.describe(event) == "an unknown sender")
    }

    @Test func theCheckReadsRealSignatures() throws {
        // launchd: Apple's code, always running, and not the extension. The
        // test runner itself will not do: it loads the ad-hoc test bundle.
        var code: SecCode?
        #expect(SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: 1] as CFDictionary, [], &code) == errSecSuccess)
        let launchd = try #require(code)
        #expect(FinderMenuSender.satisfies(launchd, "anchor apple"))
        #expect(!FinderMenuSender.satisfies(launchd, FinderMenuSender.requirement(teamID: nil)))
    }
}
