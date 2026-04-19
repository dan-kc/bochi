# List Sorting and Filtering

## Purpose

This document explains how the iOS app stores and applies list sorting and filtering for habits and rewards.

The important rules are:

- sort and filter preferences are local to the device
- preferences persist across app relaunches
- preferences do not sync to the server
- habits and rewards keep separate saved list views
- list controls only open when the user is scrolled back to the top

## Design Goals

- A user can leave the app and return to the same list view they were using.
- Habit sorting/filtering should not leak into the rewards screen, or vice versa.
- Saved list preferences should follow the same local-vs-account ownership model as the rest of the iOS stores.
- Filtering by tags should support both broad scanning and narrow matching.
- Changing sort/filter settings should not accidentally fire while the user is partway down a long list.

## Persisted Model

The iOS app stores list preferences in `ListPreferencesStore`.

Like the other local stores, the data is partitioned by owner:

- `local-device` while signed out
- backend user id while signed in

For each owner, the store keeps:

- habit list preferences
- reward list preferences

Each list preference payload contains:

- `sort`
- `difficultyFilter`
- `frequencyFilter`
- `selectedTagIDs`
- `tagMatchMode`

The file is local JSON in Application Support, the same persistence layer used by the other iOS stores.

## Available Sorts

Both habits and rewards support the same sort menu:

- Date created (oldest to newest)
- Date created (newest to oldest)
- Difficulty (lowest to highest)
- Difficulty (highest to lowest)
- Price (lowest to highest)
- Price (highest to lowest)

Default sort:

- Price (highest to lowest)

Implementation notes:

- For habits, “difficulty” means `difficultyTier`.
- For rewards, “difficulty” means `damageTier`.
- For habits, “price” is the computed tofu reward.
- For rewards, “price” is the computed tofu cost.
- Items without a meaningful price or difficulty sort after items with a value.
- Ties fall back to `createdAt`, then `id`, so the list stays stable.

## Available Filters

Both screens support the same filter categories:

- Has difficulty set
- Does not have difficulty set
- Has freq set
- Does not have freq set
- Tags

Field-name mapping:

- habits use `difficultyTier` and `frequency`
- rewards use `damageTier` and `maxFrequency`

The field filters are tri-state internally:

- no filter
- has value
- missing value

This lets the user clear a filter without resetting the rest of the list state.

## Tag Filtering

The tags menu supports two match modes:

- `Match Any Tag`
- `Match All Tags`

Behavior:

- no selected tags means tag filtering is off
- `Match Any Tag` shows items with at least one selected tag
- `Match All Tags` shows only items that contain every selected tag

Only tags that are currently attached to at least one item in that screen are shown in the menu:

- habit screen shows tags used by habits
- reward screen shows tags used by rewards

## Scroll Locking

The sort/filter/tag buttons stay visible under the title, but they are disabled unless the list is scrolled all the way back to the top.

This is intentional user-protection behavior.

Without it, a user who is halfway through a long list could accidentally:

- open a menu
- change the sort
- lose their reading position because the rows reorder immediately

So the rule is:

- controls remain visible for context
- controls only activate when the current list offset is back at the top

If the filtered result becomes empty, the screen resets the control lock so the user can immediately clear or change filters from the empty state.

## Empty States

There are two different empty states:

1. No data exists yet
   - The app shows the normal “No Habits Yet” or “No Rewards Yet” message.

2. Data exists, but the current filters hide everything
   - The app shows a filtered empty state.
   - The empty state includes a `Clear Filters` action.

This distinction matters because the second case is not a setup problem.
It is just a saved view-state problem.

## Ownership and Migration

Because list preferences are owner-scoped locally, they switch along with the rest of the stores when auth state changes.

When a signed-out local user later signs in on the same device:

- local list preferences migrate to that signed-in owner bucket
- the migration stays local only
- nothing is sent to the server or included in sync

That keeps the iOS behavior consistent with the rest of the local stores while preserving the “preferences are device-local” rule.
