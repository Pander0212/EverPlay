import XCTest

final class EverPlayUITests: XCTestCase {
    @MainActor
    func testDemoZIPImportLaunchTouchAndPersistentReopen() throws {
        let app = XCUIApplication()
        app.launch()
        let game = app.buttons["game-Lantern Garden"]
        if !game.exists {
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
}
