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

    # Start development environment
    start-dev = pkgs.writeShellScriptBin "start-dev" ''
      set -e
      ROOT="$PWD"

      # Handle --force flag
      if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        echo "Force restarting all services..."
        ${stop-dev}/bin/stop-dev
        echo ""
      fi

      mkdir -p "$ROOT/logs"
      touch "$ROOT/logs/postgres.log" "$ROOT/logs/adminer.log" "$ROOT/logs/frontend.log" "$ROOT/logs/backend.log" "$ROOT/logs/lspmux.log"

      echo "Checking services..."

      # PostgreSQL
      PGDATA="$ROOT/${env.PGDATA}"
      if pg_isready -h ${env.DB_HOST} -q 2>/dev/null; then
        echo "  ✓ PostgreSQL already running"
      else
        echo "  → Starting PostgreSQL..."
        if [ ! -d "$PGDATA" ]; then
          echo "    Initializing PostgreSQL database..."
          initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
        fi
        pg_ctl -D "$PGDATA" -l "$ROOT/logs/postgres.log" -o "-k /tmp" start
        sleep 2
        # Create user and databases if they don't exist
        export PGHOST=${env.DB_HOST}
        createuser -U $USER ${env.DB_USER} 2>/dev/null || true
        psql -U $USER -d postgres -c "ALTER USER \"${env.DB_USER}\" WITH PASSWORD '${env.DB_PASSWORD}';" 2>/dev/null || true
        createdb -U $USER -O ${env.DB_USER} ${env.DB_NAME} 2>/dev/null || true
        createdb -U $USER -O ${env.DB_USER} ${env.DB_NAME_TEST} 2>/dev/null || true
        echo "  ✓ PostgreSQL started"
      fi

      # Backend
      if [ -f "$ROOT/.backend.pid" ] && kill -0 $(cat "$ROOT/.backend.pid") 2>/dev/null; then
        echo "  ✓ Backend already running"
      else
        echo "  → Starting Backend..."
        cd "$ROOT/backend"
        PORT="${env.SERVER_PORT}" \
        DB_USER="${env.DB_USER}" \
        DB_PASSWORD="${env.DB_PASSWORD}" \
        DB_HOST="${env.DB_HOST}" \
        DB_NAME="${env.DB_NAME}" \
        SSL_MODE="disable" \
        JWT_PRIVATE_KEY="${env.JWT_PRIVATE_KEY}" \
        JWT_PUBLIC_KEY="${env.JWT_PUBLIC_KEY}" \
        LOG_DESTINATION=logs \
        nohup cargo run &> "$ROOT/logs/backend.log" &
        echo $! > "$ROOT/.backend.pid"
        disown
        cd "$ROOT"
        echo "  ✓ Backend started"
      fi

      # Adminer
      if pgrep -f "php -S localhost:${toString env.ADMINER_PORT}" > /dev/null 2>&1; then
        echo "  ✓ Adminer already running"
      else
        echo "  → Starting Adminer..."
        nohup ${pkgs.php83}/bin/php -S localhost:${toString env.ADMINER_PORT} ${pkgs.adminer}/adminer.php &> "$ROOT/logs/adminer.log" & disown
        echo "  ✓ Adminer started"
      fi

      # Frontend
      if [ -f "$ROOT/.frontend.pid" ] && kill -0 $(cat "$ROOT/.frontend.pid") 2>/dev/null; then
        echo "  ✓ Frontend already running"
      else
        echo "  → Starting Frontend..."
        cd "$ROOT/frontend"
        PATH="${pkgs.nodejs}/bin:$PATH" nohup ${pkgs.nodejs}/bin/npm run web &> "$ROOT/logs/frontend.log" &
        echo $! > "$ROOT/.frontend.pid"
        disown
        cd "$ROOT"
        echo "  ✓ Frontend started"
      fi

      # LSP Mux
      if [ -f "$ROOT/.lspmux.pid" ] && kill -0 $(cat "$ROOT/.lspmux.pid") 2>/dev/null; then
        echo "  ✓ LSP Mux already running"
      else
        echo "  → Starting LSP Mux..."
        LSPMUX_DIR="/tmp/ra-${env.LSPMUX_PORT}"
        CONFIG_DIR="$LSPMUX_DIR/lspmux"
        CONFIG_FILE="$CONFIG_DIR/config.toml"
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_FILE" <<EOF
        ${env.LSPMUX_CONFIG}
      EOF
        XDG_CONFIG_HOME=$LSPMUX_DIR nohup lspmux server &> "$ROOT/logs/lspmux.log" &
        echo $! > "$ROOT/.lspmux.pid"
        disown
        echo "  ✓ LSP Mux started"
      fi

      ${status}/bin/status
      echo ""
      echo "Logs: $ROOT/logs/"
    '';

    # Stop development environment
    stop-dev = pkgs.writeShellScriptBin "stop-dev" ''
      ROOT="$PWD"
      echo "Stopping services..."

      # LSP Mux
      if [ -f "$ROOT/.lspmux.pid" ] && kill $(cat "$ROOT/.lspmux.pid") 2>/dev/null; then
        rm -f "$ROOT/.lspmux.pid"
        echo "  ✓ LSP Mux stopped"
      else
        rm -f "$ROOT/.lspmux.pid"
        echo "  ✗ LSP Mux not running"
      fi

      # Frontend
      if [ -f "$ROOT/.frontend.pid" ] && kill $(cat "$ROOT/.frontend.pid") 2>/dev/null; then
        rm -f "$ROOT/.frontend.pid"
        echo "  ✓ Frontend stopped"
      else
        rm -f "$ROOT/.frontend.pid"
        echo "  ✗ Frontend not running"
      fi

      # Adminer
      if pkill -f "php -S localhost:${toString env.ADMINER_PORT}" 2>/dev/null; then
        echo "  ✓ Adminer stopped"
      else
        echo "  ✗ Adminer not running"
      fi

      # Backend
      if [ -f "$ROOT/.backend.pid" ] && kill $(cat "$ROOT/.backend.pid") 2>/dev/null; then
        rm -f "$ROOT/.backend.pid"
        echo "  ✓ Backend stopped"
      else
        rm -f "$ROOT/.backend.pid"
        echo "  ✗ Backend not running"
      fi

      # PostgreSQL
      PGDATA="$ROOT/${env.PGDATA}"
      if pg_ctl -D "$PGDATA" stop &>/dev/null; then
        echo "  ✓ PostgreSQL stopped"
      else
        echo "  ✗ PostgreSQL not running"
      fi

      echo "Done."
    '';

    # Show status of all services
    status = pkgs.writeShellScriptBin "status" ''
      ROOT="$PWD"
      echo "Service Status:"
      echo ""

      # PostgreSQL
      if pg_isready -h ${env.DB_HOST} -q 2>/dev/null; then
        echo "  PostgreSQL   ✓ Running    localhost:5432"
      else
        echo "  PostgreSQL   ✗ Stopped"
      fi

      # Backend
      if [ -f "$ROOT/.backend.pid" ] && kill -0 $(cat "$ROOT/.backend.pid") 2>/dev/null; then
        echo "  Backend      ✓ Running    localhost:${env.SERVER_PORT}"
      else
        echo "  Backend      ✗ Stopped"
      fi

      # Adminer
      if pgrep -f "php -S localhost:${toString env.ADMINER_PORT}" > /dev/null 2>&1; then
        echo "  Adminer      ✓ Running    localhost:${toString env.ADMINER_PORT}"
      else
        echo "  Adminer      ✗ Stopped"
      fi

      # Frontend
      if [ -f "$ROOT/.frontend.pid" ] && kill -0 $(cat "$ROOT/.frontend.pid") 2>/dev/null; then
        echo "  Frontend     ✓ Running    localhost:${env.FRONTEND_PORT}"
      else
        echo "  Frontend     ✗ Stopped"
      fi

      # LSP Mux
      if [ -f "$ROOT/.lspmux.pid" ] && kill -0 $(cat "$ROOT/.lspmux.pid") 2>/dev/null; then
        echo "  LSP Mux      ✓ Running    localhost:${env.LSPMUX_PORT}"
      else
        echo "  LSP Mux      ✗ Stopped"
      fi
    '';

    adminer = pkgs.writeShellScriptBin "adminer" ''
      ${pkgs.php83}/bin/php -S localhost:${toString env.ADMINER_PORT} ${pkgs.adminer}/adminer.php
    '';

    # Start PostgreSQL
    start-postgres = pkgs.writeShellScriptBin "start-postgres" ''
      set -e
      ROOT="$PWD"
      PGDATA="$ROOT/${env.PGDATA}"
      if [ ! -d "$PGDATA" ]; then
        echo "Initializing PostgreSQL database..."
        initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
      fi
      echo "Starting PostgreSQL..."
      pg_ctl -D "$PGDATA" -l "$ROOT/logs/postgres.log" -o "-k /tmp" start
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

    # Run npm commands in frontend directory
    npm = pkgs.writeShellScriptBin "npm" ''
      (cd frontend && ${pkgs.nodejs}/bin/npm "$@")
    '';

    # Run pnpm commands in frontend directory
    pnpm = pkgs.writeShellScriptBin "pnpm" ''
      (cd frontend && ${pkgs.pnpm}/bin/pnpm "$@")
    '';

    # Start frontend web dev server
    web = pkgs.writeShellScriptBin "web" ''
      set -e
      (cd frontend && ${pkgs.nodejs}/bin/npm run web "$@")
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

    # Kills the backend process for this project
    kp = pkgs.writeShellScriptBin "kp" ''
      ROOT="$PWD"
      if [ -f "$ROOT/.backend.pid" ]; then
        kill $(cat "$ROOT/.backend.pid") 2>/dev/null && echo "Backend killed" || echo "Backend not running"
        rm -f "$ROOT/.backend.pid"
      else
        echo "No backend PID file found"
      fi
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
