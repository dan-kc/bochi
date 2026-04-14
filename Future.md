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

# Delete button

Add a delete button to Habits. Also, swiping on the Habits in the list view should also delete them. Both of them should bring up a delete alert asking if they want to delete this habit. I'm not sure which way we should swipe to delete, I am probably going to add a different feature to the other direction swipe at a later date. Use whatever is idiomatic and Apple recommends.

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
