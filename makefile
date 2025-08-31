## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

## start: builds db, localstack and server, then starts all services
.PHONY: start
start:
	docker compose up -d --remove-orphans db localstack server

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

## migrate: applys migrations to the db
migrate:
	docker compose build db migration
	docker compose up -d --remove-orphans db
	docker compose run migration migrate

## migrate-status: shows the current state of the db against the migrations folder
migrate-status:
	docker compose build db migration
	docker compose up -d --remove-orphans db
	docker compose run migration info

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

## create-secret: creates a secret in localstack (usage: make create-secret NAME=secret-name VALUE=secret-value)
.PHONY: create-secret
create-secret:
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager create-secret --name $(NAME) --secret-string '$(VALUE)' --region us-east-1

## get-secret: retrieves a secret from localstack (usage: make get-secret NAME=secret-name)
.PHONY: get-secret
get-secret:
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id $(NAME) --region us-east-1

## list-secrets: lists all secrets in localstack
.PHONY: list-secrets
list-secrets:
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets --region us-east-1

## setup-local-secrets: creates example secrets in localstack for development
.PHONY: setup-local-secrets
setup-local-secrets:
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager create-secret --name app/database --secret-string '{"host":"db","port":"5432","database":"habit_market","username":"user","password":"password"}' --region us-east-1 || true
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager create-secret --name app/jwt --secret-string '{"private_key":"secret-jwt-key","public_key":"public-jwt-key"}' --region us-east-1 || true
	docker compose exec localstack aws --endpoint-url=http://localhost:4566 secretsmanager create-secret --name app/api-keys --secret-string '{"service1":"api-key-1","service2":"api-key-2"}' --region us-east-1 || true
