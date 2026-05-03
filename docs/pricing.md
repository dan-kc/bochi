# Pricing

This document specifies the current iOS pricing equations used in `./ios`.

There are two outputs:

- habit completion reward
  `habitReward = round(100 · T_h · F_h · D_h · S_h)`
- reward purchase cost
  `rewardCost = round(100 · G · T_r · F_r)`

Implemented in:

- shared cadence model: `ios/tofustash/Shared/Models/PricingTiers.swift`
- habit reward: `ios/tofustash/Habits/Utilities/RewardCalculation.swift`
- reward cost: `ios/tofustash/Rewards/Utilities/RewardPriceCalculation.swift`

## 1. What The System Is Trying To Do

The pricing model is trying to enforce two different behaviours:

- habits should pay more when they are under-done, and less when they are over-done
- rewards should cost more when they are being bought too often

The hard part is that "too often" depends on cadence:

- `3/day` should react on the scale of hours
- `2/month` should react on the scale of weeks
- `1/day` and `30/month` should behave identically, because they represent the same rate

So the system first converts user-entered frequency into a canonical internal
rate:

- `f ∈ [1/30, 100]` times/day
- `τ = 1 / f` days

Interpretation:

- `f` is the target rate
- `τ` is the target spacing between actions

Examples:

- `1/month ⟹   f = 1/30, τ = 30`
- `1/day ⟹   f = 1, τ = 1`
- `3/day ⟹   f = 3, τ = 1/3`
- `30/month ⟹   f = 1, τ = 1`

So `1/day` and `30/month` collapse to the same internal state.

## 2. Shared Cadence Model

### 2.1 Goal

We want a notion of "recent usage" with these properties:

- recent actions matter more than old actions
- old actions do not disappear at a hard cutoff
- the memory length should scale with cadence

So we use exponential decay instead of a fixed window.

### 2.2 Decayed Usage Score

Let:

- `now` be the current timestamp
- `H = (t₁, …, tₙ)` be the finite list of unresolved past action timestamps

Under the refund ledger model:

- normal completion/purchase trades contribute timestamps
- refund trades do not contribute timestamps
- if a normal trade is later refunded, its timestamp is removed from `H`

Define:

`U(H) = Σᵢ exp(-(now - tᵢ) / τ)`

Each term lies in `(0, 1]`, so:

- `U = 0` iff `H` is empty
- more recent actions contribute more
- for fixed action ages, smaller `τ` makes `U` smaller
- for fixed action ages, larger `τ` makes `U` larger

Interpretation:

- fast-cadence items forget history quickly
- slow-cadence items remember history longer

So refunds affect cadence by canceling the original action rather than by
adding a new cadence event of their own.

### 2.3 Why `U` Is Not Enough

`U` is a useful raw score, but not yet a ratio.

Its scale depends on cadence. For example, an "on schedule" `3/day` item and an
"on schedule" `1/week` item should both read as "normal", even though the raw
history patterns look very different in time.

So we normalise `U` against the idealised on-schedule limit.

### 2.4 Normalised Usage Ratio

If actions happen exactly every `τ` forever into the past, then:

`U = 1 + e⁻¹ + e⁻² + … = 1 / (1 - e⁻¹) =: C ≈ 1.5819767068693265`

Define:

`r_raw = U / C`

Interpretation:

- `r_raw < 1` means below target cadence
- `r_raw = 1` means on target cadence
- `r_raw > 1` means above target cadence

This is the first quantity that has a stable behavioural meaning across
different cadences.

### 2.5 Why `r_raw` Is Not Enough

`r_raw` is correct but too eager for brand-new items.

Reason:

- a new habit with no history has `U = 0`, hence `r_raw = 0`
- a new reward with no history also has `r_raw = 0`

But those two cases should not behave the same way:

- a new habit should start near neutral payout, not maximum under-use bonus
- a new reward should start near base price, which *does* correspond to `0` usage

So we introduce a warm-up blend. Early on, we trust history only partially.

### 2.6 Warm-Up

Define:

- `ageDays ≥ 0`
- `warmupDays = 2τ`
- `w = min(1, ageDays / warmupDays)`

Then define:

`r_eff = w · r_raw + (1 - w) · r_neutral`

where:

- for habits, `r_neutral = 1`
- for rewards, `r_neutral = 0`

Properties:

- `w ∈ [0, 1]`
- `ageDays = 0 ⟹   w = 0 ⟹   r_eff = r_neutral`
- `ageDays ≥ 2τ ⟹   w = 1 ⟹   r_eff = r_raw`
- `r_eff` always lies between `r_raw` and `r_neutral`

Interpretation:

- new habits start near `1`
- new rewards start near `0`
- after roughly two target intervals, the model uses the raw cadence ratio directly

So the shared cadence pipeline is:

`timestamps → U → r_raw → r_eff`

## 3. Tier Maps

Before cadence enters, each item has a static severity tier.

Habit difficulty map:

- `trivial ↦ 0.2`
- `light ↦ 0.6`
- `medium ↦ 1.0`
- `hard ↦ 1.4`
- `extreme ↦ 2.0`

Reward damage map:

- `harmless ↦ 0.2`
- `light ↦ 0.6`
- `medium ↦ 1.0`
- `heavy ↦ 1.4`
- `extreme ↦ 2.0`

These are absolute categories, not a relative ranking.

## 4. Habit Reward

### 4.1 Goal

A habit reward should combine four effects:

- harder habits should pay more
- under-done habits should pay more
- longer habits should pay more, but with diminishing returns
- higher benefit should pay more

Hence:

`habitReward = round(100 · T_h · F_h · D_h · B_h)`

with:

- `T_h ∈ {0.2, 0.6, 1.0, 1.4, 2.0}`
- `F_h ∈ (0, 2]`
- `D_h ∈ [1, 1.35]`
- `B_h ∈ {1.0, 1.3, 1.6, 2.0, 2.5}`

Fallbacks:

- missing habit tier `⟹   T_h = 0.2`
- missing habit frequency `⟹   f_h = 100/day`
- missing duration `⟹   D_h = 1`
- missing benefit `⟹   B_h = 1`

### 4.2 Habit Frequency Multiplier

#### Goal

We want a multiplier that:

- is high when recent completion cadence is low
- equals `1` at target cadence
- decays toward `0` as usage becomes very high

So define, with `α = 3.75`:

`F_h = 2 / (1 + r_eff^α)`

Properties:

- `F_h(0) = 2`
- `F_h(1) = 1`
- `r_eff < 1 ⟹   F_h > 1`
- `r_eff > 1 ⟹   F_h < 1`
- `F_h` is strictly decreasing for `r_eff ≥ 0`
- `r_eff → ∞ ⟹   F_h → 0`

So:

- under-done habits get a bonus
- on-target habits get base payout
- over-done habits get penalised

### 4.3 Duration Multiplier

#### Goal

Longer habits should pay more, but not linearly. A 2-hour habit should pay more
than a 1-hour habit, but not twice as much purely due to duration.

If duration is unset:

`D_h = 1`

Otherwise, for `durationSeconds` an integer in `[0, 43200]`:

`D_h = 1 + 0.35 · log(1 + durationSeconds) / log(1 + 43200)`

Properties:

- `D_h(0) = 1`
- `D_h(43200) = 1.35`
- `D_h` is strictly increasing
- `D_h` is concave

So duration increases reward with diminishing marginal effect.

### 4.4 Benefit Multiplier

#### Goal

Completing a more beneficial habit should make each completion worth more.

The map is:

- `1 ↦ 1.0`
- `2 ↦ 1.3`
- `3 ↦ 1.6`
- `4 ↦ 2.0`
- `5 ↦ 2.5`

This is strictly increasing.

## 5. Reward Cost

### 5.1 Goal

A reward cost should combine three effects:

- global harshness from user settings
- intrinsic damage of the reward
- recent purchase cadence

Hence:

`rewardCost = round(100 · G · T_r · F_r)`

with:

- `G > 0`
- `T_r ∈ {0.2, 0.6, 1.0, 1.4, 2.0}`
- `F_r ∈ [1, 20]`

Fallbacks:

- missing reward damage tier `⟹   T_r = 2.0`
- missing reward max frequency `⟹   f_r = 1/month`

Ignoring rounding and cadence, the base cost is:

`baseCost = 100 · G · T_r`

### 5.2 Why Rewards Need An Extra Step

For rewards, there is an extra design constraint that habits do not have:

- high-frequency caps such as `4/day` should tolerate short bursts
- low-frequency caps such as `1/week` should not

If we priced directly from `r_eff`, then high-frequency rewards would become
expensive too quickly during short clusters.

So rewards insert a burst-rescaling step before the main frequency curve.

### 5.3 Burst Scaling

Define:

- `b_r = max(1, √f_r)`
- `r_burst = r_eff / b_r`

Properties:

- `b_r ∈ [1, 10]`
- `f_r ≤ 1 ⟹   b_r = 1`
- `f_r > 1 ⟹   b_r = √f_r`
- `f_r` increasing `⟹   b_r` increasing

Interpretation:

- rewards capped at `≤ 1/day` get no burst slack
- rewards capped above `1/day` get increasing burst slack

So `r_burst` is the quantity that says how close recent reward buying is to the
cap *after* accounting for tolerated short bursts.

### 5.4 Reward Frequency Multiplier

#### Goal

We want a multiplier that:

- equals `1` at zero recent usage
- rises slowly at first
- becomes very steep near the cap
- is bounded above in the implementation

With `β = 2.5`, define:

- if `r_burst ≥ 1`, then `F_r = 20`
- if `0 ≤ r_burst < 1`, then
  `F_r = min(20, 2 / (1 - r_burst^β) - 1)`

Properties on `0 ≤ r_burst < 1`:

- `F_r(0) = 1`
- `F_r` is strictly increasing
- `r_burst → 1⁻ ⟹   F_r → +∞`

Then the implementation clamps that divergence:

- `r_burst ≥ 1 ⟹   F_r = 20`

So:

- low recent reward usage gives near-base price
- approaching the configured cadence makes price rise sharply
- reaching or exceeding the cap hits the ceiling multiplier

## 6. Multi-Quantity Semantics

### 6.1 Goal

Buying or claiming `q` units should mean "perform the pricing rule `q` times in
sequence", not "price one unit once and multiply by `q`".

Otherwise the UI would understate the cost of repeated reward buys and overstate
the reward of repeated habit claims.

### 6.2 Habit Claims

For claiming `q ≥ 0` times from current history `H`, let `Hₖ` be the history
after appending the first `k` projected claims one by one.

Then:

`TotalHabitReward(q) = Σₖ₌₁^q Reward(Hₖ)`

In general:

`TotalHabitReward(q) ≠ q · Reward(H)`

because the frequency multiplier changes after each projected claim.

### 6.3 Reward Buys

For buying `q ≥ 0` times from current history `P`, let `Pₖ` be the history
after appending the first `k` projected buys one by one.

Then:

`TotalRewardCost(q) = Σₖ₌₁^q Cost(Pₖ)`

In general:

`TotalRewardCost(q) ≠ q · Cost(P)`

because the frequency multiplier changes after each projected buy.

## 7. Consequences

The formulas imply:

- harder habits always pay more than easier habits, all else equal
- more damaging rewards always cost more than less damaging rewards, all else equal
- changing `G` changes reward costs but not habit rewards
- old actions never drop out at a hard cutoff; their weight decays exponentially to `0`
- `1/day` and `30/month` behave identically because both induce `f = 1` and `τ = 1`
- for habits, `r_eff → ∞ ⟹ F_h → 0`
- for rewards, `r_burst → 1⁻ ⟹ F_r → +∞` before clamping, and the implemented value is then `20`

## 8. Current iOS Semantics

- habit `frequency` is stored as times/day
- reward `maxFrequency` is stored as times/day
- allowed frequency range is `1/month ... 100/day`
- habit difficulty is stored as `difficultyTier`
- reward damage is stored as `damageTier`
- both pricing paths use the same timestamp-based cadence decay
- there is no relative ranking and no random multiplier
