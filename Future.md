# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that. Document behaviours too.
Use strict TDD, always write unit tests first. No UI tests. When writing tests, ensure you comment what behaviour you are testing for. I do not want redundant tests. This should resemple BDD. If there is no appropriate test, don't write one. I only want relevant BDD tests that match user workflows in the app.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

On the difficulty modal make the following changes:

The final "done" screen should only show for a second. It should have no buttons or text and should just show the green checkmark as it does now. After that it should automatically collapse and return the user to the change form. THEN the difficulty pill should animate to show that it has been set. Make it a medium/strong animation so the user notices.

For the other stages in the difficulty flow:

Move the skip button to the top left and rename it "cancel".

If the difficulty is already set, then it should have an additional button "unset" in the top right that removes the difficulty

Ensure that if a new Habit form is opened when there are no prev habits, it automatically sets the difficulty. It should be already set when the habit form is opened such that the difficulty pill is already hilighted. If one clicks on the difficulty pill, it should show a message saying that you don't need to set the difficulty because it is the first habit. A user should not be able to unset this difficulty at all. In this case, the cancel button in the top left should be an "x"

# Add a "tick" to the name/description edit modal. It should have an "x" and a "tick", if you click the x it should ask "Are you sure you want to discard changes?" Also this behaviour should replicate if I touch outside of the modal.

# Filters

Filters

# Settings page

Auth, do not just show a spinner if the network request fails.

# Rewards

Implement the Rewards page. There are subtle differences in the Reward type. It should resemble closely the Habits. Ensure the abstractions are enforced such that the codebase is extremely DRY. Make this local-only for now, do not implement the local-first sync layer sound in the old project.

# Trades

# NEXT

Add the price

Also ensure that this pill scroll correctly conveys the case where there is overflow.




     2. Manual testing scenarios:
       - Open new habit form with no existing habits → difficulty pill already highlighted
       - Tap difficulty pill on first habit → alert appears
       - Open new habit form with existing habits → difficulty pill not highlighted
       - Tap difficulty pill → ranker opens with "Cancel" top-left
       - Complete ranking → checkmark shows for 1s, sheet dismisses, pill bounces
       - Open ranker when difficulty already set → "Unset" button visible top-right
       - Tap "Unset" → difficulty cleared, sheet dismisses
       - Tap "Cancel" → sheet dismisses without changes
