# Pricing

## Purpose

This document states the current iOS pricing equations used in `./ios`.

There are two related calculations:

- habit completion reward: how much tofu the user earns
- reward purchase cost: how much tofu the user spends

Both share the same outer form:

\[
\mathrm{value} = \operatorname{round}(100 \cdot G \cdot D \cdot F \cdot R)
\]

where:

- \(G\) is the user-configurable general difficulty
- \(D\) is the rank-based multiplier
- \(F\) is the frequency multiplier
- \(R\) is a deterministic pseudo-random multiplier

## Design Goals

- The displayed reward price should react quickly enough to match the cap the user entered.
- The buy modal should use the same rising-price logic as repeated single purchases.
- Multi-buy totals should reflect each incremental purchase, not `currentPrice * quantity`.
- The same pricing rule should be reused everywhere the iOS app shows or spends a reward price.

## 1. Habit Completion Reward

Implemented in `ios/tofustash/Habits/Utilities/RewardCalculation.swift`.

\[
\mathrm{Reward} = \operatorname{round}(100 \cdot G \cdot D_h \cdot F_h \cdot R_h)
\]

### Difficulty Multiplier

Let:

- \(N_h\) = number of ranked, non-deleted habits
- \(\operatorname{rank}(h)\in\{1,\dots,N_h\}\) = lexicographic position of `difficultyRank`

Then:

\[
D_h = \frac{N_h - \operatorname{rank}(h) + 1}{N_h + 1}
\]

If the habit is unranked, or no ranked habits exist, the fallback is:

\[
D_h = 0.5
\]

### Frequency Multiplier

Let:

- \(f_h\) = target frequency in times/day
- \(c_h\) = completions in the last 7 days
- \(\alpha = 2.5\)

Then expected completions are:

\[
E_h = 7 f_h
\]

and the completion ratio is:

\[
r_h = \frac{c_h}{E_h}
\]

The current iOS implementation does not use age blending for habits, so:

\[
r_h^{\mathrm{eff}} = r_h
\]

and:

\[
F_h = \frac{2}{1 + \left(r_h^{\mathrm{eff}}\right)^\alpha}
\]

If no frequency is set, the fallback is:

\[
F_h = 1
\]

Behaviourally:

- \(r_h = 0 \Rightarrow F_h = 2\)
- \(r_h = 1 \Rightarrow F_h = 1\)
- \(r_h > 1 \Rightarrow F_h < 1\)

### Random Multiplier

For time bucket \(t_h\):

\[
R_h = 0.993 + 0.014 \cdot H(\text{habitId}, t_h)
\]

where \(H\in[0,1)\) is the deterministic hash output.

The habit bucket changes every 20 seconds.

## 2. Reward Purchase Cost

Implemented in `ios/tofustash/Rewards/Utilities/RewardPriceCalculation.swift`.

\[
\mathrm{Cost} = \operatorname{round}(100 \cdot G \cdot D_r \cdot F_r \cdot R_r)
\]

### Damage Multiplier

Let:

- \(N_r\) = number of ranked, non-deleted rewards
- \(\operatorname{rank}(r)\in\{1,\dots,N_r\}\) = lexicographic position of `damageRank`

Then:

\[
D_r = \frac{N_r - \operatorname{rank}(r) + 1}{N_r + 1}
\]

If the reward is unranked, or no ranked rewards exist, the fallback is:

\[
D_r = 0.5
\]

### Frequency Multiplier

Let:

- \(f_r\) = max healthy purchase rate in times/day
- \(c_r\) = purchases in the last 1 day
- \(\beta = 3\)

Then expected purchases are:

\[
E_r = f_r
\]

and the purchase ratio is:

\[
r_r = \frac{c_r}{E_r}
\]

The multiplier is:

\[
F_r =
\begin{cases}
50, & r_r \ge 1 \\
\min\left(50,\; \frac{2}{1-r_r^\beta} - 1\right), & r_r < 1
\end{cases}
\]

If no max frequency is set, the fallback is:

\[
F_r = 1
\]

Some useful values:

- \(r_r = 0 \Rightarrow F_r = 1\)
- \(r_r = \frac{1}{3} \Rightarrow F_r \approx 1.077\)
- \(r_r = \frac{2}{3} \Rightarrow F_r \approx 1.842\)
- \(r_r \to 1^{-} \Rightarrow F_r \to +\infty\), but the implementation clamps to \(50\)

### Reward Pricing Behaviour

Reward pricing uses a rolling 24-hour purchase window.

This is deliberate.

If the user sets a reward to `3/day`, they expect:

1. the first purchase today to use the base price
2. the second purchase today to cost more
3. the third purchase today to cost even more
4. later purchases today to become very expensive

Using a long window like 60 days makes early same-day purchases look flat because the ratio barely moves. A 24-hour window keeps the app aligned with the way the cap is expressed in the UI.

### Random Multiplier

For time bucket \(t_r\):

\[
R_r = 0.993 + 0.014 \cdot H(\text{rewardId}, t_r)
\]

where \(H\in[0,1)\) is the deterministic hash output.

The reward bucket changes every 30 minutes.

## 3. Multi-Quantity Behaviour

### Habit Claim Modal

For claiming \(q\) times from a habit with current completion count \(c_h\):

\[
\mathrm{TotalHabitReward}(q) = \sum_{i=0}^{q-1}
\mathrm{Reward}(c_h + i)
\]

So the total is generally not:

\[
q \cdot \mathrm{Reward}(c_h)
\]

because \(F_h\) changes after each increment.

### Reward Buy Modal

For buying \(q\) times from a reward with current purchase count \(c_r\):

\[
\mathrm{TotalRewardCost}(q) = \sum_{i=0}^{q-1}
\mathrm{Cost}(c_r + i)
\]

So the total is generally not:

\[
q \cdot \mathrm{Cost}(c_r)
\]

because \(F_r\) changes after each increment.

The total intentionally matches what would happen if the user tapped Buy repeatedly inside the same pricing bucket.

## 4. Where This Rule Is Used

The iOS app uses the same reward pricing window and calculation path in:

- `RewardsView` for the list price
- `RewardFormView` for the edit-sheet price preview
- `RewardPurchaseModalView` for the multi-buy total
- `RewardPurchaseService` for the actual trade records and balance deduction

This keeps the visible price, the modal total, and the persisted trades in sync.

## 5. Notes On Current Semantics

- Habit `frequency` is stored on iOS as times/day.
- Reward `maxFrequency` is stored on iOS as times/day.
- Habit frequency response is measured over a rolling 7-day window.
- Reward price response is measured over a rolling 24-hour window.
- Rank ordering is lexicographic on the stored rank string.
- Deleted entities are excluded from rank calculations.
- The random multiplier is deterministic within a bucket, so repeated renders inside one bucket are stable.
