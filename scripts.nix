{ pkgs, env }:
let
  scripts = rec {
    # Whipes all tables in the provided database.
    clean = pkgs.writeShellScriptBin "clean" ''
      set -e 
      if [ -z "$1" ]; then
        echo "Usage: clean ${env.DB_NAME}"
        echo "OR:    clean ${env.DB_NAME_TEST}"
        exit 1
      fi
      DB_NAME="$1"
      echo "Truncating all tables in ''${DB_NAME} database..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d "''${DB_NAME}" -c "TRUNCATE refresh_tokens, rewards, tags, task_dependencies, task_tags, tasks, trades, users CASCADE;"
      echo "Database cleaned!"
    '';

    # Truncates all tables and loads fixture data into tofustash database
    seed = pkgs.writeShellScriptBin "seed" ''
      set -e
      echo "Truncating all tables in tofustash database..."
      ${clean}/bin/clean ${env.DB_NAME} || true
      echo "Loading fixture data..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -f ./dev-seed.sql
      echo "Fixtures loaded successfully!"
    '';

    start-lsp = pkgs.writeShellScriptBin "start-lsp" ''
      LSPMUX_DIR="/tmp/ra-${env.LSPMUX_PORT}"
      CONFIG_DIR="$LSPMUX_DIR/lspmux"  
      CONFIG_FILE="$CONFIG_DIR/config.toml"
      LOG_FILE=${env.LSPMUX_LOG_FILE}

      mkdir -p "$(dirname "$LOG_FILE")"
      mkdir -p "$CONFIG_DIR"
      cat > "$CONFIG_FILE" <<EOF
      ${env.LSPMUX_CONFIG}
      EOF

      XDG_CONFIG_HOME=$LSPMUX_DIR lspmux server &> "$LOG_FILE" & disown
      echo "Listening"
    '';

    # Start development environment
    start-dev = pkgs.writeShellScriptBin "start-dev" ''
      set -e
      echo "Stopping any existing services..."
      ${stop-dev}/bin/stop || true
      sleep 1
      echo "Starting services..."
      echo "Starting PostgreSQL..."
      ${start-postgres}/bin/start-postgres
      echo "Starting Adminer..."
      (nohup adminer &> /dev/null &) && \
      echo "All services started successfully!"
    '';

    # Stop development environment
    stop-dev = pkgs.writeShellScriptBin "stop-dev" ''
      echo "Stopping PostgreSQL..."
      PGDATA=${env.PGDATA}
      pg_ctl -D "$PGDATA" stop 2>/dev/null && echo "✓ PostgreSQL stopped" || echo "✗ PostgreSQL not running"

      echo "Stopping Adminer..."
      pkill -f "php -S localhost:${toString env.ADMINER_PORT}" && echo "✓ Adminer stopped" || echo "✗ Adminer not running"

      echo "All services stopped."
    '';

    adminer = pkgs.writeShellScriptBin "adminer" ''
      ${pkgs.php83}/bin/php -S localhost:${toString env.ADMINER_PORT} ${pkgs.adminer}/adminer.php
    '';

    # Start PostgreSQL
    start-postgres = pkgs.writeShellScriptBin "start-postgres" ''
      set -e
      PGDATA=${env.PGDATA}
      if [ ! -d "$PGDATA" ]; then
        echo "Initializing PostgreSQL database..."
        initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
      fi
      echo "Starting PostgreSQL..."
      pg_ctl -D "$PGDATA" -l /tmp/postgres.log -o "-k /tmp" start
      sleep 2
      # Create user and databases if they don't exist
      export PGHOST=${env.DB_HOST}
      createuser -U $USER ${env.DB_USER} 2>/dev/null || echo "  ✓ User '${env.DB_USER}' already exists"
      psql -U $USER -d postgres -c "ALTER USER \"${env.DB_USER}\" WITH PASSWORD '${env.DB_PASSWORD}';" 2>/dev/null || true
      createdb -U $USER -O ${env.DB_USER} ${env.DB_NAME} 2>/dev/null || echo "  ✓ Database '${env.DB_NAME}' already exists"
      createdb -U $USER -O ${env.DB_USER} ${env.DB_NAME_TEST} 2>/dev/null || echo "  ✓ Database '${env.DB_NAME_TEST}' already exists"
      echo "PostgreSQL started successfully"
    '';

    # Wraps `cargo run` with env vars
    run = pkgs.writeShellScriptBin "run" ''
      set -e
      cd backend
      PORT="${env.SERVER_PORT}" \
      DB_USER="${env.DB_USER}" \
      DB_PASSWORD="${env.DB_PASSWORD}" \
      DB_HOST="${env.DB_HOST}" \
      DB_NAME="${env.DB_NAME}" \
      SSL_MODE="disable" \
      JWT_PRIVATE_KEY="${env.JWT_PRIVATE_KEY}" \
      JWT_PUBLIC_KEY="${env.JWT_PUBLIC_KEY}" \
      LOG_DESTINATION=logs \
      cargo run "$@"
    '';

    # Start frontend dev server
    run-frontend = pkgs.writeShellScriptBin "run-frontend" ''
      set -e
      cd frontend
      npm run start "$@"
    '';

    # Sets up and tears down the test environment. Wraps `cargo test`.
    t = pkgs.writeShellScriptBin "t" ''
      set -e
      ${clean}/bin/clean ${env.DB_NAME_TEST}
      cd backend
      PORT="${env.SERVER_PORT}" \
      DB_USER="${env.DB_USER}" \
      DB_PASSWORD="${env.DB_PASSWORD}" \
      DB_HOST="${env.DB_HOST}" \
      DB_NAME="${env.DB_NAME_TEST}" \
      SSL_MODE="disable" \
      JWT_PRIVATE_KEY="${env.JWT_PRIVATE_KEY}" \
      JWT_PUBLIC_KEY="${env.JWT_PUBLIC_KEY}" \
      cargo test "$@"
    '';

    # Kills all tofustash processes
    kp = pkgs.writeShellScriptBin "kp" ''
      	pkill -f tofustash
    '';

    # Displays the schema of a database table in tofustash
    schema = pkgs.writeShellScriptBin "schema" ''
      set -e
      if [ -z "$1" ]; then
        echo "Usage: schema <table name>"
        exit 1
      fi
      TABLE_NAME="$1"
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -P pager=off -c "\d+ ''${TABLE_NAME}"
    '';

    # Flyway wrapper with config
    fw = pkgs.writeShellScriptBin "fw" ''
      set -e
      # Use the first argument as DATABASE_NAME if provided, otherwise default to tofustash
      # Shift removes the first argument so "$@" correctly passes remaining arguments
      if [ -n "$1" ]; then
        DATABASE_NAME="$1"
        shift
      else
        DATABASE_NAME="${env.DB_NAME}" # Default database name
      fi

      echo "Using database: ''${DATABASE_NAME}"
      ${pkgs.flyway}/bin/flyway \
        -url="jdbc:postgresql://${env.DB_HOST}:5432/''${DATABASE_NAME}" \
        -user="${env.DB_USER}" \
        -password="${env.DB_PASSWORD}" \
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
      echo "Killing any running tofustash processes..."
      ${kp}/bin/kp || true
      echo "Dropping existing database..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d postgres -c "DROP DATABASE IF EXISTS ''${DB_NAME};"
      echo "Creating database..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d postgres -c "CREATE DATABASE ''${DB_NAME};"
      echo "Applying migrations to ''${DB_NAME}..."
      ${fw}/bin/fw ''${DB_NAME} migrate
      echo "Database refresh complete!"
    '';
  };
in
builtins.attrValues scripts
