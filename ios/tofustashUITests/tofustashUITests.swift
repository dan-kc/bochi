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

    // Behaviour: the habit reminders control should live in the pill row and
    // allow the user to add a recurring reminder without leaving the form.
    func testHabitReminderPillCanAddRecurringReminder() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        app.buttons["entity.add"].tap()

        let remindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(remindersPill.waitForExistence(timeout: 2))
        remindersPill.tap()

        XCTAssertTrue(app.buttons["Recurring"].waitForExistence(timeout: 2))
        app.buttons["Recurring"].tap()
        app.buttons["reminder.add"].tap()
        app.buttons["Done"].tap()

        XCTAssertEqual(remindersPill.label, "1 reminder")
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

    // Behaviour: the task edit form should let the user complete the task in
    // place, then reopen in a completed state without reminder editing.
    func testTaskFormOmitsHistoryAndMarkIncompleteControls() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Submit report")
        finishEditingFormIfNeeded(app)
        app.buttons["Save"].tap()

        let taskText = app.staticTexts["Submit report"]
        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.tap()
        let completeButton = app.buttons["task.complete"]
        if !completeButton.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(completeButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["View Trade History"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Mark Incomplete"].waitForExistence(timeout: 1))
        completeButton.tap()

        XCTAssertFalse(app.buttons["task.claim"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.tap()
        XCTAssertFalse(app.buttons["View Trade History"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Mark Incomplete"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Manage Reminders"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Reminders are void for completed tasks."].waitForExistence(timeout: 1))
    }

    // Behaviour: task reminder edits should only commit on Save, so cancelling
    // the edit sheet must leave the previously saved reminder list untouched.
    func testTaskReminderEditsAreDiscardedOnCancel() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2), "step: new-task name field")
        nameField.tap()
        nameField.typeText("Plan trip")
        finishEditingFormIfNeeded(app)
        app.buttons["Save"].tap()

        let taskText = app.staticTexts["Plan trip"]
        XCTAssertTrue(taskText.waitForExistence(timeout: 2), "step: saved task row visible")
        openTaskEditor(taskText, in: app)
        let firstManageRemindersButton = taskRemindersButton(in: app)
        scrollToTaskRemindersButton(firstManageRemindersButton, in: app)
        XCTAssertTrue(firstManageRemindersButton.waitForExistence(timeout: 2), "step: manage reminders button visible on first open")
        firstManageRemindersButton.tap()
        XCTAssertTrue(app.buttons["reminder.add"].waitForExistence(timeout: 2), "step: reminder modal add button visible")
        app.buttons["reminder.add"].tap()
        app.buttons["Done"].tap()
        app.buttons["Cancel"].tap()

        XCTAssertTrue(taskText.waitForExistence(timeout: 2), "step: task row visible after cancel")
        openTaskEditor(taskText, in: app)
        let manageRemindersButton = taskRemindersButton(in: app)
        scrollToTaskRemindersButton(manageRemindersButton, in: app)
        XCTAssertTrue(manageRemindersButton.waitForExistence(timeout: 2), "step: manage reminders button visible on reopen")
        XCTAssertTrue(manageRemindersButton.label.contains("Not set"), "step: reminder summary reset after cancel")
    }

    // Behaviour: tasks should delete with the same swipe-to-confirm gesture
    // already used by habits and rewards.
    func testTaskCanBeDeletedFromListWithSwipeGesture() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Inbox zero")
        finishEditingFormIfNeeded(app)
        app.buttons["Save"].tap()

        let taskText = app.staticTexts["Inbox zero"]
        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()

        XCTAssertFalse(taskText.waitForExistence(timeout: 1))
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

    private func openTaskEditor(_ taskText: XCUIElement, in app: XCUIApplication) {
        let editTaskTitle = app.navigationBars["Edit Task"]
        if editTaskTitle.waitForExistence(timeout: 1) {
            return
        }

        for _ in 0..<3 {
            taskText.tap()
            if editTaskTitle.waitForExistence(timeout: 1) {
                return
            }
        }

        XCTFail("step: edit task sheet opened")
    }

    private func scrollToTaskRemindersButton(_ button: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !button.exists {
            app.swipeUp()
        }
    }

    private func taskRemindersButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Manage Reminders")).firstMatch
    }
}
