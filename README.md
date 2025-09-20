## Local development:

- Docker compose sets up the local environment. Nix shell. The server is the only thing run locally.
- Useful commands in scripts.nix

## Testing

- All tests must have a different name even if they are in seperate modules due to how the user is created.

## MVP:

### Todo:

- [x] Tasks
- [x] Rewards (No ranking yet)
- [x] Trades

# Infra (Terraform AWS)

- rds
- ECS
- "deployment_strategy.txt"
- flyway migrations in CI
- infra-deploy.yml: Only runs if changes in infra/\*\*
- app-deploy.yml: Only runs if changes in app/\*\*

- REMEMBER, deployments are triggered via CodeDeploy not by terraform. Terraform meerly defines static configuration.
- Use Terraform for: Creating and managing the CodeDeploy infrastructure (applications, deployment groups, associated IAM roles, ALB, ECS service itself, CloudWatch alarms). This ensures your deployment environment is defined in Git and is reproducible.
- Use GitHub Actions (or another CI/CD tool) and AWS CLI for: Triggering individual application deployments through CodeDeploy, specifying the new task definition and choosing which CodeDeploy deployment group (and thus which strategy) to use.

## CI

- [x] Test (conditional if ./src changes)
- Build (conditional if ./src changes) (dep on test)
  - Install nix environment
  - 'nix build' docker container
  - upload to aws containers registry
- Provision (conditional if ./infra changes)
  - Install nix
  - auth with aws
  - tofu plan
  - manuall step
- Migrate (conditional if ./migrations changes) (dep on Build, Provision)
  - Install nix
  - auth with aws
  - touch server to stop prepared statments
  - run migrations
- Deploy
  - Execute desired deployment strategy
  - Touch server to stop prepared statments
