# Sync email, isPremium

I want to also sync email and isPremium. I want to display both on the settings tab.


# Change all references to `tasks` to account for a new heiarchy. A task can either be a `todo` or a `habit`. Task is the general term. Please update the UI and any code/documentation to be clear on this. In the past I never used the word `todo` I just used `tasks` to mean a non-habit task.

# Add tags

Add tags to all tasks (both todos and habits)
Remove the description from the tasks.
Make sure that all tasks are the same height in the list view. If a task has lots of text as a title then truncate it with `...`. Bare in mind thin phones.
Show all of the tags underneath the text. If there are so many tags that it's running out of space then truncate that too but show the user that there are more
The tags should be synced just like the tasks and trades.
Both habits and todos can have tags, they can be added at any time.
When clicking `add tags` after clicking on a task, it should pop up with a new ui that lists all tags and opens a text box for you to search and filter. It will filter depending on what you type and in the list there should be tickboxes such that you can select multiple. 
Also beside each entry in the list, it should be a color button. Clicking that will bring up a modal that is a color picker. 
You should also be able to add new ones too with a button. Creating new ones will give it a random color hex.

first add tests to the backend if any,
then make the tests pass
then implement the frontend changes

# Remove homepage, that is now just `tasks`

# Add rewards tab

Plan a big feature change. Add a `rewards` tab. It should look like the tasks tab. It should be synced the same as tasks, trades and tags. Rewards can be `purchased` with soy. 

They have a price to them similar to the tasks. This price is derived from the tasks max_daily_freqency against the actual frequency for this task. This can be calculated with the `trades`. How many trades have been made for this task and when was the task created. It should only consider the past 2 months and calculate the rate from that. If a reward has been purchased at a rate far fewer than the max_daily_freqency in the past 2 months, then it should be cheaper.

Rewards can have tags too

The rewards tab should have a sort by for: (just like the tasks do)
newest/oldest
max_daily_frequency rate highest to lowest
max_daily_frequency rate lowest to highst
price cheapest to most expensive
price most expensive to cheapest (default)

Also they should the information in the task itself in the List, just like how tasks does.

First write new tests on the backend.
Make sure the new tests pass
Then change the frontend
The frontend should have 

# Add a trades tab

This new tab after `tasks` and before `settings` will be `trades`. This should list all trades just like the tasks. This should look very similar to the tasks tab. It should have "Both", "Reward", "Trade"and then the sort by.


|Trades                       |
|Both, Reward, Task           |
|              sort by newest | (or oldest, or cheapest or most expensive. Newest is default)
It should also show the balance in the top, just the same as tasks view.

Make sure to re-use and abstract out components dont repeat yourself too much.
Each trade should look like

|[type][name]     amount | where type is "Bought" or "Sold"
|tags                    |

