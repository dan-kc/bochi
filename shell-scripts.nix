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
      	docker compose up -d --remove-orphans 
    '';

    # Stop development environment
    stop = pkgs.writeShellScriptBin "stop" ''
      	docker compose -f docker-compose.yml -f docker-compose-server.yml down
    '';

    # Sets up and tears down the test environment. Wraps `cargo test`.
    t = pkgs.writeShellScriptBin "t" ''
      set -e 
      ${clean}/bin/clean test_habit_market
      AWS_SECRETS_PREFIX="test-" DATABASE_NAME="test_habit_market" cargo test "$@"
    '';

    # Kills all habit_market processes
    kp = pkgs.writeShellScriptBin "kp" ''
      	-pkill -f habit-market-backend
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
