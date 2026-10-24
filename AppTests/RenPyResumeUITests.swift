import XCTest

/// Leaves a running Ren'Py game for the home screen and comes back, then taps again. Runs only in
/// the all-in-one simulator job, which embeds the runtimes and installs the Resume85 fixture; the
/// fixture writes every tap it receives to clicks.txt, which that job checks.
final class RenPyResumeUITests: XCTestCase {
    @MainActor
    func testTapsReachTheGameAfterReturningFromTheHomeScreen() throws {
        guard let game = ProcessInfo.processInfo.environment["EVERPLAY_RESUME_GAME"] else {
            throw XCTSkip("Needs the embedded Ren'Py runtimes (all-in-one simulator job)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-EverPlayAutoplayRenPy", game]
        app.launch()
        Thread.sleep(forTimeInterval: 45)
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.tap()
        Thread.sleep(forTimeInterval: 3)
        keep("Before leaving")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        Thread.sleep(forTimeInterval: 8)
        middle.tap()
        Thread.sleep(forTimeInterval: 2)
        middle.tap()
        Thread.sleep(forTimeInterval: 3)
        keep("After returning")
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
