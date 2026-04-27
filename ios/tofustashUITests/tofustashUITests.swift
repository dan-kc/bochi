import XCTest

final class tofustashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Behaviour: closing a blank new-habit sheet should not show a recovery
    // toast because the user never authored anything worth restoring.
    func testBlankHabitDraftDoesNotShowRecoveryToast() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        app.buttons["entity.add"].tap()
        app.buttons["Cancel"].tap()

        XCTAssertFalse(app.staticTexts["Habit Discarded"].waitForExistence(timeout: 1))
    }

    // Behaviour: dismissing a partially filled habit form should offer a
    // recovery action and reopen with the user's typed draft intact.
    func testDiscardedHabitDraftCanBeRecovered() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Morning Run")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Habit Discarded"].waitForExistence(timeout: 2))
        app.buttons["Recover"].tap()

        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertEqual(nameField.value as? String, "Morning Run")
    }

    // Behaviour: the habit form should show UI summaries for the selected
    // difficulty and frequency directly in the pill row.
    func testHabitPillsReflectSelectedValues() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        app.buttons["entity.add"].tap()

        app.buttons["pill.difficulty"].tap()
        app.buttons["4"].tap()
        app.buttons["Save"].tap()
        XCTAssertEqual(app.buttons["pill.difficulty"].label, "Hard")

        app.buttons["pill.frequency"].tap()
        let habitFrequencyField = app.textFields["habit-frequency.value"]
        XCTAssertTrue(habitFrequencyField.waitForExistence(timeout: 2))
        habitFrequencyField.tap()
        habitFrequencyField.typeText("3")
        app.buttons["Week"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["pill.frequency"].label, "3/week")
    }

    // Behaviour: saving a new habit should trim accidental outer whitespace so
    // the list shows the intentional name instead of the raw typed padding.
    func testSavedHabitNameIsTrimmed() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("  Exercise  ")
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Exercise"].waitForExistence(timeout: 2))
    }

    // Behaviour: closing a blank reward sheet should not create a recoverable
    // toast because there is no user-authored draft to restore.
    func testBlankRewardDraftDoesNotShowRecoveryToast() {
        let app = launchApp()

        app.tabBars.buttons["Rewards"].tap()
        app.buttons["entity.add"].tap()
        app.buttons["Cancel"].tap()

        XCTAssertFalse(app.staticTexts["Reward Discarded"].waitForExistence(timeout: 1))
    }

    // Behaviour: dismissing a partially filled reward form should preserve the
    // draft behind a recover action and restore it when tapped.
    func testDiscardedRewardDraftCanBeRecovered() {
        let app = launchApp()

        app.tabBars.buttons["Rewards"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Chips")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Reward Discarded"].waitForExistence(timeout: 2))
        app.buttons["Recover"].tap()

        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertEqual(nameField.value as? String, "Chips")
    }

    // Behaviour: the reward form should summarize the chosen damage tier and
    // max frequency directly in the pill row after the user sets them.
    func testRewardPillsReflectSelectedValues() {
        let app = launchApp()

        app.tabBars.buttons["Rewards"].tap()
        app.buttons["entity.add"].tap()

        app.buttons["pill.damage"].tap()
        app.buttons["4"].tap()
        app.buttons["Save"].tap()
        XCTAssertEqual(app.buttons["pill.damage"].label, "Heavy")

        app.buttons["pill.frequency"].tap()
        let rewardFrequencyField = app.textFields["reward-frequency.value"]
        XCTAssertTrue(rewardFrequencyField.waitForExistence(timeout: 2))
        rewardFrequencyField.tap()
        rewardFrequencyField.typeText("2")
        app.buttons["Week"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["pill.frequency"].label, "Max 2/week")
    }

    // Behaviour: saving a reward should trim accidental outer whitespace so
    // the visible list reflects the intended reward name.
    func testSavedRewardNameIsTrimmed() {
        let app = launchApp()

        app.tabBars.buttons["Rewards"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("  Chips  ")
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Chips"].waitForExistence(timeout: 2))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tofustash-uitests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: storageDirectory)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        app.launchEnvironment["TOFUSTASH_UI_TEST_MODE"] = "1"
        app.launchEnvironment["TOFUSTASH_STORAGE_DIR"] = storageDirectory.path
        app.launch()
        return app
    }

    private func finishEditingFormIfNeeded(_ app: XCUIApplication) {
        let doneButton = app.navigationBars.buttons["Done"]
        if doneButton.waitForExistence(timeout: 1) {
            doneButton.tap()
        }
    }
}
