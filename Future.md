I am writing a swift IOS app in ./ios. This is a habit tracking app where you have habits and rewards. You do habits to earn in-game currency, you spend them on rewards. An example habit is "10 pushups" or "Cold message a friend". An example reward is "Eat 1 chocolate bar" or "Spend 15 minutes on TikTok".

Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.
For features that cannot be simply explained with code, write appropriate documentation in ./docs. Observer the auth document too see the level of detail I need.

Scour ./ios and look for oppertunities to refactor. Specifically I want to keep the codebase as dry as possible. I do not want to go too extreme, but I'd say I want 8/10 DRYNESS. Also, keep an eye out for oppertunities to better group functionality/logic into classes, but I strongly avoid inheritance unless it is super obvious. List all of the changes and ask lots of questions on the specific abstractions and give me options 

# NEXT

Fix compile warnings

Remove Bought and Sold

Tag row and button row same size

Remove bg color in habit/reward list

Update seed

Tasks

# Todos?
