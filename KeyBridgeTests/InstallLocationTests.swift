import Foundation
import Testing

/// Where KeyBridge can be updated from (KB-101).
@Suite struct InstallLocationTests {
    @Test func applicationsIsUpdatable() {
        let location = InstallLocation(path: "/Applications/KeyBridge.app", volumeIsReadOnly: false)
        #expect(location == .updatable)
        #expect(location.advice == nil)
    }

    @Test func aDiskImageIsNot() {
        let location = InstallLocation(path: "/Volumes/KeyBridge 1.0/KeyBridge.app", volumeIsReadOnly: true)
        #expect(location == .diskImage)
        #expect(location.advice != nil)
    }

    /// Translocated copies sit on a read-only mount as well; the advice for
    /// them is different, so the path decides first.
    @Test func aTranslocatedCopyIsNot() {
        let path = "/private/var/folders/xy/T/AppTranslocation/0A1B2C3D-4E5F/d/KeyBridge.app"
        #expect(InstallLocation(path: path, volumeIsReadOnly: true) == .translocated)
        #expect(InstallLocation(path: path, volumeIsReadOnly: false) == .translocated)
    }

    /// Anywhere writable works, not only Applications.
    @Test func aWritableFolderElsewhereIsUpdatable() {
        #expect(InstallLocation(path: "/Users/someone/Apps/KeyBridge.app", volumeIsReadOnly: false) == .updatable)
    }

    // MARK: Offering to move (KB-233)

    private let home = "/Users/someone"

    @Test func aDiskImageOrTranslocatedCopyAlwaysOffers() {
        let dmg = "/Volumes/KeyBridge 1.0/KeyBridge.app"
        #expect(InstallLocation.diskImage.offersMove(path: dmg, homeDirectory: home, declined: false))
        #expect(InstallLocation.diskImage.offersMove(path: dmg, homeDirectory: home, declined: true))
        let copy = "/private/var/folders/xy/T/AppTranslocation/0A1B/d/KeyBridge.app"
        #expect(InstallLocation.translocated.offersMove(path: copy, homeDirectory: home, declined: true))
    }

    @Test func applicationsFoldersNeverOffer() {
        for path in ["/Applications/KeyBridge.app", "/Applications/Utilities/KeyBridge.app",
                     "/Users/someone/Applications/KeyBridge.app"] {
            #expect(!InstallLocation.updatable.offersMove(path: path, homeDirectory: home, declined: false), "\(path)")
            #expect(!InstallLocation.updatable.offersMove(path: path, homeDirectory: home + "/", declined: false), "\(path)")
        }
    }

    @Test func anotherFolderOffersUntilDeclined() {
        let path = "/Users/someone/Desktop/KeyBridge.app"
        #expect(InstallLocation.updatable.offersMove(path: path, homeDirectory: home, declined: false))
        #expect(!InstallLocation.updatable.offersMove(path: path, homeDirectory: home, declined: true))
    }

    /// A folder whose name only starts like Applications is somewhere else.
    @Test func lookalikeFoldersAreElsewhere() {
        #expect(!InstallLocation.isInApplicationsFolder(path: "/Applications Old/KeyBridge.app", homeDirectory: home))
        #expect(!InstallLocation.isInApplicationsFolder(path: "/Users/someone/ApplicationsBackup/KeyBridge.app", homeDirectory: home))
        #expect(!InstallLocation.isInApplicationsFolder(path: "/Users/other/Applications/KeyBridge.app", homeDirectory: home))
    }

    // MARK: Replacing a copy already installed (KB-233)

    @Test func installsWhenNothingIsThere() {
        #expect(InstallLocation.replaces(installedBuild: nil, runningBuild: "3"))
    }

    /// The same build again replaces it, which also repairs a damaged copy.
    @Test func replacesTheSameOrAnOlderBuild() {
        #expect(InstallLocation.replaces(installedBuild: "3", runningBuild: "3"))
        #expect(InstallLocation.replaces(installedBuild: "2", runningBuild: "3"))
        #expect(InstallLocation.replaces(installedBuild: "", runningBuild: "3"))
    }

    /// Build numbers compare as numbers: 10 is newer than 9.
    @Test func keepsANewerBuild() {
        #expect(!InstallLocation.replaces(installedBuild: "4", runningBuild: "3"))
        #expect(!InstallLocation.replaces(installedBuild: "10", runningBuild: "9"))
    }

    /// Installing silently from the disk image opens the same build instead
    /// of copying it again (KB-235).
    @Test func keepsTheSameBuildWhenInstallingSilently() {
        #expect(!InstallLocation.replaces(installedBuild: "3", runningBuild: "3", replacingSameBuild: false))
        #expect(InstallLocation.replaces(installedBuild: "2", runningBuild: "3", replacingSameBuild: false))
        #expect(InstallLocation.replaces(installedBuild: nil, runningBuild: "3", replacingSameBuild: false))
        #expect(!InstallLocation.replaces(installedBuild: "4", runningBuild: "3", replacingSameBuild: false))
    }
}
