# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that.
Use strict TDD, always write unit tests first. No UI tests.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Remove the feature where if you tap on the tags section in the habitRow it opens the tags section. It should just open the change form. In fact, make the entire row a button which opens the change form. There should be no other buttons on each list item. Ensure you only change the behaviour for the habitRow, DO NOT touch the behaviour in side of the change form.




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
