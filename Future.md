I am porting a react-native (./frontend) app to native IOS swift (./ios).
Use default SwiftUI styling including icons etc.
Write comments assuming I am an expert in React but 6 don't know anything about Swift.
Write comments documenting user behaviours.
Write tests when appropriate. When writing tests, ensure you comment what behaviour you are testing for. If there are no appropriate test, don't write one. Only write relevant BDD tests that match user workflows in the app. Do not run any tests, I will run them myself to validate.
Ensure the codebase is as DRY as **reasonably** possible.

# HabitForm

Make the contents of the habit form to adjust depending on its contents.

The new/change habit form should adapt to any size changes i.e when the trade button appears or the tag row appears.

The name description modal should have a small initial size, one line for the name, 3 for the description. The name field should always stay one line, but the description field can increase in size. When it does increase in size, the modal should gradually get taller until it is max height, after that it should be scrollable.

When a user taps "+" to create a new habit, it should immediately open the name & description modal, the user should not be aware of the habit form yet until they dismiss the name description modal, then it should animate (fade fields and increase or decrease in size) INTO the change modal. This animation should also happen when the user taps on the name or descripiton fields in the change/new form.

This is a dynamic height text field: https://github.com/winwx/DynamicTextEditor that may be helpful for using or inspiration for the name description modal as this adapts size as the modal gets bigger.

You may have to avoid using the Form component because it seems to always uses fullscreen as opposed to fit the content.

Also, there exists some logic for auto-focusing on a the name or description field depending on what button was pressed. I WANT THE IOS KEYBOARD TO OPEN AT THE SAME TIME AS THE NAME AND DESCRIPION MODAL. In all of my implementations so far, the modal has opened THEN the keyboard opens. I do not want this. It needs to be all in one animation.

I have attempted to implement this already but it is buggy and I want you to radically rethink things.

Currently there is a massive padding at the top of the name description modal and new/change modal. Also if i add a name and descripiton, then the modal suddently becomes super small and the content does not fix the sheet?





Implement the following spec:

A sheet that animates in from the bottom. It is triggered by tapping either the "+" (new), or the habit list item (change).

The new form should have the following:

- A cancel button in the top left
- A title "New Habit"
- A name button
- A description button
- A tags button
- A difficulty button
- A Frequency button
- A list of Tags

Tapping the cancel button (or tapping outside of the modal) should dismiss the modal.
Tapping name should open a "name description" form and focus the user on the name fields
Tapping description should open a "name description" form and focus the user on the description fields
Tapping tags should open the tags modal. If a tag is added, the tags should now appear in the form.

If anything adds content to the form, like how adding a tag adds 

This is a dynamic height text field: https://github.com/winwx/DynamicTextEditor for inspiration.


You may have to avoid using the Sheet component because it seems to always uses fullscreen as opposed to fit the content.



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
