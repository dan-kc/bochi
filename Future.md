# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that. Document behaviours too.
Use strict TDD, always write unit tests first. No UI tests. When writing tests, ensure you comment what behaviour you are testing for. I do not want redundant tests. This should resemple BDD. If there is no appropriate test, don't write one. I only want relevant BDD tests that match user workflows in the app.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Go over all tests in this project and add a behaviour comment or change the test to make it BDD. If there are any test cases that you think are impossible and will not be reached ever, then remove the test completely. I only want relevant BDD tests that match user workflows in the app. 

--------------

Change the logic around the height of the new/change modal. It currently sometimes is too small. Whatever calculations are being run to determin the height of this modal is incorrect. I want it to work as follows:

- Default height: small.
- When the content is larger than the height, the height of the modal should increase accordingly. It should gradually be getting taller from the bottom.
- Once the modal reaches the top, it is then scrollable.

Remove the bar on the modal that allows you to drag the form. It's height should only be derived from its contents.




Remove the Discard? modal completely. It should never pop up. If a user taps on the outside of the new habit modal/form, or if they hit cancel, it should automatically cancel straight away and return to the HabitList view. However, it should the spawn a Toast saying something like "New Habit Discarded, Recover?" - giving the oppertunity for a user to recover the recently discarded new habit.

5 second timer on the toast. Toasts should stack over eachother if multiple are live, clearing one toast should reveal the other. All toasts should be the same size. One shold be able to swipe away the Toast or wait until the timer is done, or tap on a button somewhere to clear it.

- Change the NameDescription 

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
