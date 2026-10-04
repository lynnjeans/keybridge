import Foundation
import Testing

/// Stands in for the system's login items.
@MainActor
final class FakeLoginItems {
    var isEnabled = false
    /// Every change is refused with an error.
    var refuses = false
    /// Changes are accepted and then not made.
    var ignores = false
    /// What the code under test asked for, in order.
    var calls: [String] = []

    /// How often the state was asked for.
    var reads = 0

    var system: LoginItem.System {
        LoginItem.System(
            isEnabled: {
                self.reads += 1
                return self.isEnabled
            },
            register: { try self.change(to: true, as: "register") },
            unregister: { try self.change(to: false, as: "unregister") }
        )
    }

    private func change(to enabled: Bool, as call: String) throws {
        calls.append(call)
        if refuses { throw CocoaError(.featureUnsupported) }
        if !ignores { isEnabled = enabled }
    }
}

@MainActor
@Suite struct LoginItemTests {
    let fake = FakeLoginItems()

    @Test func startsWithWhatTheSystemHas() {
        #expect(!LoginItem(isAvailable: true, system: fake.system).isEnabled)
        fake.isEnabled = true
        #expect(LoginItem(isAvailable: true, system: fake.system).isEnabled)
    }

    @Test func switchingOnRegistersAndOffUnregisters() {
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        #expect(fake.calls == ["register"])
        #expect(item.isEnabled)
        #expect(!item.hasFailed)

        item.set(false)
        #expect(fake.calls == ["register", "unregister"])
        #expect(!item.isEnabled)
        #expect(!item.hasFailed)
    }

    @Test func asksForNothingWhenAlreadyAsWanted() {
        fake.isEnabled = true
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        #expect(fake.calls.isEmpty, "Registering twice is an error to the system")
    }

    @Test func aRefusedChangeLeavesTheSwitchWhereItWas() {
        fake.refuses = true
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        #expect(fake.calls == ["register"])
        #expect(!item.isEnabled)
        #expect(item.hasFailed)
    }

    @Test func aChangeAcceptedButNotMadeCountsAsFailed() {
        fake.ignores = true
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        #expect(!item.isEnabled, "What shows is the system's answer, not what was asked for")
        #expect(item.hasFailed)
    }

    @Test func aLaterSuccessClearsTheFailure() {
        fake.refuses = true
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        fake.refuses = false
        item.set(true)
        #expect(item.isEnabled)
        #expect(!item.hasFailed)
    }

    @Test func followsAChangeMadeInSystemSettings() {
        fake.refuses = true
        let item = LoginItem(isAvailable: true, system: fake.system)
        item.set(true)
        #expect(item.hasFailed)

        fake.isEnabled = true
        item.refresh()
        #expect(item.isEnabled)
        #expect(!item.hasFailed, "Switched on by hand since, so there is nothing left to report")

        fake.isEnabled = false
        item.refresh()
        #expect(!item.isEnabled)
    }

    @Test func aCopyOutsideApplicationsNeverAsksTheSystem() {
        fake.isEnabled = true
        let item = LoginItem(isAvailable: false, system: fake.system)
        #expect(!item.isEnabled, "Reads as off, whatever another copy has set")
        item.refresh()
        item.set(true)
        item.set(false)
        #expect(fake.reads == 0, "Asking alone would make this copy the one opened at login")
        #expect(fake.calls.isEmpty)
        #expect(!item.hasFailed)
    }
}
