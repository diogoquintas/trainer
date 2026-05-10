import AppKit
import IOKit.pwr_mgt

final class ScreenWakeController: NSObject, NSApplicationDelegate {
    private var assertionID = IOPMAssertionID(0)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSApp.isActive {
            keepDisplayAwake()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        keepDisplayAwake()
    }

    func applicationDidResignActive(_ notification: Notification) {
        allowDisplaySleep()
    }

    func applicationWillTerminate(_ notification: Notification) {
        allowDisplaySleep()
    }

    private func keepDisplayAwake() {
        guard assertionID == 0 else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Trainer is focused" as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
        }
    }

    private func allowDisplaySleep() {
        guard assertionID != 0 else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
