# Lists all possible commands
default:
  just --list

# Builds db and server, then starts db, then starts server in the background
start:
  docker compose build db server
  docker compose up -d --remove-orphans db
  sleep 3 # Wait for db to be accepting connections
  docker compose up -d --remove-orphans server

# Stops and removes all containers
stop:
  docker compose -f docker-compose.yml -f docker-compose.test.yml down

# Starts a temporary db, then migrate, then server, then playwright
test: stop
  docker volume rm habit_market_backend_test_data || true
  docker compose -f docker-compose.yml -f docker-compose.test.yml build
  docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --remove-orphans db
  sleep 3 # Wait for db to be accepting connections
  docker compose -f docker-compose.yml -f docker-compose.test.yml run migration migrate
  docker compose -f docker-compose.yml -f docker-compose.test.yml up -d --remove-orphans server
  docker compose -f docker-compose.yml -f docker-compose.test.yml run test_suite

# View output of all containers
logs:
  docker compose logs -f

# Teardown all containers and delete all volumes and their contents
nuke:
  docker compose -f docker-compose.yml -f docker-compose.test.yml down
  docker compose -f docker-compose.yml -f docker-compose.test.yml down -v

# Shows the current state of the db against the migrations folder.
migrate-status:
  docker compose build db migration
  docker compose up -d --remove-orphans db
  docker compose run migration info

# Applys migrations to the db.
migrate:
  docker compose build db migration
  docker compose up -d --remove-orphans db
  docker compose run migration migrate

show-users:
  docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM users;"

show-users-schema:
  docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ users"

show-tasks:
  docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM tasks;"

show-tasks-schema:
  docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ tasks"

show-refresh-tokens:
  docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM refresh_tokens;"

show-refresh-tokens-schema:
  docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ refresh_tokens"

show-api-keys:
  docker compose exec -T db psql -U user -d habit_market -P pager=off -c "SELECT * FROM api_keys;"

show-api-keys-schema:
  docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ api_keys"

tables:
  docker compose exec db psql -U user -d habit_market -P pager=off -c "\dt"
