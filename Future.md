Rewrite the frontend in kotlin.

- Language: Kotlin.
- UI Framework: Jetpack Compose (Declarative).
- Architecture: MVVM (Model-View-ViewModel).
- Asynchrony: Coroutines and Flow (for handling background tasks).
- Networking: Retrofit or Ktor.
- UI testing with Compose Testing Library
- Complete with dev scripts that do the following:

First, prepare my dev environment for a new project. I will be creating an android-only app with the following tech stack. It should live in the ./android directory.
- Add commands in the scripts.nix for interacting with the project. Anything I need for testing, linting, emulation. Also change the flake.nix for anything i need for kotlin development including language servers and formatters - the lot.
- Inform me of any options for local first implementation details etc.


# AFTER LAUNCH

# Styling

Make all of the styling like the

# Add a trades tab (OR JUST MAKE THE BALANCE A TOGGLE THAT BRINGS THIS UP?)

Add a new tab to the nav menu called trades. It is a page that lists all trades.

This should look similar to the habits tab.

It should have a sort by where you can sort by date (default) or amount.

This nav entry should be togglable in settings.

This setting is saved locally but not synced

Each entry/button in the list should look like
|[Date][Time] [type]
|[habit/reward name] ----------------------- amount |
where type is "Bought" or "Sold"

If the name is long, then it goes from 2 to up to 4 lines.

The buttons should bring up a modal like the Habits from the bottom of the screen. But it's not a form, It just shows all the info. The modal should have a button to refund.

# General

Plan a big change accross the whole stack.
