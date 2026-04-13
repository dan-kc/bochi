# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that. Document behaviours too.
Use strict TDD, always write unit tests first. No UI tests. When writing tests, ensure you comment what behaviour you are testing for. I do not want redundant tests. This should resemple BDD. If there is no appropriate test, don't write one. I only want relevant BDD tests that match user workflows in the app.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Remove the confirm Discard modal popup completely. It should never pop up. If a user taps on the outside of the new habit modal/form, or if they hit cancel, it should automatically cancel straight away and return to the HabitList view. However, it should also spawn a Toast saying something like "New Habit Discarded, Recover?" - giving the oppertunity for a user to recover the recently discarded new habit.

5 second timer on the toast, visible on the toast itself. Toasts should stack over eachother if multiple are live, clearing one toast should reveal the other. All toasts should be the same size. One shold be able to swipe away the Toast or wait until the timer is done, or tap on a button somewhere to clear it, or press on the "recover" (or some other word) button to recover the item, which brins up the new form again (but does not focus on anything - usually the new form auto focuses on Name but not this time)

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

# NEXT old stuff for the height etc...

Change the logic around the height of the new/change modal. It is sometimes is too small. Whatever calculations are being run to determin the height of this modal is incorrect. I want it to work as follows:

- Default height: small enough to contain the entire contents of the form.
- When the content is larger than the height, the height of the modal should increase accordingly. It should gradually be getting taller from the bottom. This should update as it is done. For example when a tag is added and the tag row is now rendered, it should immediately be taller. If I add a newline to the description, is should immediately be taller. (Note that it probably still wont reach the top of an iPhone Pro Max 17 because the description has a max size before truncation)
- Once the modal reaches the top (possible on shorter devices), it is then scrollable.

Also remove the bar on the modal that allows you to drag the form. It's height should only be derived from its contents.

When I tap on "+" to create a new habit I see this. @IMG*0374.PNG This is a perfect initial height for the NameDescription modal.
I then type out a long description with many newlines and my cursor begins to flow underneath the keyboard as seen here @IMG_0375.PNG I then have to scroll to see it. I do not want the user to ever have to scroll to see their cursor. The cursor should \_always* be in view. I want the modal to here to get taller and for the cursor to remain at the bottom.

To show you how it's done, this is the behaviour from the todoist app after pressing the '+' button: @IMG_0376.PNG
And when i type in the descripiton and make it really long: @IMG_0377.PNG observer how the modal increases in height
And when i type such that the description overflows and the modal is at max height: @IMG_0378.PNG observe that it is now a scrollable container where whenever I type, the viewbox scrolls to the cursor position such that it's at the bottom. This also happens when I scroll the container to the top and start typing with the cursor still at the bottom, it will auto scroll to the correct position

Fix this for the NameDescription modal, we will look at the change modal later.

Also, could this article be relevant? https://dev.to/mrcflorian/managing-the-keyboard-in-swiftui-a-comprehensive-tutorial-11p0
