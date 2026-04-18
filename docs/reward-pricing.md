# Reward Pricing

## Purpose

This document explains how reward prices are calculated in the iOS app, and why the buy flow does not simply multiply one visible price by the selected quantity.

The important rule is:

- reward pricing is based on a rolling 24-hour purchase window

That means a reward with a cap like `3/day` should get more expensive during the same day as the user keeps buying it.

## Design Goals

- The displayed reward price should react quickly enough to match the cap the user entered.
- The buy modal should use the same rising-price logic as repeated single purchases.
- Multi-buy totals should reflect each incremental purchase, not `currentPrice * quantity`.
- The same pricing rule should be reused everywhere the iOS app shows or spends a reward price.

## Core Model

Reward price uses this formula in `RewardPriceCalculation`:

- `price = round(100 * G * D_r * F_r * R)`

Where:

- `G` is the user-configured general difficulty
- `D_r` is the reward damage multiplier from the reward ranking
- `F_r` is the reward frequency multiplier from recent purchases
- `R` is a small deterministic random multiplier that stays fixed inside the current 30-minute bucket

## Frequency Behaviour

The reward frequency multiplier uses:

- the reward's `maxFrequency`, stored as times per day
- the count of purchases for that reward in the last 1 day

This is deliberate.

If the user sets a reward to `3/day`, they expect:

1. the first purchase today to use the base price
2. the second purchase today to cost more
3. the third purchase today to cost even more
4. later purchases today to become very expensive

Using a long window like 60 days makes early same-day purchases look flat because the ratio barely moves. A 24-hour window keeps the app aligned with the way the cap is expressed in the UI.

## Multi-Buy Behaviour

The buy modal totals purchases one at a time:

1. calculate the first purchase price from the current purchase count
2. increment the purchase count
3. calculate the next purchase price
4. repeat until the selected quantity is reached

This means:

- buying 2 rewards is usually not the same as `currentPrice * 2`
- buying 3 rewards is usually not the same as `currentPrice * 3`

The total intentionally matches what would happen if the user tapped Buy repeatedly inside the same pricing bucket.

## Where This Rule Is Used

The iOS app uses the same pricing window and calculation path in:

- `RewardsView` for the list price
- `RewardFormView` for the edit-sheet price preview
- `RewardPurchaseModalView` for the multi-buy total
- `RewardPurchaseService` for the actual trade records and balance deduction

This keeps the visible price, the modal total, and the persisted trades in sync.
