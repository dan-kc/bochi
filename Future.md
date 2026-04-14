# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that. Document behaviours too.
Use strict TDD, always write unit tests first. No UI tests. When writing tests, ensure you comment what behaviour you are testing for. I do not want redundant tests. This should resemple BDD. If there is no appropriate test, don't write one. I only want relevant BDD tests that match user workflows in the app. Most tests should fail first, Red, Green, Refactor. But I am not strict for that, indeed if there is a behaviour that ought to be a test it should be added even if it already passes.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Implement the tofu reward amount calculation feature from the old frontend. Each habit should have a reward amount derived from its properties.
Implement a tofu balance feature that tracks the current tofu balance of the user.
Also add to settings the "general difficulty" so you can properly calculate the value.

# Balance

A users balance should be displayed in the top right of the ui, regardless of what view you are on, it needs to be always visible. I think it should be on the same line as the "Habits" title. Make it big, similar size to the Title. It should be "1000T" for example where T is some appropriate icon.

# Trade buttons

- Each habit list item should have the price in a button on the RHS of the item. The button should open a "trade" modal.
- A button should also feature in the habit change view (NOT on the new view) at the bottom. (Make the modal slightly taller as it will need more space). This should also open the trade modal

# trade modal

Should have the following:
- The name of the Habit (non editable from this modal)
- "Cancel" button verbatim
- "Claim" button verbatim that executes the trade
- A counter for the quantity (this should be the main center peice of the modal). one habit could be "Do 10 pushups" for example, and if i do 20, I want a way to indicate that I've cliamed this reward twice. 
- The total price of everything. Bare in mind that the calculated reward should not just be double what the price is if I put the count at 2. This is because purchasing 1, changes the prices of the next as per the formula found in ./frontend. So this calculation needs to account for that.

  Tapping cancel should hide the modal and return to either the change form or the habitList depending on where you opened the modal. 

  Tapping yes should display some animation to user indicating they just cliamed a reward, then it should close the modal and always return to the habit list view. It should also animate the total tofu balance in the top bar next to the title over 2 seconds because the total should have changed. Also, at the same time the balance is animating, the price/reward amount should animate in the change view and the habit list item, to it's new value (because the price/reward amount is derived from how ofen you do the habit, so it should generally change after completing a habit).

# Delete button

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
