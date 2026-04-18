I am writing a swift IOS app in ./ios. I am losely basing it off of the react-natige project in ./frontend
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.
For features that cannot be simply explained with code, write appropriate documentation in ./docs. Observer the auth document too see the level of detail I need.
 
The logic for the reward price calculation seems to be incorrect. I have a reward with max freq 3/day. I have purchased it several times. it should increase in price every time. it seems to be stuck at 250. Also, if use the buy reward modal it seems to just multiply the current price. In the claim Habit reward it correctly changes the price according to how many you pick. If i claim rewards for 2x habits, the amount wont be 2 times the current price, it adjusts. Make sure this works in rewards too.

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
