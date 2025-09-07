## Local development:

- No docker (except for localstack)
- No nix build
- Nix for local env and test env only and building final image only
- Shell script as soon as you arrive in the CWD you run the db and localstack if it is not running already.

## Testing

- All tests must have a different name even if they are in seperate modules due to how the user is created.

## MVP:

- The following gql endpoints for CRUD on the following:
- Tasks
- Habits
- Rewards
- Trades
- Graphql playground
- Terraform, nginx, aws, cloudflare
