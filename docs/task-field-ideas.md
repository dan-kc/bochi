# Task Field Ideas

## Purpose

This document suggests additional fields and pricing ideas for introducing one-time tasks or todos into the app.

This is related to, but different from, the existing habit and reward model in [docs/pricing.md](/Users/danielcox/projects/tofustash/docs/pricing.md:1).

The most important distinction is:

- habits are repeating behaviours with a target cadence
- tasks are finite obligations that should usually be done once

That difference matters a lot for pricing.

## Core Product Difference From Habits

A habit is something the user wants to keep doing over time.

A task is something the user wants to get done and remove from the list.

Because of that:

- habit pricing should react to repeating cadence
- task pricing should react to urgency, scope, and friction

If tasks simply replace `frequency` with `dueDate`, the app risks teaching the wrong behaviour:

- a task becomes more valuable if the user waits
- users may learn to procrastinate to farm extra tofu

So your instinct is right to be cautious here.

## Strong Recommendation

Do **not** make task payout increase purely because the due date is closer.

That would be legible, but behaviourally it points in the wrong direction.

Instead, treat due date as one input inside a broader model, and cap how much it can boost payout.

Better principle:

- hard tasks should pay more than easy tasks
- bigger tasks should pay more than small tasks
- urgent tasks can pay slightly more
- delaying a task should never become the dominant strategy

## Minimal Task Model

If you want a minimal first version, I would start with:

- `name`
- `description`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `completedAt`
- `dueDate`
- `difficultyTier`
- tags

That would parallel habits closely enough to fit the current architecture, while still being conceptually distinct.

## Good Non-Pricing Task Fields

These are useful even if they never affect tofu.

### `category`

Examples:

- `admin`
- `health`
- `social`
- `finance`
- `home`

Why users may want this:

- easier filtering
- easier batching
- easier review of neglected areas

This should not affect price directly.

### `project` or `area`

Examples:

- `house move`
- `job search`
- `spring cleanup`
- `friendships`

Why users may want this:

- tasks are often part of a broader outcome
- this supports grouped views and progress tracking later

This should not affect price directly.

### `notes`

Examples:

- address
- checklist details
- context for the call

Why users may want this:

- tasks often need supporting detail more than habits do
- it prevents losing the "next action" context

This should not affect price.

### `scheduleWindow`

Examples:

- today
- this week
- evening
- work hours
- anytime

Why users may want this:

- due date alone is often too coarse
- it helps the user decide when the task fits

This should not affect price directly.

### `locationContext`

Examples:

- home
- computer
- phone
- outside
- errands

Why users may want this:

- this makes task lists more actionable
- users often want to filter by where they are and what tools they have

This should not affect price directly.

### `blockedBy`

Examples:

- waiting for a reply
- need to buy supplies
- need the user’s address

Why users may want this:

- blocked tasks should look different from actionable tasks
- this can prevent guilt around tasks the user cannot currently do

This should usually not affect price, but it may affect when a task is surfaced.

### `subtasks`

Examples:

- draft message
- find contact info
- send follow-up

Why users may want this:

- many tasks are too vague until broken down
- it reduces overwhelm

This can influence price indirectly if you later split large tasks into smaller units, but the parent field itself should not directly affect price.

## Task Fields That Could Reasonably Influence Price

These are the strongest candidates if you want task payout to feel fair.

### `estimatedEffortMinutes`

Examples:

- 5 minutes
- 20 minutes
- 90 minutes

Why it may be worth adding:

- it is one of the clearest drivers of task size
- users already intuitively understand time cost

This is probably the single best extra task pricing field.

Recommended usage:

- keep the multiplier modest
- do not let "4 hour task" completely dominate every other factor

### `activationFriction`

Examples:

- low
- medium
- high

Meaning:

- how hard it is to start the task

Why it may be worth adding:

- many todos are not long, but are emotionally avoided
- "email landlord" and "put document in folder" are not the same even if both take 3 minutes

This is an excellent companion to `estimatedEffortMinutes`.

### `difficultyTier`

Examples:

- trivial
- light
- medium
- hard
- extreme

Why it may still matter even with effort and friction:

- some tasks are complex or stressful in a broader way
- the user may want one clear overall judgment, just like habits

You could reuse the same tier system as habits for consistency.

If you have both `difficultyTier` and `activationFriction`, make sure they mean different things:

- difficulty = overall complexity or unpleasantness
- activation friction = how hard it is to begin

### `urgencyWindow`

Examples:

- no deadline
- soft deadline
- hard deadline

Why it may be worth adding:

- not all due dates carry the same consequence
- "sometime this month" and "must submit before 5pm Friday" should not price the same

This is often better than using raw due date alone.

It lets the user express:

- how serious the deadline is
- whether lateness has real consequences

### `consequenceOfNotDoing`

Examples:

- low
- medium
- high

Meaning:

- how bad it is if the task slips

Examples:

- low: tidy one shelf
- medium: reply to an important message
- high: pay a bill before fees apply

Why it may be worth adding:

- some tasks are strategically important even if they are short
- users often want the app to reward what matters, not just what is annoying

This shifts the philosophy slightly:

- payout is no longer only about effort
- payout also reflects consequence

That can be good, but it should be intentional.

### `taskSize` or `scopeTier`

Examples:

- tiny
- small
- medium
- large
- huge

Meaning:

- how much real-world surface area the task has

Why it may be worth adding:

- some tasks are multi-step and cognitively sprawling even if effort is hard to estimate in minutes
- "sort taxes" is not well-described by just a due date and difficulty

This may overlap with `estimatedEffortMinutes`, so I would usually choose one or the other, not both, unless you have evidence users want both.

## Due Date As A Pricing Input

Due date can still be useful in pricing, but it should be handled carefully.

### What Due Date Is Good For

Due date is good for:

- sorting tasks
- surfacing urgency
- mild payout adjustment
- showing risk of delay

### What Due Date Is Bad For

Due date is bad for:

- acting as the main price driver
- increasing value linearly as the deadline gets closer

Reason:

- that makes procrastination economically rational

## Better Alternatives To "Closer Due Date = More Tofu"

### Option 1: Urgency Bonus Based On Original Deadline Distance

When the task is created, compute how tight the schedule already is:

- same day
- within 3 days
- within a week
- flexible

Then keep that urgency tier mostly stable.

Behaviourally:

- a genuinely urgent task pays more from the start
- waiting does not keep increasing the reward

This is one of the cleanest solutions.

### Option 2: Early Completion Bonus

Instead of rewarding lateness, reward completing before the deadline.

Examples:

- done 3+ days early
- done 1 day early
- done on time
- done late

Behaviourally:

- the user is rewarded for acting sooner
- the app discourages deadline-drifting

This is probably better than a raw urgency multiplier.

### Option 3: Deadline Pressure Only Affects Surfacing, Not Price

Keep payout based on difficulty, effort, and friction.

Use due date only to:

- sort tasks higher
- show warning UI
- suggest "do this next"

This is the safest product choice if you want to avoid gaming.

### Option 4: Small Bounded Urgency Modifier

If you really want due date in the formula, keep it tightly bounded.

Example mental model:

- far away: `1.0x`
- near: `1.1x`
- very near: `1.2x`

Important:

- the modifier should be small
- the difference between a trivial and extreme task should still matter more
- waiting should not multiply payout dramatically

## Suggested Task Pricing Direction

I would not try to force tasks into the habit cadence formula.

Tasks need a different top-level model.

A good conceptual shape would be:

`taskReward = round(100 * T * E * A * U)`

where:

- `T` = difficulty tier
- `E` = effort modifier
- `A` = activation friction modifier
- `U` = small urgency modifier

That preserves the same product feel as habits:

- a small set of understandable multipliers
- deterministic pricing
- easy preview in forms

But it avoids pretending one-time tasks have a repeat cadence.

## The Best Additions If You Want To Stay Simple

If the goal is "tasks should feel fair without becoming a project manager", the strongest shortlist is:

1. `dueDate`
2. `difficultyTier`
3. `estimatedEffortMinutes`
4. `activationFriction`
5. `project` or `area`

Why this set works:

- `dueDate` gives urgency and scheduling
- `difficultyTier` gives a simple overall classification
- `estimatedEffortMinutes` captures objective size
- `activationFriction` captures avoidance
- `project` keeps the task list useful in practice

## Fields I Would Not Use For Pricing

These are valid task properties, but I would keep them out of the reward equation:

- tags
- category
- project
- notes
- reminder time
- location
- blocked status
- color
- icon

Reason:

- users experience these as metadata or workflow aids
- the formula becomes harder to explain if organisational fields change tofu

## Likely User Wants Beyond Pricing

Separate from price, users will probably want:

- inbox capture
- today / upcoming / overdue sections
- snooze
- blocked or waiting states
- subtasks
- project grouping
- quick-complete from the list
- carry-forward of unfinished tasks

These are likely more important for task satisfaction than squeezing every last bit of fidelity out of the formula.

## Recommendation

If you only add one new pricing-related task field, add:

- `estimatedEffortMinutes`

If you add two, add:

- `estimatedEffortMinutes`
- `activationFriction`

If you want the best overall first task model, add:

- `dueDate`
- `difficultyTier`
- `estimatedEffortMinutes`
- `activationFriction`
- `project`

And for pricing specifically:

- do not use due date as a strong live multiplier
- if you use it at all, prefer a small urgency band or an early-completion bonus

That gives you a task system that still feels coherent next to habits, without teaching users to delay important work.
