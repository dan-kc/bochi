# Pricing

## Purpose

This document states the current iOS pricing equations used in `./ios`.

There are two related calculations:

- habit completion reward: how much tofu the user earns
- reward purchase cost: how much tofu the user spends

The two calculations now differ at the top level:

`habitReward = round(100 * T_h * F_h)`

`rewardCost = round(100 * G * T_r * F_r)`

where:

- `G` is the user-configurable general difficulty
- `T` is the fixed tier multiplier
- `F` is the frequency multiplier

Behaviourally:

- changing general difficulty only changes reward purchase cost
- changing general difficulty does not change habit completion reward

There is no random pricing component anymore.

## Design Goals

- The user should pick from a small stable set of tiers instead of maintaining relative rankings.
- Harder habits should always pay more than easier ones when frequency is equal.
- More damaging rewards should always cost more than less damaging ones when frequency is equal.
- The displayed reward price should react quickly enough to match the cap the user entered.
- Monthly and daily frequencies should both be handled by the same rule.
- Equivalent rates such as `1/day` and `30/month` should stabilize the same way.
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

- `trivial = 0.2`
- `light = 0.6`
- `medium = 1.0`
- `hard = 1.4`
- `extreme = 2.0`

These values come from taking the previous tier multipliers and scaling each
tier's distance from the neutral `1.0` baseline by `4x`.

### Reward Damage Multipliers

- `harmless = 0.2`
- `light = 0.6`
- `medium = 1.0`
- `heavy = 1.4`
- `extreme = 2.0`

As with habits, reward damage uses the same `4x` scaling away from the neutral
`1.0` baseline, so low-damage rewards get cheaper and high-damage rewards get
more expensive much faster than before.

## Shared Cadence Model

Implemented in `ios/tofustash/Shared/Models/PricingTiers.swift` via `CadenceDecayPricing`.

Both habits and rewards now use the same recency model.

The app does **not** count actions inside a fixed window such as:

- last 7 days
- last 24 hours

Instead, every past action contributes a fading amount of recent usage.

### Inputs

Let:

- `f` = configured frequency in times/day
- `tau = 1 / f`
  - this is the target spacing in days between actions
- `t_i` = timestamp of a past completion or purchase
- `now` = current timestamp

Examples:

- `3/day => tau ~= 0.333 days ~= 8 hours`
- `1/day => tau = 1 day`
- `30/month ~= 1/day => tau = 1 day`
- `2/month ~= 2/30 day^-1 => tau = 15 days`

This is the key normalisation rule:

- if two user-entered frequencies mean the same times/day rate, they get the
  same `tau`
- therefore `1/day` and `30/month` behave the same

### Decayed Usage Score

For a list of past action timestamps:

`U = sum over all actions i of exp(-(now - t_i) / tau)`

Behaviourally:

- recent actions matter more than old ones
- fast-cadence items forget history quickly
- slow-cadence items remember history longer

### Normalised Usage Ratio

If actions happen exactly on schedule forever, the decayed score tends to:

`1 + e^-1 + e^-2 + ... = 1 / (1 - e^-1) ~= 1.582`

So the app normalises with:

`r_raw = U / 1.582`

This keeps "on target cadence" near ratio `1`.

### Cold-Start Warm-Up

Brand-new habits and rewards should not overreact when history is still sparse.

Let:

- `ageDays` = days since the habit or reward was created
- `warmupDays = 2 * tau`
- `w = min(1, ageDays / warmupDays)`

Then:

`r_eff = w * r_raw + (1 - w) * r_neutral`

Important behaviour:

- the warm-up depends only on the normalised rate
- it does **not** depend on whether the user entered day/week/month in the UI
- equivalent rates therefore stabilize equally fast

The neutral ratio differs by entity type:

- habits use `r_neutral = 1`
- rewards use `r_neutral = 0`

Reason:

- a new habit should start near its neutral payout instead of jumping straight
  to maximum reward
- a new reward should start near its base price instead of becoming expensive
  before the user has any real purchase history

## 1. Habit Completion Reward

Implemented in `ios/tofustash/Habits/Utilities/RewardCalculation.swift`.

`Reward = round(100 * T_h * F_h)`

### Tier Multiplier

`T_h` comes directly from the selected habit difficulty tier.

If the habit has no tier yet, iOS calculation code falls back to `medium = 1.0`.

This fallback exists so helper functions remain deterministic, but the app
still blocks trading until the user has set both frequency and difficulty.

### Frequency Multiplier

Let:

- `f_h` = target habit frequency in times/day
- `tau_h = 1 / f_h`
- `r_h_eff` = cadence-adjusted completion ratio from the shared model
- `alpha = 3.75`

Then:

`F_h = 2 / (1 + (r_h_eff ^ alpha))`

If no frequency is set, the fallback is:

`F_h = 1`

Behaviourally:

- `r_h_eff = 0  =>  F_h = 2`
- `r_h_eff = 1  =>  F_h = 1`
- `r_h_eff > 1  =>  F_h < 1`

This means:

- under-done habits pay more
- on-target habits pay the base amount
- over-done habits pay less
- compared with the previous curve, pricing now reacts about `50%` more
  aggressively to the same cadence drift

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
- `tau_r = 1 / f_r`
- `r_r_eff` = cadence-adjusted purchase ratio from the shared model
- `beta = 4.5`

Then:

If `r_r_eff >= 1`:

`F_r = 50`

If `r_r_eff < 1`:

`F_r = min(50, (2 / (1 - (r_r_eff ^ beta))) - 1)`

If no max frequency is set, the fallback is:

`F_r = 1`

Behaviourally:

- buy prices ramp up sooner as the user approaches the configured cap
- compared with the previous curve, frequency pressure is about `50%` stronger
  for the same purchase history
- `r_r_eff = 0  =>  F_r = 1`
- `r_r_eff -> 1 from below  =>  F_r -> +infinity`, but the implementation clamps to `50`
- `r_r_eff >= 1  =>  F_r = 50`

This means:

- the first purchase of a new or lightly used reward is near base price
- repeated recent purchases raise the price
- buying at or above the intended cadence becomes extremely expensive

### Why This Replaces A Fixed Window

The old problem was:

- short windows work for `3/day`
- longer windows work for `2/month`
- no single hard window works well for both

Cadence-scaled decay fixes that because the memory length comes from `tau`.

Examples:

- `3/day` uses `tau ~= 8 hours`, so same-day repeat purchases still move price quickly
- `2/month` uses `tau = 15 days`, so purchases from last week still matter
- `1/day` and `30/month` both normalise to `tau = 1 day`, so they behave the same

## 3. Multi-Quantity Behaviour

### Habit Claim Modal

For claiming `q` times from a habit with current completion timestamps `H`:

`TotalHabitReward(q) = sum of Reward(H with each newly projected claim appended one by one)`

So the total is generally not:

`q * Reward(current state)`

because `F_h` changes after each projected increment.

### Reward Buy Modal

For buying `q` times from a reward with current purchase timestamps `P`:

`TotalRewardCost(q) = sum of Cost(P with each newly projected buy appended one by one)`

So the total is generally not:

`q * Cost(current state)`

because `F_r` changes after each projected increment.

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
  habits have the same frequency and completion history.
- A more damaging reward tier always costs more than a less damaging reward
  tier when the two rewards have the same cap and purchase history.
- Raising general difficulty makes rewards more expensive without changing
  habit payouts.
- Habit rewards fall as the user keeps completing the same habit toward or
  above its intended cadence.
- Reward prices rise as the user keeps buying the same reward toward or past
  its intended cadence.
- Rewards remain purchasable after the cap, but they become extremely
  expensive because the frequency multiplier clamps at `50`.
- Recent actions matter more than old ones, but old actions fade smoothly
  instead of dropping out at a hard time boundary.
- Equivalent rates such as `1/day` and `30/month` behave the same because the
  app normalises everything to times/day before pricing.
- The same inputs always produce the same price. There is no time-bucket or
  pseudo-random drift in the current system.

## 6. Notes On Current Semantics

- Habit `frequency` is stored on iOS as times/day.
- Reward `maxFrequency` is stored on iOS as times/day.
- Habit difficulty is stored as `difficultyTier`.
- Reward damage is stored as `damageTier`.
- Habit and reward pricing both use timestamp-based cadence decay.
- There is no relative ranking and no random multiplier.
