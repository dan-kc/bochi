{ pkgs }:
let
  ra-multiplex-port = "27632";
  ra-config = ''
    instance_timeout = false 
    gc_interval = 10
    listen = ["127.0.0.1", ${ra-multiplex-port}]
    connect = ["127.0.0.1", ${ra-multiplex-port}]
    log_filters = "info"
    pass_environment = []
  '';

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
      PGPASSWORD=password psql -h localhost -U user -d "''${DB_NAME}" -c "TRUNCATE refresh_tokens, tags, task_dependencies, task_tags, tasks, trades, users CASCADE;"
      echo "Database cleaned!"
    '';

    ra = pkgs.writeShellScriptBin "ra" ''
      RA_MULTIPLEX_DIR="/tmp/ra-${ra-multiplex-port}"
      CONFIG_DIR="$RA_MULTIPLEX_DIR/ra-multiplex"  
      CONFIG_FILE="$CONFIG_DIR/config.toml"
      LOG_DIR="/tmp/ra-multiplex"
      LOG_FILE="$LOG_DIR/$RA_MULTIPLEX_PORT.log"

      mkdir -p "$LOG_DIR"
      mkdir -p "$CONFIG_DIR"
      cat > "$CONFIG_FILE" <<EOF
      ${ra-config}
      EOF

      XDG_CONFIG_HOME=$RA_MULTIPLEX_DIR ra-multiplex server &> "$LOG_FILE" & disown
      echo "Listening"
    '';

    # Start development environment
    start = pkgs.writeShellScriptBin "start" ''
      set -e
      echo "Stopping any existing services..."
      ${stop}/bin/stop || true
      sleep 1
      echo "Starting services..."
      echo "Starting PostgreSQL..."
      ${start-postgres}/bin/start-postgres
      (nohup adminer &> /dev/null &) && \
      ${start-loki}/bin/start-loki && \
      sleep 2 && \
      ${start-promtail}/bin/start-promtail && \
      ${start-grafana}/bin/start-grafana
      echo "All services started successfully!"
    '';

    adminer = pkgs.writeShellScriptBin "adminer" ''
      ${pkgs.php83}/bin/php -S localhost:8081 ${pkgs.adminer}/adminer.php
    '';

    # Start PostgreSQL
    start-postgres = pkgs.writeShellScriptBin "start-postgres" ''
      set -e
      PGDATA="/tmp/postgres-data"
      if [ ! -d "$PGDATA" ]; then
        echo "Initializing PostgreSQL database..."
        initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
      fi
      echo "Starting PostgreSQL..."
      pg_ctl -D "$PGDATA" -l /tmp/postgres.log -o "-k /tmp" start
      sleep 2
      # Create user and databases if they don't exist
      export PGHOST=localhost
      createuser -U $USER user 2>/dev/null || echo "  ✓ User 'user' already exists"
      psql -U $USER -d postgres -c "ALTER USER \"user\" WITH PASSWORD 'password';" 2>/dev/null || true
      createdb -U $USER -O user habit_market 2>/dev/null || echo "  ✓ Database 'habit_market' already exists"
      createdb -U $USER -O user test_habit_market 2>/dev/null || echo "  ✓ Database 'test_habit_market' already exists"
      echo "PostgreSQL started successfully"
    '';

    # Start loki
    start-loki = pkgs.writeShellScriptBin "start-loki" ''
      set -e
      LOKI_DATA_DIR="/tmp/loki-data"
      mkdir -p "$LOKI_DATA_DIR/chunks"
      mkdir -p "$LOKI_DATA_DIR/rules"
      mkdir -p "$LOKI_DATA_DIR/compactor"
      echo "Starting Loki..."
      ${pkgs.grafana-loki}/bin/loki -config.file=./observability/local/loki-config.yaml &> /tmp/loki.log &
      LOKI_PID=$!
      sleep 2
      if ! kill -0 $LOKI_PID 2>/dev/null; then
        echo "Failed to start Loki. Check /tmp/loki.log for details"
        cat /tmp/loki.log | tail -20
        exit 1
      fi
      echo "Loki started (PID: $LOKI_PID)"
    '';

    # Start promtail
    start-promtail = pkgs.writeShellScriptBin "start-promtail" ''
      set -e
      mkdir -p ./logs
      echo "Starting Promtail..."
      export PROMTAIL_LOG_PATH="$(pwd)/logs/server.log*"
      ${pkgs.grafana-loki}/bin/promtail -config.expand-env=true -config.file=./observability/local/promtail-config.yaml &> /tmp/promtail.log &
      PROMTAIL_PID=$!
      sleep 2
      if ! kill -0 $PROMTAIL_PID 2>/dev/null; then
        echo "Failed to start Promtail. Check /tmp/promtail.log for details"
        cat /tmp/promtail.log | tail -20
        exit 1
      fi
      echo "Promtail started (PID: $PROMTAIL_PID)"
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
      ${pkgs.grafana}/bin/grafana-server --homepath ${pkgs.grafana}/share/grafana &> /tmp/grafana.log &
      GRAFANA_PID=$!
      sleep 2
      if ! kill -0 $GRAFANA_PID 2>/dev/null; then
        echo "Failed to start Grafana. Check /tmp/grafana.log for details"
        cat /tmp/grafana.log | tail -20
        exit 1
      fi
      echo "Grafana started (PID: $GRAFANA_PID)"
    '';

    # Stop development environment
    stop = pkgs.writeShellScriptBin "stop" ''
      echo "Stopping PostgreSQL..."
      pg_ctl -D /tmp/postgres-data stop 2>/dev/null && echo "✓ PostgreSQL stopped" || echo "✗ PostgreSQL not running"

      echo "Stopping Adminer..."
      pkill -f "php -S localhost:8081" && echo "✓ Adminer stopped" || echo "✗ Adminer not running"

      echo "Stopping Loki..."
      pkill -f "loki -config.file" && echo "✓ Loki stopped" || echo "✗ Loki not running"

      echo "Stopping Promtail..."
      pkill -9 promtail && echo "✓ Promtail stopped" || echo "✗ Promtail not running"

      echo "Stopping Grafana..."
      pkill -f "grafana-server" && echo "✓ Grafana stopped" || echo "✗ Grafana not running"

      echo "All services stopped."
    '';

    # Wraps `cargo run` with env vars
    run = pkgs.writeShellScriptBin "run" ''
      DB_USER="user" \
      DB_PASSWORD="password" \
      DB_HOST="localhost" \
      DB_NAME="habit_market" \
      JWT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd
-----END PRIVATE KEY-----" \
      JWT_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=
-----END PUBLIC KEY-----" \
      LOG_DESTINATION=logs \
      cargo run "$@"
    '';

    # Sets up and tears down the test environment. Wraps `cargo test`.
    t = pkgs.writeShellScriptBin "t" ''
      set -e 
      ${clean}/bin/clean test_habit_market
      DB_USER="user" \
      DB_PASSWORD="password" \
      DB_HOST="localhost" \
      DB_NAME="test_habit_market" \
      JWT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd
-----END PRIVATE KEY-----" \
      JWT_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=
-----END PUBLIC KEY-----" \
      cargo test "$@"
    '';

    # Kills all habit_market processes
    kp = pkgs.writeShellScriptBin "kp" ''
      	pkill -f habit-market-backend
    '';

    # Displays the schema of a database table in habit_market
    schema = pkgs.writeShellScriptBin "schema" ''
      set -e 
      if [ -z "$1" ]; then
        echo "Usage: schema <table name>"
        exit 1
      fi
      TABLE_NAME="$1"
      PGPASSWORD=password psql -h localhost -U user -d habit_market -P pager=off -c "\d+ ''${TABLE_NAME}"
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
      PGPASSWORD=password psql -h localhost -U user -d postgres -c "DROP DATABASE IF EXISTS ''${DB_NAME};"
      echo "Creating database..."
      PGPASSWORD=password psql -h localhost -U user -d postgres -c "CREATE DATABASE ''${DB_NAME};"
      echo "Applying migrations to ''${DB_NAME}..."
      ${fw}/bin/fw ''${DB_NAME} migrate
      echo "Database refresh complete!"
    '';
  };
in
builtins.attrValues scripts
