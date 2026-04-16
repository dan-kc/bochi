I am porting a react-native (./frontend) app to native IOS swift (./ios).
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.

The "claim reward" button is broken. When the claim modal pops up, the 

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
