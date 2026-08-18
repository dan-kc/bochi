## App

- iOS Swift app lives in `./ios`.
- RecurringTask tracker: complete recurringTasks to earn currency; spend currency on rewards.
- Run repo commands through the Nix devshell so project specific scripts from `flake.nix` are loaded.
- Use the `bochi-dev-commands` skill before running dev, test, build, database, iOS, or infrastructure commands.
- Prefer `nix develop -c <cmd>` for custom script helpers listed in `.agents/skills/bochi-dev-commands/SKILL.md`. Other commands will likely not need this.
- Use `schema` commands to inspect the database schema.
- Do not worry about backwards compatibility as everyone will be on the latest version and I will nuke all rows in the db before launch.


## iOS

- Use default SwiftUI styling, including default icons.
- Write comments for an expert React engineer who does not know Swift.
- Comment user behaviors, not obvious syntax.
- Keep code DRY where reasonable.
- Strongly prefer centralized SwiftUI lifecycle/effect modifiers for side effects keyed by state changes over scattered manual calls. Stores should mutate durable state or publish lightweight revisions; root/lifecycle hooks should reconcile outside-world effects such as sync sessions and notifications. Put custom lifecycle modifiers in `ios/bochi/Lifecycles`, one lifecycle per file.
- Write iOS unit tests only when they cover user behavior; keep them BDD-style and add a behavior comment to each test.
- Run unit tests with `ios-test`.

## Backend

- Do tests first with `t`, then write/apply migrations, then backend code, then ensure tests pass.

## Workflow

Do not edit existing migration files. Conduct code changes in this order, skip steps that not required:

- Write failing backend tests
- Write code and write/apply migrations such that tests pass
- Write ios unit tests
- Write code such that unit tests pass.
- Maintain an exceptionally high standard of code. Refactor when appropriate, no matter how big the refactor, if the result will be better code. Prefer functional code where appropriate, but do not go crazy with monads etc and do not fight the language / framework to do so. Strongly prefer idiomatic code always.
- Add comments if and only if you deem it appropriate. I only want explainations of things not obvious from the code.
