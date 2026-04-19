I am writing a swift IOS app in ./ios. I am losely basing it off of the react-natige project in ./frontend
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.
For features that cannot be simply explained with code, write appropriate documentation in ./docs. Observer the auth document too see the level of detail I need.
This is a habit tracking app where you have habits and rewards. You do habits to earn in-game currency, you spend them on rewards. An example habit is "10 pushups" or "Cold message a friend". An example reward is "Eat 1 chocolate bar" or "Spend 15 minutes on TikTok".

---

The set difficulty modal UI is ugly. I like the title bar with unset, cancel and save.
Underneath that have a horizontal list of difficulties that is horizontally scrollable. IT should be quite large and should center on the currently selected one. Also the currently selected one should be orange. They should all be pill shaped, gray unless it is currently selected in which case it is orange.
Underneath that have the explaination text, underneath that have the example test.
This should all fit in a .medium modal.

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
