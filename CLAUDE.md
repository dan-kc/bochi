## Workflow

When making changes, follow these steps in order. Skip steps that don't apply.

1. Write/run migrations
2. Check backend tests pass (migrations must be compatible with old backend)
3. Write/change backend code and tests
4. Check backend tests pass
5. Refactor backend, keeping the codebase DRY
6. Check backend tests pass
7. Write/change frontend code and tests
8. Check frontend tests pass
9. Refactor frontend, keeping the codebase DRY
10. Check frontend tests pass

**IMPORTANT:** Most of the dev dependencies are in the dev shell. This means that most commands are only available in the cwd. All dev commands are listed in scripts.nix.

Do not run `start`, assume the dev environment is already running.
