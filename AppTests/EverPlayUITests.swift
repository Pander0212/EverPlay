import XCTest

final class EverPlayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDemoZIPImportLaunchTouchAndPersistentReopen() throws {
        let app = XCUIApplication()
        app.launch()
        let game = app.buttons["game-Lantern Garden"]
        if !game.waitForExistence(timeout: 3) {
            let demo = app.buttons["importDemo"]
            XCTAssertTrue(demo.waitForExistence(timeout: 10))
            demo.tap()
        }
        XCTAssertTrue(game.waitForExistence(timeout: 20), "Bundled ZIP should pass the same importer as Files imports")
        game.tap()
        let collect = app.webViews.buttons["Collect light +10"]
        XCTAssertTrue(collect.waitForExistence(timeout: 20), "Local HTTP server must serve module JS, CSS and dialogue JSON")
        let inventory = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Seeds: ")).firstMatch
        XCTAssertTrue(inventory.waitForExistence(timeout: 5))
        let initialSeeds = try XCTUnwrap(Int(inventory.label.replacingOccurrences(of: "Seeds: ", with: "")))
        let expectedInventory = "Seeds: \(initialSeeds + 1)"
        collect.tap(); collect.tap()
        let seed = app.webViews.buttons["Buy seed · 20 gold"]
        XCTAssertTrue(seed.waitForExistence(timeout: 5)); seed.tap()
        app.webViews.buttons["Save game"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Saved on this device"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts[expectedInventory].exists)
        app.buttons["gameMenu"].tap()
        let exit = app.buttons["exitGame"]
        if !exit.isHittable { app.swipeUp() }
        XCTAssertTrue(exit.waitForExistence(timeout: 5)); exit.tap()
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(game.waitForExistence(timeout: 10)); game.tap()
        XCTAssertTrue(app.webViews.staticTexts[expectedInventory].waitForExistence(timeout: 20), "Per-game WebKit storage must survive application relaunch")
    }

    @MainActor
    func testVirtualControlLayoutPersistsAndGameRemainsUsableInLandscape() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        let game = app.buttons["game-Lantern Garden"]
        if !game.waitForExistence(timeout: 3) { app.buttons["importDemo"].tap() }
        XCTAssertTrue(game.waitForExistence(timeout: 20)); game.tap()
        XCTAssertTrue(app.webViews.buttons["Collect light +10"].waitForExistence(timeout: 20))
        app.buttons["gameMenu"].tap()
        let toggle = app.switches["virtualControlsToggle"]
        reveal(toggle, in: app)
        if toggle.value as? String != "1" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "1", "Virtual controls must be enabled before arranging them")
        let arrange = app.buttons["arrangeControls"]
        reveal(arrange, in: app); arrange.tap()
        let action = app.buttons["z"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        let before = action.frame
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.48))
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: target)
        let direction = app.buttons["ArrowUp"]
        let directionBefore = direction.frame
        direction.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)))
        app.buttons["finishControlLayout"].tap()
        XCTAssertLessThan(direction.frame.midY, directionBefore.midY - 20, "Arrange mode must also move the D-pad")
        let savedDirectionFrame = direction.frame
        XCTAssertLessThan(action.frame.midY, before.midY - 20, "Arrange mode must move the control group")
        let savedFrame = action.frame
        action.tap()
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Portrait with virtual controls"; portrait.lifetime = .keepAlways; add(portrait)

        XCUIDevice.shared.orientation = .landscapeLeft
        let save = app.webViews.buttons["Save game"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable, "Game actions must remain reachable in landscape")
        save.tap()
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Landscape gameplay"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait

        app.buttons["gameMenu"].tap()
        let exit = app.buttons["exitGame"]
        reveal(exit, in: app); exit.tap()
        XCTAssertTrue(game.waitForExistence(timeout: 10)); game.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 20))
        XCTAssertEqual(action.frame.midX, savedFrame.midX, accuracy: 15, "Saved horizontal layout must survive reopening")
        XCTAssertEqual(action.frame.midY, savedFrame.midY, accuracy: 15, "Saved vertical layout must survive reopening")
        XCTAssertEqual(direction.frame.midX, savedDirectionFrame.midX, accuracy: 15, "Saved D-pad layout must survive reopening")
        XCTAssertEqual(direction.frame.midY, savedDirectionFrame.midY, accuracy: 15, "Saved D-pad layout must survive reopening")
        app.buttons["gameMenu"].tap()
        reveal(toggle, in: app); toggle.tap()
        app.buttons["resumeGame"].tap()
        XCTAssertFalse(action.exists, "Hidden controls must stop obstructing the game")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.collectionViews.firstMatch
        for _ in 0..<4 {
            if element.isHittable { return }
            if menu.exists && menu.isHittable { menu.swipeUp() }
            else { app.swipeUp() }
        }
        if !element.isHittable {
            let switches = app.switches.allElementsBoundByIndex.map { "\($0.label): \(String(describing: $0.frame))" }
            XCTFail("Expected menu item to become reachable: \(element.description). Switches: \(switches)", file: file, line: line)
        }
    }

}
