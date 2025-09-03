ARGS ?=

.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

flyway:
	@echo "Running Flyway with config: migrations/flyway.toml $(ARGS)"
	flyway -configFiles=migrations/flyway.toml $(ARGS)

# start: start environment
.PHONY: start
start:
	docker compose up -d --remove-orphans 

## stop: stop all containers
.PHONY: stop
stop:
	docker compose -f docker-compose.yml -f docker-compose-server.yml down

## logs: view logs output of all containers
.PHONY: logs
logs:
	docker compose logs -f

## build-image: builds server docker image
.PHONY: build-image
build-image:
	nix build .#server-docker
	docker load < result
	rm result

## show-users: displays entries in the users table
show-users:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM users;"

## show-api-keys: displays entries in the api_keys table
show-api-keys:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM api_keys;"

## show-refresh-tokens: displays entries in the refresh_tokens table
show-refresh-tokens:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM refresh_tokens;"

## show-tasks: displays entries in the tasks table
show-tasks:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM tasks;"

## show-habits: displays entries in the habits table
show-habits:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM habits;"

## show-schema: displays entire database schema
show-schema:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\dt"

## show-schema-users: displays all entries in the users table
show-schema-users:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ users"

## show-schema-api-keys: displays all entries in the api_keys table
show-schema-api-keys:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ api_keys"

## show-schema-refresh-tokens: displays all entries in the refresh_tokens table
show-schema-refresh-tokens:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ refresh_tokens"

## show-schema-tasks: displays all entries in the tasks table
show-schema-tasks:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ tasks"

## show-schema-habits: displays all entries in the habits table
show-schema-habits:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ habits"

## refresh: drops and recreates databases, then applies migrations
.PHONY: refresh
refresh:
	@echo "Killing any running habit-market-backend processes..."
	-pkill -f habit-market-backend
	@echo "Dropping existing databases..."
	docker compose exec -T db psql -U user -d postgres -c "DROP DATABASE IF EXISTS habit_market;"
	docker compose exec -T db psql -U user -d postgres -c "DROP DATABASE IF EXISTS test_habit_market;"
	@echo "Creating databases..."
	docker compose exec -T db psql -U user -d postgres -c "CREATE DATABASE habit_market;"
	docker compose exec -T db psql -U user -d postgres -c "CREATE DATABASE test_habit_market;"
	@echo "Applying migrations to habit_market..."
	DATABASE_NAME=habit_market flyway -configFiles=./flyway.toml -locations=filesystem:./migrations migrate
	@echo "Applying migrations to test_habit_market..."
	DATABASE_NAME=test_habit_market flyway -configFiles=./flyway.toml -locations=filesystem:./migrations migrate
	@echo "Database refresh complete!"
