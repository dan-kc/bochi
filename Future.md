I am writing a swift IOS app in ./ios. I am losely basing it off of the react-natige project in ./frontend
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.

Flesh out the Rewards section. This works in inverse of the habits section where users can purchase rewards and spend their balance. This has similar fields but has a maximum frequency instead of a minimum frequency, and has "damage" instead of difficulty. The damage should determin which rewards inflict the most damage to the user. The prices of the reward reflects this damage.

You can find the fields / price calculations in ./frontend where I implemented rewards before.

When implementing this solution, re-use the tags component. A reward can have the same tags as a habit.

There should be a new RewardFormView, it should be more or less identical to Habits. I want you to cleverly abstract where you think is fit. There will not be another similar section, these are the only two. Ask me questions about where you should abstract things. I don't want to have to change in two places all the time but I don't want to go too far. In React I would put lots of the logic in for the habits into hooks but I don't know what to do in Swift. Ask me questions and use your intuition

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
