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
}
