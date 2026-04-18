# Pricing

## Purpose

This document states the current iOS pricing equations used in `./ios`.

There are two related calculations:

- habit completion reward: how much tofu the user earns
- reward purchase cost: how much tofu the user spends

Both share the same outer form:

`value = round(100 * G * T * F)`

where:

- `G` is the user-configurable general difficulty
- `T` is the fixed tier multiplier
- `F` is the frequency multiplier

There is no random pricing component anymore.

## Design Goals

- The user should pick from a small stable set of tiers instead of maintaining relative rankings.
- Harder habits should always pay more than easier ones when frequency is equal.
- More damaging rewards should always cost more than less damaging ones when frequency is equal.
- The displayed reward price should react quickly enough to match the cap the user entered.
- Multi-claim and multi-buy totals should reflect each incremental action, not `currentPrice * quantity`.
- The same pricing rule should be reused everywhere the iOS app previews, displays, and persists prices.

## Tier Model

Habit difficulty is stored as:

- `trivial`
- `light`
- `medium`
- `hard`
- `extreme`

Reward damage is stored as:

- `harmless`
- `light`
- `medium`
- `heavy`
- `extreme`

These are absolute categories, not relative positions. Adding a new habit or
reward does not force the user to re-rank existing items.

### Habit Difficulty Multipliers

- `trivial = 0.8`
- `light = 0.9`
- `medium = 1.0`
- `hard = 1.1`
- `extreme = 1.25`

### Reward Damage Multipliers

- `harmless = 0.8`
- `light = 0.9`
- `medium = 1.0`
- `heavy = 1.1`
- `extreme = 1.25`

## 1. Habit Completion Reward

Implemented in `ios/tofustash/Habits/Utilities/RewardCalculation.swift`.

`Reward = round(100 * G * T_h * F_h)`

### Tier Multiplier

`T_h` comes directly from the selected habit difficulty tier.

If the habit has no tier yet, iOS calculation code falls back to `medium = 1.0`.

This fallback exists so helper functions remain deterministic, but the app
still blocks trading until the user has set both frequency and difficulty.

### Frequency Multiplier

Let:

- `f_h` = target frequency in times/day
- `c_h` = completions in the last 7 days
- `alpha = 2.5`

Then expected completions are:

`E_h = 7 * f_h`

and the completion ratio is:

`r_h = c_h / E_h`

The current iOS implementation does not use age blending for habits, so:

`r_h_eff = r_h`

and:

`F_h = 2 / (1 + (r_h_eff ^ alpha))`

If no frequency is set, the fallback is:

`F_h = 1`

Behaviourally:

- `r_h = 0  =>  F_h = 2`
- `r_h = 1  =>  F_h = 1`
- `r_h > 1  =>  F_h < 1`

### Habit Setup Gating

The habit claim flow is blocked until both of these are set:

- `frequency`
- `difficultyTier`

The UI explains what is missing using `RewardCalculation.missingTradeProperties`.

## 2. Reward Purchase Cost

Implemented in `ios/tofustash/Rewards/Utilities/RewardPriceCalculation.swift`.

`Cost = round(100 * G * T_r * F_r)`

### Tier Multiplier

`T_r` comes directly from the selected reward damage tier.

If the reward has no tier yet, iOS calculation code falls back to `medium = 1.0`.

As with habits, the helper stays deterministic but the UI still blocks buying
until the user has set both max frequency and damage tier.

### Frequency Multiplier

Let:

- `f_r` = max healthy purchase rate in times/day
- `c_r` = purchases in the last 1 day
- `beta = 3`

Then expected purchases are:

`E_r = f_r`

and the purchase ratio is:

`r_r = c_r / E_r`

The multiplier is:

If `r_r >= 1`:

`F_r = 50`

If `r_r < 1`:

`F_r = min(50, (2 / (1 - (r_r ^ beta))) - 1)`

If no max frequency is set, the fallback is:

`F_r = 1`

Some useful values:

- `r_r = 0  =>  F_r = 1`
- `r_r = 1/3  =>  F_r ~= 1.077`
- `r_r = 2/3  =>  F_r ~= 1.842`
- `r_r -> 1 from below  =>  F_r -> +infinity`, but the implementation clamps to `50`

### Reward Pricing Behaviour

Reward pricing uses a rolling 24-hour purchase window.

This is deliberate.

If the user sets a reward to `3/day`, they expect:

1. the first purchase today to use the base price
2. the second purchase today to cost more
3. the third purchase today to cost even more
4. later purchases today to become very expensive

Using a long window like 60 days makes early same-day purchases look flat because the ratio barely moves. A 24-hour window keeps the app aligned with the way the cap is expressed in the UI.

## 3. Multi-Quantity Behaviour

### Habit Claim Modal

For claiming `q` times from a habit with current completion count `c_h`:

`TotalHabitReward(q) = sum from i = 0 to q - 1 of Reward(c_h + i)`

So the total is generally not:

`q * Reward(c_h)`

because \(F_h\) changes after each increment.

### Reward Buy Modal

For buying `q` times from a reward with current purchase count `c_r`:

`TotalRewardCost(q) = sum from i = 0 to q - 1 of Cost(c_r + i)`

So the total is generally not:

`q * Cost(c_r)`

because \(F_r\) changes after each increment.

## 4. Where This Rule Is Used

The iOS app uses the same habit reward and reward pricing calculation paths in:

- `HabitsView` for habit reward previews
- `HabitFormView` for the edit-sheet reward preview
- `TradeModalView` for multi-claim totals
- `RewardsView` for reward price previews
- `RewardFormView` for the edit-sheet price preview
- `RewardPurchaseModalView` for multi-buy totals
- `RewardPurchaseService` for the actual trade records and balance deduction

This keeps the visible price, the modal total, and the persisted trades in sync.

## 5. User-Facing Behaviour

- A harder habit tier always pays more than an easier habit tier when the two
  habits have the same frequency and completion count.
- A more damaging reward tier always costs more than a less damaging reward
  tier when the two rewards have the same cap and purchase count.
- Habit rewards fall as the user keeps completing the same habit above its
  desired rate.
- Reward prices rise as the user keeps buying the same reward toward or past
  its desired cap.
- Rewards remain purchasable after the cap, but they become extremely
  expensive because the frequency multiplier clamps at `50`.
- The same inputs always produce the same price. There is no time-bucket or
  pseudo-random drift in the current system.

## 6. Notes On Current Semantics

- Habit `frequency` is stored on iOS as times/day.
- Reward `maxFrequency` is stored on iOS as times/day.
- Habit frequency response is measured over a rolling 7-day window.
- Reward price response is measured over a rolling 24-hour window.
- Habit difficulty is stored as `difficultyTier`.
- Reward damage is stored as `damageTier`.
- There is no relative ranking and no random multiplier.
