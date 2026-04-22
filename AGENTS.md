## App
- iOS Swift app lives in `./ios`.
- Habit tracker: complete habits to earn currency; spend currency on rewards.
- Run repo commands through the Nix devshell so env from `flake.nix` and `scripts.nix` is loaded.
- Prefer `nix develop -c <cmd>` for script helpers like `t`, `start`, `stop`, `status`, `seed`, and `run`.
- `./frontend` is legacy; ignore it.

## iOS
- Use default SwiftUI styling, including default icons.
- Write comments for an expert React engineer who does not know Swift.
- Comment user behaviors, not obvious syntax.
- Keep code DRY where reasonable.
- Write iOS tests only when they cover user behavior; keep them BDD-style and add a behavior comment to each test.
- Do not run iOS tests; the user will.

## Backend
- Do tests first with `t`, then write/apply migrations, then backend code, then ensure tests pass.

## Order
- For backend work: finish backend flow first, then move to `./ios`.
- For iOS work: write tests first if any are appropriate, then write code.
