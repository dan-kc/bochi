# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that.
Use strict TDD, always write unit tests first. No UI tests.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Change the behaviour of the Habit new/change form in the following way:

In the Habit new/change form, a user should be able to Click on the whitespace to open the main tags section. Instead of having each tag open up the tags modal, ensure that whole section is the button effectively. You should also remove the buttons from the tags themselves too, as it should all be covered from touching the section. Also, keep the "tags" pill in the pill list section when a tag is added. Currently, if there is one or more tags then it will automaticaaly remove itself from the pill list. I want it to still feature in the pill list but be hilighted orange, similar to the frequency pill but have it still say "tags".

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
