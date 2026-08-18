{ pkgs, env }:
let
  sanitizedXcodeEnvironment = ''
    env -i \
      HOME="$HOME" \
      USER="$USER" \
      SHELL="/bin/bash" \
      TERM="$TERM" \
      LANG="en_US.UTF-8" \
      PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
      DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  '';

  resolveConcreteSimulator = ''
    DEVICE_ID=$(xcrun simctl list devices available | grep -E "^[[:space:]]+$DEVICE \\(" | grep -oE '[A-F0-9-]{36}' | tail -1)
    if [ -z "$DEVICE_ID" ]; then
      echo "Error: Could not find simulator device: $DEVICE"
      echo "Available devices:"
      xcrun simctl list devices available
      exit 1
    fi
  '';

  cleanupBochiSimulatorAppData = ''
    cleanup_bochi_simulator_app_data() {
      APP_DATA_DIR=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null || true)
      if [ -n "$APP_DATA_DIR" ] && [ -d "$APP_DATA_DIR/tmp" ]; then
        find "$APP_DATA_DIR/tmp" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
      fi
      xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
    }
  '';

  loadLocalJwtEnvironment = ''
    LOCAL_JWT_DIR="$ROOT/.local/jwt"
    LOCAL_JWT_PRIVATE_KEY="$LOCAL_JWT_DIR/private.pem"
    LOCAL_JWT_PUBLIC_KEY="$LOCAL_JWT_DIR/public.pem"

    if [ ! -s "$LOCAL_JWT_PRIVATE_KEY" ] || [ ! -s "$LOCAL_JWT_PUBLIC_KEY" ]; then
      echo "Generating checkout-local JWT signing keys..."
      umask 077
      mkdir -p "$LOCAL_JWT_DIR"
      PRIVATE_KEY_TEMP=$(mktemp "$LOCAL_JWT_DIR/.private.XXXXXX")
      PUBLIC_KEY_TEMP=$(mktemp "$LOCAL_JWT_DIR/.public.XXXXXX")
      ${pkgs.openssl}/bin/openssl genpkey -algorithm ED25519 -out "$PRIVATE_KEY_TEMP"
      ${pkgs.openssl}/bin/openssl pkey -in "$PRIVATE_KEY_TEMP" -pubout -out "$PUBLIC_KEY_TEMP"
      mv "$PRIVATE_KEY_TEMP" "$LOCAL_JWT_PRIVATE_KEY"
      mv "$PUBLIC_KEY_TEMP" "$LOCAL_JWT_PUBLIC_KEY"
    fi

    export JWT_PRIVATE_KEY="$(<"$LOCAL_JWT_PRIVATE_KEY")"
    export JWT_PUBLIC_KEY="$(<"$LOCAL_JWT_PUBLIC_KEY")"
  '';

  ensureLocalPostgresDatabases = ''
    export PGHOST=${env.DB_HOST}

    if psql -U "$USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${env.DB_USER}'" | grep -qx 1; then
      echo "  ✓ User '${env.DB_USER}' already exists"
    else
      createuser -U "$USER" "${env.DB_USER}"
    fi

    psql -U "$USER" -d postgres -v ON_ERROR_STOP=1 -c "ALTER USER \"${env.DB_USER}\" WITH PASSWORD '${env.DB_PASSWORD}';"

    ensure_database() {
      DATABASE_NAME="$1"
      if PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME'" | grep -qx 1; then
        echo "  ✓ Database '$DATABASE_NAME' already exists"
      else
        createdb -U "$USER" -O "${env.DB_USER}" "$DATABASE_NAME"
      fi
    }

    ensure_database "${env.DB_NAME}"
    ensure_database "${env.DB_NAME_TEST}"
  '';

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
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d "''${DB_NAME}" -c "TRUNCATE apple_server_notifications, refresh_tokens, rewards, tags, tasks, trades, users CASCADE;"
      echo "Database cleaned!"
    '';

    # Truncates all tables and loads fixture data into bochi database
    seed = pkgs.writeShellScriptBin "seed" ''
      set -e
      ${clean}/bin/clean ${env.DB_NAME} || true
      echo "Loading fixture data..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -f ./dev-seed.sql
      echo "Fixtures loaded successfully!"
    '';

    # Removes local premium/subscription state without deleting users or app data.
    reset-subscriptions = pkgs.writeShellScriptBin "reset-subscriptions" ''
      set -e
      echo "Deleting local subscription state from ${env.DB_NAME} database..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -v ON_ERROR_STOP=1 -c "
        DELETE FROM premium_entitlements;
        DELETE FROM apple_server_notifications;
        UPDATE users
        SET subscription_source = NULL,
            subscription_status = 'none',
            subscription_expires_at = NULL,
            external_billing_customer_id = NULL,
            subscription_product_id = NULL,
            app_store_original_transaction_id = NULL,
            app_store_latest_transaction_id = NULL,
            app_store_environment = NULL;
      "
      echo "Local subscription state deleted."
    '';

    # Start development environment
    start = pkgs.writeShellScriptBin "start" ''
      set -e
      ROOT="$PWD"

      # Handle --force flag
      if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        echo "Force restarting all services..."
        ${stop}/bin/stop
        echo ""
      fi

      mkdir -p "$ROOT/logs"
      touch "$ROOT/logs/postgres.log" "$ROOT/logs/adminer.log" "$ROOT/logs/backend.log"

      echo "Checking services..."

      # PostgreSQL
      PGDATA="''${PGDATA:-$ROOT/${env.PGDATA}}"
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
        ${ensureLocalPostgresDatabases}
        echo "  ✓ PostgreSQL started"
      fi

      # Backend
      if [ -f "$ROOT/.backend.pid" ] && kill -0 $(cat "$ROOT/.backend.pid") 2>/dev/null; then
        echo "  ✓ Backend already running"
      else
        echo "  → Starting Backend..."
        ${loadLocalJwtEnvironment}
        cd "$ROOT/backend"
        PORT="${env.SERVER_PORT}" \
        DB_USER="${env.DB_USER}" \
        DB_PASSWORD="${env.DB_PASSWORD}" \
        DB_HOST="${env.DB_HOST}" \
        DB_NAME="${env.DB_NAME}" \
        SSL_MODE="disable" \
        JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
        JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
        APPLE_SIGN_IN_AUDIENCE="${env.APPLE_SIGN_IN_AUDIENCE}" \
        ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS=true \
        LOG_DESTINATION=logs \
        RUST_LOG="${env.RUST_LOG}" \
        cargo build
        PORT="${env.SERVER_PORT}" \
        DB_USER="${env.DB_USER}" \
        DB_PASSWORD="${env.DB_PASSWORD}" \
        DB_HOST="${env.DB_HOST}" \
        DB_NAME="${env.DB_NAME}" \
        SSL_MODE="disable" \
        JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
        JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
        APPLE_SIGN_IN_AUDIENCE="${env.APPLE_SIGN_IN_AUDIENCE}" \
        ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS=true \
        LOG_DESTINATION=logs \
        RUST_LOG="${env.RUST_LOG}" \
        nohup "$ROOT/backend/target/debug/bochi-backend" &> "$ROOT/logs/backend.log" &
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

      # LSP Mux
      echo "  → Checking LSP Mux..."
      ra-start

      ${status}/bin/status
      echo ""
      echo "Logs: $ROOT/logs/"
    '';

    # Stop development environment
    stop = pkgs.writeShellScriptBin "stop" ''
      ROOT="$PWD"
      echo "Stopping services..."

      # LSP Mux
      ra-stop

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
      PGDATA="''${PGDATA:-$ROOT/${env.PGDATA}}"
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

      # LSP Mux
      ra-status
    '';

    adminer = pkgs.writeShellScriptBin "adminer" ''
      ${pkgs.php83}/bin/php -S localhost:${toString env.ADMINER_PORT} ${pkgs.adminer}/adminer.php
    '';

    # Start PostgreSQL
    start-postgres = pkgs.writeShellScriptBin "start-postgres" ''
      set -e
      ROOT="$PWD"
      PGDATA="''${PGDATA:-$ROOT/${env.PGDATA}}"
      mkdir -p "$ROOT/logs"
      if [ ! -d "$PGDATA" ]; then
        echo "Initializing PostgreSQL database..."
        initdb -D "$PGDATA" --auth-local=trust --auth-host=trust
      fi
      echo "Starting PostgreSQL..."
      pg_ctl -D "$PGDATA" -l "$ROOT/logs/postgres.log" -o "-k /tmp" start
      sleep 2
      ${ensureLocalPostgresDatabases}
      echo "PostgreSQL started successfully"
    '';

    # Wraps `cargo run` with env vars
    run = pkgs.writeShellScriptBin "run" ''
      set -e
      ROOT="$PWD"
      ${loadLocalJwtEnvironment}
      cd backend
      PORT="${env.SERVER_PORT}" \
      DB_USER="${env.DB_USER}" \
      DB_PASSWORD="${env.DB_PASSWORD}" \
      DB_HOST="${env.DB_HOST}" \
      DB_NAME="${env.DB_NAME}" \
      SSL_MODE="disable" \
      JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
      JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
      APPLE_SIGN_IN_AUDIENCE="${env.APPLE_SIGN_IN_AUDIENCE}" \
      ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS=true \
      LOG_DESTINATION=logs \
      cargo run "$@"
    '';

    # Sets up and tears down the test environment. Wraps `cargo test`.
    t = pkgs.writeShellScriptBin "t" ''
      set -e
      ROOT="$PWD"
      ${loadLocalJwtEnvironment}
      ${clean}/bin/clean ${env.DB_NAME_TEST}
      cd backend
      PORT="${env.SERVER_PORT}" \
      DB_USER="${env.DB_USER}" \
      DB_PASSWORD="${env.DB_PASSWORD}" \
      DB_HOST="${env.DB_HOST}" \
      DB_NAME="${env.DB_NAME_TEST}" \
      SSL_MODE="disable" \
      JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
      JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
      APPLE_SIGN_IN_AUDIENCE="${env.APPLE_SIGN_IN_AUDIENCE}" \
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

    # Displays the schema of a database table in bochi, or lists all tables if no argument
    schema = pkgs.writeShellScriptBin "schema" ''
      set -e
      if [ -z "$1" ]; then
        PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -P pager=off -c "\dt"
      else
        TABLE_NAME="$1"
        PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -P pager=off -c "\d+ ''${TABLE_NAME}"
      fi
    '';

    # Flyway wrapper with config
    fw = pkgs.writeShellScriptBin "fw" ''
      set -e
      # Use the first argument as DATABASE_NAME if provided, otherwise default to bochi
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

    # Updates the Debug iOS local API host to this Mac's active IPv4 address.
    update-ip = pkgs.writeShellScriptBin "update-ip" ''
      set -euo pipefail

      ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      PROJECT_FILE="$ROOT/ios/bochi.xcodeproj/project.pbxproj"

      detect_ip() {
        if command -v ipconfig >/dev/null 2>&1; then
          IP=$(ipconfig getifaddr en0 2>/dev/null || true)
          if [ -n "$IP" ]; then
            printf '%s\n' "$IP"
            return 0
          fi
        fi

        if ! command -v ifconfig >/dev/null 2>&1; then
          return 1
        fi

        for IFACE in en0 en1 en2 en3 en4 en5; do
          DETAILS=$(ifconfig "$IFACE" 2>/dev/null || true)
          if ! printf '%s\n' "$DETAILS" | grep -q "status: active"; then
            continue
          fi

          IP=$(printf '%s\n' "$DETAILS" | awk '$1 == "inet" && $2 !~ /^127\./ { print $2; exit }')
          if [ -n "$IP" ]; then
            printf '%s\n' "$IP"
            return 0
          fi
        done

        for IFACE in $(ifconfig -l 2>/dev/null || true); do
          DETAILS=$(ifconfig "$IFACE" 2>/dev/null || true)
          if ! printf '%s\n' "$DETAILS" | grep -q "status: active"; then
            continue
          fi

          IP=$(printf '%s\n' "$DETAILS" | awk '$1 == "inet" && $2 !~ /^127\./ { print $2; exit }')
          if [ -n "$IP" ]; then
            printf '%s\n' "$IP"
            return 0
          fi
        done

        return 1
      }

      IP="''${1:-}"
      if [ -z "$IP" ]; then
        IP=$(detect_ip) || {
          echo "Error: Could not detect an active IPv4 address. Pass one explicitly: update-ip 192.168.x.x"
          exit 1
        }
      fi

      if ! printf '%s\n' "$IP" | awk -F. 'NF == 4 { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i > 255) exit 1; exit 0 } { exit 1 }'; then
        echo "Error: Invalid IPv4 address: $IP"
        exit 1
      fi

      if [ ! -f "$PROJECT_FILE" ]; then
        echo "Error: Could not find Xcode project file: $PROJECT_FILE"
        exit 1
      fi

      TMP_FILE=$(mktemp)
      if ! awk -v ip="$IP" '
        /BOCHI_LOCAL_API_HOST = [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+;/ {
          sub(/BOCHI_LOCAL_API_HOST = [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+;/, "BOCHI_LOCAL_API_HOST = " ip ";")
          changed = 1
        }
        { print }
        END { if (!changed) exit 2 }
      ' "$PROJECT_FILE" > "$TMP_FILE"; then
        rm -f "$TMP_FILE"
        echo "Error: Could not find BOCHI_LOCAL_API_HOST in $PROJECT_FILE"
        exit 1
      fi

      mv "$TMP_FILE" "$PROJECT_FILE"
      echo "Updated BOCHI_LOCAL_API_HOST to $IP"
    '';

    # drops and recreates the provided database, then applies migrations.
    nuke = pkgs.writeShellScriptBin "nuke" ''
      set -e
      if [ -z "$1" ]; then
        echo "Usage: nuke <database_name>"
        exit 1
      fi
      DB_NAME="$1"
      echo "Killing any running bochi processes..."
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
  darwinScripts =
    if pkgs.stdenv.isDarwin then
      {
        # Run Swift Testing unit tests on macOS.
        ios-test = pkgs.writeShellScriptBin "ios-test" ''
          set -e -o pipefail
          ROOT="$PWD"
          PROJECT="$ROOT/ios/bochi.xcodeproj"
          SCHEME="bochi"
          BUNDLE_ID="app.bochi"
          BUILD_DIR="$ROOT/ios/build"
          DEVICE="iPhone 17 Pro"

          if [ "$#" -gt 0 ]; then
            echo "Running unit tests $* for $SCHEME on $DEVICE..."
          else
            echo "Running unit tests for $SCHEME on $DEVICE..."
          fi

          ${sanitizedXcodeEnvironment} \
            PROJECT="$PROJECT" \
            SCHEME="$SCHEME" \
            BUNDLE_ID="$BUNDLE_ID" \
            BUILD_DIR="$BUILD_DIR" \
            DEVICE="$DEVICE" \
            TEST_NAMES="$*" \
            bash <<'EOF'
          set -e -o pipefail
          ${resolveConcreteSimulator}
          ${cleanupBochiSimulatorAppData}

          ONLY_TESTING_ARGS=("-only-testing:bochiTests")
          if [ -n "$TEST_NAMES" ]; then
            ONLY_TESTING_ARGS=()
            for TEST_NAME in $TEST_NAMES; do
              ONLY_TESTING_ARGS+=("-only-testing:bochiTests/$TEST_NAME")
            done
          fi

          cleanup() {
            cleanup_bochi_simulator_app_data
            xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          }
          trap cleanup EXIT

          xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl bootstatus "$DEVICE_ID" -b
          cleanup_bochi_simulator_app_data

          # Run one suite process at a time so a Debug trap reports the
          # real failing test instead of cascading through cloned runners.
          xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination "platform=iOS Simulator,id=$DEVICE_ID" \
            -parallel-testing-enabled NO \
            -parallel-testing-worker-count 1 \
            -maximum-concurrent-test-simulator-destinations 1 \
            -derivedDataPath "$BUILD_DIR" \
            "''${ONLY_TESTING_ARGS[@]}" \
            test 2>&1 | ${pkgs.xcbeautify}/bin/xcbeautify
          EOF
        '';
      }
    else
      { };
in
builtins.attrValues (scripts // darwinScripts)
