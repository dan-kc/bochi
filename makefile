## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

## start: builds db and server, then starts db, then starts server in the background
.PHONY: start
start:
	docker compose build db server
	docker compose up -d --remove-orphans db
	sleep 3 # Wait for db to be accepting connections
	docker compose up -d --remove-orphans server

## stop: stops and removes all containers
.PHONY: stop
stop:
	docker compose -f docker-compose.yml -f docker-compose.test.yml down

## test: starts a temporary db, then applies migrations, then runs server, then playwright
.PHONY: test
test: stop
	docker volume rm habit_market_backend_test_data || true
	docker compose -f docker-compose.yml -f docker-compose.test.yml build
	docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --remove-orphans db
	sleep 3 # Wait for db to be accepting connections
	docker compose -f docker-compose.yml -f docker-compose.test.yml run migration migrate
	docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --remove-orphans server
	docker compose -f docker-compose.yml -f docker-compose.test.yml run test_suite

## logs: view logs output of all containers
.PHONY: logs
logs:
	docker compose logs -f

## migrate-status: shows the current state of the db against the migrations folder
migrate-status:
	docker compose build db migration
	docker compose up -d --remove-orphans db
	docker compose run migration info

## migrate: applys migrations to the db
migrate:
	docker compose build db migration
	docker compose up -d --remove-orphans db
	docker compose run migration migrate

## show-users: displays entries in the users table
show-users:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM users;"

show-users-schema:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ users"

## show-users: displays entries in the tasks table
show-tasks:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM tasks;"

show-tasks-schema:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ tasks"

## show-users: displays entries in the refresh_tokens table
show-refresh-tokens:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM refresh_tokens;"

show-refresh-tokens-schema:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ refresh_tokens"

## show-users: displays entries in the api_keys table
show-api-keys:
	docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM api_keys;"

show-api-keys-schema:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ api_keys"

## show-users: displays entire database schema
tables:
	docker compose exec db psql -U user -d habit_market -P pager=off -c "\dt"
