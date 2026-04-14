# Base

I am writing a native IOS version (./ios) of an existing react-native frontend (./frontend).
Do not copy any styling. Use default SwiftUI styling including icons etc.
Write comments assuming I don't know anything about Swift. When comparable, compare to React as I am an expert in that. Document behaviours too.
Use strict TDD, always write unit tests first. No UI tests. When writing tests, ensure you comment what behaviour you are testing for. I do not want redundant tests. This should resemple BDD. If there is no appropriate test, don't write one. I only want relevant BDD tests that match user workflows in the app. Most tests should fail first, Red, Green, Refactor. But I am not strict for that, indeed if there is a behaviour that ought to be a test it should be added even if it already passes.
Ensure the codebase is as DRY as possible. Do not repeat code when avoidable.
Use `ios-test` to run unit tests, this may take a few minutes. Outside of this, do not run any xcode commands - notify if you need me to run any.

# Rewards

Make the textbox "search tags..." always have focus. The IOS keyboard should always be out when this modal is open. It should only close when one opens the edit tag modal. Ensure that the tick in the top right is always visible. Currently it dissapears While the user is typing until they hit the "X" next to the keyboard.

# Rewards

Implement the rewards section. See how it is implemented in ./frontend.

Much of the content in the rewards section will be very similar to the habits section. Be sure to keep things DRY and re-use when appropriate. Do not over abstract be reasonable. Ask if you are unsure.

Copy UI decisions from the Habits page in ./ios.

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
