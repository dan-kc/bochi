## App
- iOS Swift app lives in `./ios`.
- Habit tracker: complete habits to earn currency; spend currency on rewards.
- Examples: habit = `10 pushups`, `Cold message a friend`; reward = `Eat 1 chocolate bar`, `Spend 15 minutes on TikTok`.

## iOS
- Use default SwiftUI styling, including default icons.
- Write comments for an expert React engineer who does not know Swift.
- Comment user behaviors, not obvious syntax.
- Keep code DRY where reasonable.
- Write tests only when appropriate.
- If writing iOS tests, keep them BDD-style and tied to user workflows.
- Omit any test that does not represent user behavior.
- Every test must include a comment stating the behavior it covers.
- Do not run iOS tests; the user will.

## Backend
- Do tests first.
- Ensure they fail and the code compiles with `t`.
- Write/apply migrations.
- Write backend code.
- Ensure tests pass.

## Order
- For backend work: finish backend flow first, then move to `./ios`.
- For iOS work: write tests first if any are appropriate, then write code.
