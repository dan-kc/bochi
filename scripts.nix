{ pkgs }:
let
  scripts = rec {
    # Whipes all tables in the provided database.
    clean = pkgs.writeShellScriptBin "clean" ''
      set -e 
      if [ -z "$1" ]; then
        echo "Usage: clean <database_name>"
        exit 1
      fi
      DB_NAME="$1"
      echo "Truncating all tables in ''${DB_NAME} database..."
      docker compose exec -T db psql -U user -d "''${DB_NAME}" -c "TRUNCATE refresh_tokens, tags, task_dependencies, task_tags, tasks, trades, users CASCADE;"
      echo "Database cleaned!"
    '';

    # Start development environment
    start = pkgs.writeShellScriptBin "start" ''
      docker compose up -d --remove-orphans && \
      (nohup adminer &> /dev/null &) && \
      ${start-loki}/bin/start-loki && \
      sleep 2 && \
      ${start-promtail}/bin/start-promtail && \
      ${start-grafana}/bin/start-grafana
    '';

    adminer = pkgs.writeShellScriptBin "adminer" ''
      ${pkgs.php83}/bin/php -S localhost:8081 ${pkgs.adminer}/adminer.php
    '';

    # Start loki
    start-loki = pkgs.writeShellScriptBin "start-loki" ''
      set -e
      LOKI_DATA_DIR="/tmp/loki-data"
      mkdir -p "$LOKI_DATA_DIR/chunks"
      mkdir -p "$LOKI_DATA_DIR/rules"
      mkdir -p "$LOKI_DATA_DIR/compactor"
      echo "Starting Loki..."
      nohup ${pkgs.grafana-loki}/bin/loki -config.file=./observability/local/loki-config.yaml &> /tmp/loki.log & disown
      echo "Loki started"
    '';

    # Start promtail
    start-promtail = pkgs.writeShellScriptBin "start-promtail" ''
      set -e
      mkdir -p ./logs
      echo "Starting Promtail..."
      CURRENT_DIR=$(pwd)
      APP_LOG_PATH="$CURRENT_DIR/logs/server.log*"
      nohup ${pkgs.grafana-loki}/bin/promtail -config.file=./observability/local/promtail-config.yaml &> /tmp/promtail.log & disown
      echo "Promtail started"
    '';

    # Start grafana
    start-grafana = pkgs.writeShellScriptBin "start-grafana" ''
      set -e
      GRAFANA_DATA_DIR="/tmp/grafana-storage"
      mkdir -p "$GRAFANA_DATA_DIR"
      echo "Starting Grafana..."
      GF_SECURITY_ADMIN_PASSWORD=admin \
      GF_SECURITY_ADMIN_USER=admin \
      GF_AUTH_ANONYMOUS_ENABLED=true \
      GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
      GF_AUTH_DISABLE_LOGIN_FORM=true \
      GF_AUTH_DISABLE_SIGNOUT_MENU=true \
      GF_PATHS_DATA="$GRAFANA_DATA_DIR" \
      nohup ${pkgs.grafana}/bin/grafana-server --homepath ${pkgs.grafana}/share/grafana &> /tmp/grafana.log & disown
      echo "Grafana started"
    '';

    # Stop development environment
    stop = pkgs.writeShellScriptBin "stop" ''
      	docker compose -f docker-compose.yml -f docker-compose-server.yml down
        pkill -f "php -S localhost:8081" || true
        pkill -f "loki -config.file" || true
        pkill -f "promtail -config.file" || true
        pkill -f "grafana-server" || true
    '';

    # Wraps `cargo run` with env vars for localstack.
    run = pkgs.writeShellScriptBin "run" ''
      AWS_ACCESS_KEY_ID="test" \
      AWS_SECRET_ACCESS_KEY="test" \
      AWS_DEFAULT_REGION="eu-west-1" \
      AWS_ENDPOINT_URL_SECRETSMANAGER="http://localhost:4566" \
      AWS_SECRETS_PREFIX="" \
      DATABASE_NAME="habit_market" \
      LOG_DESTINATION=logs \
      AWS_PROFILE="" \
      AWS_DEFAULT_PROFILE="" \
      cargo run "$@"
    '';

    # Sets up and tears down the test environment. Wraps `cargo test`.
    t = pkgs.writeShellScriptBin "t" ''
      set -e 
      ${clean}/bin/clean test_habit_market
      AWS_ACCESS_KEY_ID="test" \
      AWS_SECRET_ACCESS_KEY="test" \
      AWS_DEFAULT_REGION="eu-west-1" \
      AWS_ENDPOINT_URL_SECRETSMANAGER="http://localhost:4566" \
      AWS_SECRETS_PREFIX="test-" \
      DATABASE_NAME="test_habit_market" \
      AWS_PROFILE="" \
      AWS_DEFAULT_PROFILE="" \
      cargo test "$@"
    '';

    # Kills all habit_market processes
    kp = pkgs.writeShellScriptBin "kp" ''
      	pkill -f habit-market-backend
    '';

    # build: builds server docker image
    build = pkgs.writeShellScriptBin "build" ''
      set -e 
      nix build .#server-docker
      docker load < result
      rm result
    '';

    # Displays the schema of a database table in habit_market
    schema = pkgs.writeShellScriptBin "schema" ''
      set -e 
      if [ -z "$1" ]; then
        echo "Usage: schema <table name>"
        exit 1
      fi
      TABLE_NAME="$1"
      docker compose exec db psql -U user -d habit_market -P pager=off -c "\d+ ''${TABLE_NAME}"
    '';

    # Flyway wrapper with config
    fw = pkgs.writeShellScriptBin "fw" ''
      set -e 
      # Use the first argument as DATABASE_NAME if provided, otherwise default to habit_market
      # Shift removes the first argument so "$@" correctly passes remaining arguments
      if [ -n "$1" ]; then
        DATABASE_NAME="$1"
        shift
      else
        DATABASE_NAME="habit_market" # Default database name
      fi

      echo "Using database: ''${DATABASE_NAME}"
      ${pkgs.flyway}/bin/flyway \
        -url="jdbc:postgresql://localhost:5432/''${DATABASE_NAME}" \
        -user="user" \
        -password="password" \
        -locations="filesystem:./migrations" \
        -validateOnMigrate=true \
        -baselineOnMigrate=true \
        "$@"
    '';

    tf = pkgs.writeShellScriptBin "tf" ''
      tofu -chdir=./infra "$@"
    '';

    # drops and recreates the provided database, then applies migrations.
    nuke = pkgs.writeShellScriptBin "nuke" ''
      set -e 
      if [ -z "$1" ]; then
        echo "Usage: nuke <database_name>"
        exit 1
      fi
      DB_NAME="$1"
      echo "Killing any running habit-market-backend processes..."
      ${kp}/bin/kp
      echo "Dropping existing database..."
      docker compose exec -T db psql -U user -d postgres -c "DROP DATABASE IF EXISTS ''${DB_NAME};"
      echo "Creating database..."
      docker compose exec -T db psql -U user -d postgres -c "CREATE DATABASE ''${DB_NAME};"
      echo "Applying migrations to ''${DB_NAME}..."
      ${fw}/bin/flyway ''${DB_NAME}
      echo "Database refresh complete!"
    '';
  };
in
builtins.attrValues scripts
