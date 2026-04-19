I am writing a swift IOS app in ./ios. I am losely basing it off of the react-natige project in ./frontend
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.
For features that cannot be simply explained with code, write appropriate documentation in ./docs. Observer the auth document too see the level of detail I need.
This is a habit tracking app where you have habits and rewards. You do habits to earn in-game currency, you spend them on rewards. An example habit is "10 pushups" or "Cold message a friend". An example reward is "Eat 1 chocolate bar" or "Spend 15 minutes on TikTok".

---

Add filters and sorting to the habits and rewards list. The sort settings should persist on app close (but not saved to server or anything).

You should be able to sort by:

Date created (oldets to newest)
Date created (newest to oldest)
Difficulty (lowest to highest)
Difficulty (highest to lowest)
Price (lowest to highest)
Price (highest to lowest) (DEFAULT)

You should be able to filter by:

Has difficulty set
Does not have difficulty set
Has freq set
Does not have freq set

Then there should also be a tags filter which allows you to select the tags you want to see.

Put the UI right underneath the title and just above the list of habits/rewards. A user should only be able to press these butons if they are scrolled all the way up.

# NEXT

Scour codebase finding bad code/duplicates

Fix compile warnings

Remove Bought and Sold

Tag row and button row same size

Remove bg color in habit/reward list

Update seed

Tasks

# Todos?
