# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that.
Use strict TDD, always write unit tests first. No UI tests.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

Ensure that when a user taps on a habit list item it opens the change menu. Currently it opens the NameDesc modal when you tap on the name or desc, but not when i tap the rest of it. It also currently opens the appropriate modal when tapping on the frequency/tags/difficulty which is good, but I need it to work for the rest of the item. Also ensure that when you tap on the description, it focuses on the description in the NameDesc modal

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
