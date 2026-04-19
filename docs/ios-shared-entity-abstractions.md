# iOS Shared Entity Abstractions

## Purpose

This document explains the shared abstraction layer used by the iOS habits and rewards flows after the DRY refactor.

The important rule is:

- share repeated mechanics, not domain meaning

Habits and rewards look structurally similar in several places:

- both have owner-scoped persisted stores
- both have list screens with create/delete/recover flows
- both have edit forms with draft recovery, pill rows, and autosave
- both compute an action amount only when the entity is fully configured

Those similarities are now shared where the behaviour is genuinely the same. The user-facing concepts still stay separate.

## Design Goals

- Reduce copy-paste across habits and rewards without collapsing them into one generic feature model.
- Keep `HabitFormView`, `RewardFormView`, `HabitStore`, and `RewardStore` readable in their own domain language.
- Avoid inheritance and favor small composition helpers.
- Keep shared helpers pure when possible so they are easy to test.
- Make future refactors safer by documenting what is intentionally shared and what is intentionally still separate.

## Shared Layers

### `OwnerScopedRecordSupport`

This helper centralizes the repeated persistence mechanics used by owner-backed stores.

It handles:

- reading the current owner's records from `[ownerID: [Record]]`
- migrating local records into a signed-in owner bucket
- sorting records by `createdAt` with stable `RecordID` tie-breaking
- merging local and remote copies by `updatedAt`
- normalizing persisted records so canonical lowercase `RecordID` values win

Stores still own:

- their public API
- validation rules
- sync notification details
- record construction

This means:

- `HabitStore`, `RewardStore`, and `TradeStore` share the same merge/migrate mechanics
- `TagStore` reuses the same machinery for tags, habit-tag links, and reward-tag links

### `EntityFormSupport`

This helper centralizes the repeated behaviour rules used by both form screens.

It handles:

- trimming user-entered names before autosave/persist
- deciding whether a dismissed new draft is recoverable
- building pill rows from feature-supplied configs and attention states

Forms still own:

- their field names and terminology
- which secondary editors exist
- how drafts map back into `Habit` or `Reward`
- which pills should pulse in that feature

This keeps the shared behaviour testable without making the SwiftUI views unreadably generic.

### `EntityActionSupport`

This helper centralizes one small but repeated rule:

- only compute and expose sort/action amounts when the entity can actually be used

That keeps habits and rewards aligned on:

- hidden sort values for incomplete rows
- zero visible amount for incomplete actions

The actual pricing formulas still live separately in:

- `RewardCalculation`
- `RewardPriceCalculation`

because those rules are feature-specific.

### `EntityFloatingAddButton`

This view keeps the main habits and rewards tabs visually aligned on the default SwiftUI-style floating add affordance.

It is intentionally small:

- shared visuals only
- no shared screen state
- no shared routing model

## What Stayed Separate On Purpose

The refactor does **not** introduce a single generic entity framework.

These remain feature-specific on purpose:

- `HabitFormView` vs `RewardFormView`
- `HabitsView` vs `RewardsView`
- `HabitStore` vs `RewardStore`
- earn-price vs spend-price formulas
- habit wording such as `Claim Reward`
- reward wording such as `Buy Reward`

Why:

- the two features already diverge in naming, button behaviour, and pricing logic
- pushing further would add indirection faster than it would remove useful complexity
- this codebase targets high readability for future product iteration

## Testing Strategy

The shared helpers now own tests for the shared behaviour itself:

- record migration and normalization rules
- draft recovery rules
- pill animation rules
- actionable amount gating

Feature-specific tests still exist for user workflows that remain distinct:

- habit form pill labels and autosave rules
- reward form pill labels and autosave rules
- store-specific validation and soft delete behaviour

This keeps the tests DRY where the behaviour is truly shared, while preserving explicit workflow coverage where the user experience differs.
