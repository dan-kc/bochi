# Pricing Code Guide

This is a code-reading guide for the current points pricing model.

## Read First

- `ios/bochi/Tasks/Utilities/TaskPriceCalculator.swift`
- `ios/bochi/RecurringTasks/Utilities/RecurringTaskPriceCalculator.swift`
- `ios/bochi/Rewards/Utilities/RewardPriceCalculator.swift`
- `ios/bochi/Shared/Models/PricingTiers.swift`
- `ios/bochi/Shared/Utilities/PriceAdjustmentSupport.swift`
- `ios/bochi/Trades/TradeStore.swift`
- `ios/bochi/Rewards/Utilities/RewardPurchaseService.swift`

Tests:

- `ios/bochiTests/TaskPriceCalculatorTests.swift`
- `ios/bochiTests/RecurringTaskPriceCalculatorTests.swift`
- `ios/bochiTests/RewardPriceCalculatorTests.swift`
- `ios/bochiTests/BasePricePricingTests.swift`
- `ios/bochiTests/SyncManagerTests.swift`
- `ios/bochiTests/BackendIntegerContractTests.swift`

## Stored Fields

Tasks, recurringTasks, and rewards store `base_price`.

Removed from persisted entity pricing:

- difficulty
- duration
- importance
- damage
- general difficulty
- permanent adjustment multipliers
- special offers

Helper UI can still suggest a `base_price`, but those helper inputs are not
stored on the entity.

## Runtime Rules

- Task completion: `basePrice`, plus any premium one-time adjustment.
- Recurring task completion: `basePrice * recurring task cadence multiplier`.
- One-off reward purchase: `basePrice`, plus any premium one-time adjustment.
- Recurring reward purchase: `basePrice * reward cadence multiplier`.

One-time adjustments are action snapshots on `Trade`, not entity fields.

## Cadence Model

`CadenceDecayPricing` is shared by recurring task rewards and recurring reward
costs.

Key ideas to check in code:

- frequency is normalized to a daily rate
- old completions/purchases decay over time
- equivalent rates such as `1/day` and `30/month` behave the same
- new items warm up before sparse history is trusted too much

Recurring tasks and rewards use the shared cadence signal differently:

- recurring tasks pay less when overdone and more when underdone
- recurring rewards cost more when bought too often

## Multi-Quantity

Multi-claim and multi-purchase totals are sequential simulations.

The app does not price one unit and multiply by quantity. It prices each
projected action after appending the previous projected action to history.

Read:

- `RecurringTaskPriceCalculator.calculateMultiClaimTotal(...)`
- `RewardPriceCalculator.calculateMultiPurchaseTotal(...)`

## Sync Contract

`base_price` and trade snapshots sync. Helper UI inputs do not.

The backend accepts signed 32-bit integer ranges for synced numeric fields.
Local SQLite checks mirror that contract through `BackendIntegerContract`.

When changing pricing fields, check both:

- iOS model/store/schema encoding
- backend sync validation in `backend/src/api/sync.rs`
