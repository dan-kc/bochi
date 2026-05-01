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

    // Behaviour: after adding a habit into a long list, the screen should
    // scroll so the new habit is immediately visible to the user.
    func testAddingHabitScrollsToNewHabit() {
        let app = launchApp()

        app.tabBars.buttons["Habits"].tap()
        for index in 0..<12 {
            createHabit(named: "Habit \(index)", in: app)
        }

        createHabit(named: "Habit Target", in: app)

        let targetHabit = app.staticTexts["Habit Target"]
        XCTAssertTrue(targetHabit.waitForExistence(timeout: 2))
        XCTAssertTrue(targetHabit.isHittable)
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

    // Behaviour: after adding a reward into a long list, the screen should
    // scroll so the new reward is immediately visible.
    func testAddingRewardScrollsToNewReward() {
        let app = launchApp()

        app.tabBars.buttons["Rewards"].tap()
        for index in 0..<12 {
            createReward(named: "Reward \(index)", in: app)
        }

        createReward(named: "Reward Target", in: app)

        let targetReward = app.staticTexts["Reward Target"]
        XCTAssertTrue(targetReward.waitForExistence(timeout: 2))
        XCTAssertTrue(targetReward.isHittable)
    }

    // Behaviour: closing a blank new-task sheet should not offer recovery
    // because the user did not create any draft worth restoring.
    func testBlankTaskDraftDoesNotShowRecoveryToast() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        app.buttons["Cancel"].tap()

        XCTAssertFalse(app.staticTexts["Task Discarded"].waitForExistence(timeout: 1))
    }

    // Behaviour: dismissing a partially filled new-task form should keep the
    // draft recoverable so the user can reopen it with the same values.
    func testDiscardedTaskDraftCanBeRecovered() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Plan trip")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Task Discarded"].waitForExistence(timeout: 2))
        app.buttons["Recover"].tap()

        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertEqual(nameField.value as? String, "Plan trip")
    }

    // Behaviour: the task form should summarize the chosen difficulty and due
    // date directly in the pill row after the user sets them.
    func testTaskPillsReflectSelectedValues() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()

        app.buttons["pill.difficulty"].tap()
        app.buttons["4"].tap()
        app.buttons["Save"].tap()
        XCTAssertEqual(app.buttons["pill.difficulty"].label, "Hard")

        app.buttons["pill.dueDate"].tap()
        let dueDateButton = app.buttons["task-due-date.quick.today"]
        XCTAssertTrue(dueDateButton.waitForExistence(timeout: 2))
        dueDateButton.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["pill.dueDate"].label.contains("Today"))
    }

    // Behaviour: saving a new task should trim accidental outer whitespace so
    // the list shows the intended task name.
    func testSavedTaskNameIsTrimmed() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("  Submit report  ")
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Submit report"].waitForExistence(timeout: 2))
    }

    // Behaviour: after adding a task into a long list, the screen should
    // scroll so the new task is immediately visible.
    func testAddingTaskScrollsToNewTask() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        for index in 0..<12 {
            createTask(named: "Task \(index)", in: app)
        }

        createTask(named: "Task Target", in: app)

        let targetTask = app.staticTexts["Task Target"]
        XCTAssertTrue(targetTask.waitForExistence(timeout: 2))
        XCTAssertTrue(targetTask.isHittable)
    }

    // Behaviour: opening list search from the floating button should narrow
    // the current list live, keep the search bar visible after the keyboard
    // collapses, and only collapse once the user clears the text and taps away.
    func testTaskListSearchKeepsFilterAfterClosingKeyboard() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        createTask(named: "Alpha Task", in: app)
        createTask(named: "Bravo Task", in: app)

        app.buttons["entity.search"].tap()
        let searchField = app.textFields["entity.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("bravo")

        XCTAssertTrue(app.staticTexts["Bravo Task"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Alpha Task"].waitForExistence(timeout: 1))

        app.navigationBars["Tasks"].tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Bravo Task"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Alpha Task"].waitForExistence(timeout: 1))

        app.buttons["entity.search.clear"].tap()
        app.navigationBars["Tasks"].tap()

        XCTAssertFalse(searchField.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Bravo Task"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Alpha Task"].waitForExistence(timeout: 2))
    }

    // Behaviour: submitting an empty list search should collapse the search
    // chrome instead of leaving an empty filter bar behind.
    func testEmptyTaskSearchSubmitClosesSearch() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        createTask(named: "Alpha Task", in: app)

        app.buttons["entity.search"].tap()
        let searchField = app.textFields["entity.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        app.keyboards.buttons["Done"].tap()

        XCTAssertFalse(searchField.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["entity.search"].waitForExistence(timeout: 1))
    }

    // Behaviour: completing a task should keep existing reminders visible and
    // still let the user add more reminders from the completed task form.
    func testCompletedTaskKeepsAndAllowsReminderEdits() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Submit report")
        finishEditingFormIfNeeded(app)

        let initialRemindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(initialRemindersPill.waitForExistence(timeout: 2))
        initialRemindersPill.tap()
        XCTAssertTrue(app.buttons["reminder.add"].waitForExistence(timeout: 2))
        app.buttons["reminder.add"].tap()
        app.buttons["Done"].tap()

        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

        let taskText = app.staticTexts["Submit report"]
        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.tap()
        let completeButton = app.buttons["task.complete"]
        if !completeButton.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(completeButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["History"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Mark Incomplete"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["task.form.menu"].waitForExistence(timeout: 1))
        completeButton.tap()

        XCTAssertFalse(app.buttons["task.claim"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.tap()
        let completedRemindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(completedRemindersPill.waitForExistence(timeout: 2))
        XCTAssertEqual(completedRemindersPill.label, "1 reminder")
        completedRemindersPill.tap()
        XCTAssertTrue(app.buttons["reminder.add"].waitForExistence(timeout: 2))
        app.buttons["reminder.add"].tap()
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Done"].tap()

        XCTAssertTrue(taskText.waitForExistence(timeout: 2))
        taskText.tap()
        let reopenedRemindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(reopenedRemindersPill.waitForExistence(timeout: 2))
        XCTAssertEqual(reopenedRemindersPill.label, "2 reminders")
        XCTAssertFalse(app.buttons["History"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Mark Incomplete"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["task.form.menu"].waitForExistence(timeout: 1))
    }

    // Behaviour: editing reminders on an existing task should auto-save as soon
    // as the reminder modal closes, without needing a dedicated save button.
    func testTaskReminderEditsAutoSave() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2), "step: new-task name field")
        nameField.tap()
        nameField.typeText("Plan trip")
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

        let taskText = app.staticTexts["Plan trip"]
        XCTAssertTrue(taskText.waitForExistence(timeout: 2), "step: saved task row visible")
        openTaskEditor(taskText, in: app)
        let remindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(remindersPill.waitForExistence(timeout: 2), "step: reminder pill visible on first open")
        remindersPill.tap()
        XCTAssertTrue(app.buttons["reminder.add"].waitForExistence(timeout: 2), "step: reminder modal add button visible")
        app.buttons["reminder.add"].tap()
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Done"].tap()

        XCTAssertTrue(taskText.waitForExistence(timeout: 2), "step: task row visible after dismiss")
        openTaskEditor(taskText, in: app)
        let reopenedRemindersPill = app.buttons["pill.reminders"]
        XCTAssertTrue(reopenedRemindersPill.waitForExistence(timeout: 2), "step: reminder pill visible on reopen")
        XCTAssertEqual(reopenedRemindersPill.label, "1 reminder")
    }

    // Behaviour: tasks should delete with the same swipe-to-confirm gesture
    // already used by habits and rewards.
    func testTaskCanBeDeletedFromListWithSwipeGesture() {
        let app = launchApp()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Inbox zero")
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()

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

    private func createHabit(named name: String, in app: XCUIApplication) {
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(name)
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()
    }

    private func createReward(named name: String, in app: XCUIApplication) {
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(name)
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()
    }

    private func createTask(named name: String, in app: XCUIApplication) {
        app.buttons["entity.add"].tap()
        let nameField = app.textFields["entity-form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(name)
        finishEditingFormIfNeeded(app)
        app.navigationBars.buttons["Add"].firstMatch.tap()
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
}
