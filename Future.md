I am writing a swift IOS app in ./ios. I am losely basing it off of the react-natige project in ./frontend
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.
For features that cannot be simply explained with code, write appropriate documentation in ./docs. Observer the auth document too see the level of detail I need.

Review the pricing calculation for habits and rewards in ./docs/pricing.md.

This is a habit tracking app where you have habits and rewards. You do habits to earn in-game currency, you spend them on rewards. An example habit is "10 pushups" or "Cold message a friend". An example reward is "Eat 1 chocolate bar" or "Spend 15 minutes on TikTok".

Having maintained a similar system for myself, I noticed that it was too time consuming setting the price of things myself because when things change I need to keep updating it. I don't want to be able to just do 100 pushups and get what I want. There needs to be limits.

Instead we derive the price of a habit from it's "difficulty", it's "minimum desired frequency" and the number of times you've completed the habit recently. The difficulty is just how difficult it is relative to other habits, whereas the minimum desired frequency is a set number. Rewards are priced similarly, except with "damage" and "maximum desired frequency" instead.

Obviously the difficulty only really works if all habits are of reasonably similar difficulty, if one is MUCH harder than others then just having a relative ranking breaks down. But I don't want to have to rank them out of 10 instead, because what if something was a 10 and then you add a new habit that is harder, now that is the 10 and I'd have to re-calculate the rest. It's more upkeep.

Review what I have in ./docs/pricing.md and suggest improvements.

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
