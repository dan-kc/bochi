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
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d "''${DB_NAME}" -c "TRUNCATE refresh_tokens, rewards, tags, habits, trades, users CASCADE;"
      echo "Database cleaned!"
    '';

    # Truncates all tables and loads fixture data into tofustash database
    seed = pkgs.writeShellScriptBin "seed" ''
      set -e
      ${clean}/bin/clean ${env.DB_NAME} || true
      echo "Loading fixture data..."
      PGPASSWORD=${env.DB_PASSWORD} psql -h ${env.DB_HOST} -U ${env.DB_USER} -d ${env.DB_NAME} -f ./dev-seed.sql
      echo "Fixtures loaded successfully!"
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
      touch "$ROOT/logs/postgres.log" "$ROOT/logs/adminer.log" "$ROOT/logs/backend.log" "$ROOT/logs/lspmux.log"

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
        RUST_LOG=info \
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
    stop = pkgs.writeShellScriptBin "stop" ''
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

    # Build and run native iOS app in simulator
    ios = pkgs.writeShellScriptBin "ios" ''
      set -e
      ROOT="$PWD"
      PROJECT="$ROOT/ios/tofustash.xcodeproj"
      SCHEME="tofustash"
      BUNDLE_ID="dev.keone.tofustash"
      BUILD_DIR="$ROOT/ios/build"

      # Determine simulator device
      DEVICE="''${1:-iPhone 17 Pro}"

      mkdir -p "$ROOT/logs"

      echo "Building $SCHEME for $DEVICE..."

      # Run xcodebuild with sanitized environment (removes Nix toolchain interference)
      env -i \
        HOME="$HOME" \
        USER="$USER" \
        SHELL="/bin/bash" \
        TERM="$TERM" \
        LANG="en_US.UTF-8" \
        PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
        DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
        bash -c "
          set -e

          # Build for simulator
          xcodebuild \
            -project '$PROJECT' \
            -scheme '$SCHEME' \
            -configuration Debug \
            -destination 'platform=iOS Simulator,name=$DEVICE' \
            -derivedDataPath '$BUILD_DIR' \
            build 2>&1 | tail -20

          # Find the built .app
          APP_PATH=\$(find '$BUILD_DIR' -name '$SCHEME.app' -path '*/Debug-iphonesimulator/*' | head -1)
          if [ -z \"\$APP_PATH\" ]; then
            echo 'Error: Could not find built .app bundle'
            exit 1
          fi
          echo \"Built: \$APP_PATH\"

          # Boot simulator if not already booted (pick the last match to prefer the latest runtime)
          DEVICE_ID=\$(xcrun simctl list devices available | grep '$DEVICE' | grep -oE '[A-F0-9-]{36}' | tail -1)
          if [ -z \"\$DEVICE_ID\" ]; then
            echo 'Error: Could not find simulator device: $DEVICE'
            echo 'Available devices:'
            xcrun simctl list devices available
            exit 1
          fi

          # Boot the simulator (ignore error if already booted)
          xcrun simctl boot \"\$DEVICE_ID\" 2>/dev/null || true
          open -a Simulator

          # Install and launch with console output for runtime logs
          xcrun simctl install \"\$DEVICE_ID\" \"\$APP_PATH\"
          xcrun simctl terminate \"\$DEVICE_ID\" '$BUNDLE_ID' 2>/dev/null || true

          echo 'App launched. Streaming runtime logs (also saved to $ROOT/logs/ios.log)...'
          echo
          exec xcrun simctl launch --console-pty \"\$DEVICE_ID\" '$BUNDLE_ID' 2>&1 | tee '$ROOT/logs/ios.log'
        "
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

    # Displays the schema of a database table in tofustash, or lists all tables if no argument
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
  darwinScripts =
    if pkgs.stdenv.isDarwin then
      {
        # Run Swift Testing unit tests on macOS.
        ios-test = pkgs.writeShellScriptBin "ios-test" ''
          set -e -o pipefail
          ROOT="$PWD"
          PROJECT="$ROOT/ios/tofustash.xcodeproj"
          SCHEME="tofustash"
          BUILD_DIR="$ROOT/ios/build"
          DEVICE="''${1:-iPhone 17 Pro}"

          echo "Running unit tests for $SCHEME on $DEVICE..."

          ${sanitizedXcodeEnvironment} \
            PROJECT="$PROJECT" \
            SCHEME="$SCHEME" \
            BUILD_DIR="$BUILD_DIR" \
            DEVICE="$DEVICE" \
            bash <<'EOF'
          set -e -o pipefail
          ${resolveConcreteSimulator}

          cleanup() {
            xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          }
          trap cleanup EXIT

          xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl bootstatus "$DEVICE_ID" -b

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
            -only-testing:tofustashTests \
            test 2>&1 | ${pkgs.xcbeautify}/bin/xcbeautify
          EOF
        '';

        # Run XCTest UI tests on macOS.
        ios-xctest = pkgs.writeShellScriptBin "ios-xctest" ''
          set -e -o pipefail
          ROOT="$PWD"
          PROJECT="$ROOT/ios/tofustash.xcodeproj"
          SCHEME="tofustash"
          BUILD_DIR="$ROOT/ios/build"
          DEVICE="''${1:-iPhone 17 Pro}"

          echo "Running XCTest UI tests for $SCHEME on $DEVICE..."

          ${sanitizedXcodeEnvironment} \
            PROJECT="$PROJECT" \
            SCHEME="$SCHEME" \
            BUILD_DIR="$BUILD_DIR" \
            DEVICE="$DEVICE" \
            bash <<'EOF'
          set -e -o pipefail
          ${resolveConcreteSimulator}

          cleanup() {
            xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          }
          trap cleanup EXIT

          xcrun simctl shutdown "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
          xcrun simctl bootstatus "$DEVICE_ID" -b

          xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination "platform=iOS Simulator,id=$DEVICE_ID" \
            -parallel-testing-enabled NO \
            -parallel-testing-worker-count 1 \
            -maximum-concurrent-test-simulator-destinations 1 \
            -derivedDataPath "$BUILD_DIR" \
            -only-testing:tofustashUITests \
            test 2>&1 | ${pkgs.xcbeautify}/bin/xcbeautify
          EOF
        '';

        # Build, install, and launch the app on a connected iPhone.
        ios-device = pkgs.writeShellScriptBin "ios-device" ''
          set -e -o pipefail
          ROOT="$PWD"
          PROJECT="$ROOT/ios/tofustash.xcodeproj"
          SCHEME="tofustash"
          BUNDLE_ID="dev.keone.tofustash"
          BUILD_DIR="$ROOT/ios/build"
          DEVICE="''${1:-iPhone rass}"

          mkdir -p "$ROOT/logs"

          echo "Building $SCHEME for $DEVICE..."

          unset AR
          unset CC
          unset CXX
          unset LD
          unset NM
          unset RANLIB
          unset SDKROOT
          unset TOOLCHAINS
          unset LIBRARY_PATH
          unset CPATH
          unset C_INCLUDE_PATH
          unset CPLUS_INCLUDE_PATH
          unset OBJC_INCLUDE_PATH
          unset OBJCPLUS_INCLUDE_PATH
          unset NIX_CFLAGS_COMPILE
          unset NIX_CFLAGS_LINK
          unset NIX_LDFLAGS
          unset NIX_CC
          unset NIX_BINTOOLS
          unset DEVELOPER_DIR

          PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH" \
          DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
          PROJECT="$PROJECT" \
          SCHEME="$SCHEME" \
          BUNDLE_ID="$BUNDLE_ID" \
          BUILD_DIR="$BUILD_DIR" \
          ROOT="$ROOT" \
          DEVICE="$DEVICE" \
          bash <<'EOF'
          set -e -o pipefail

          echo "==> Starting Xcode build"
          NSUnbufferedIO=YES xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -sdk iphoneos \
            -destination "platform=iOS,name=$DEVICE" \
            -destination-timeout 60 \
            -allowProvisioningUpdates \
            -allowProvisioningDeviceRegistration \
            -derivedDataPath "$BUILD_DIR" \
            build 2>&1 \
            | tee "$ROOT/logs/ios-device-xcodebuild.log" \
            | ${pkgs.xcbeautify}/bin/xcbeautify

          echo "==> Build finished"

          APP_PATH=$(xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -sdk iphoneos \
            -showBuildSettings -json \
            | /usr/bin/jq -r '.[0].buildSettings.TARGET_BUILD_DIR + "/" + .[0].buildSettings.FULL_PRODUCT_NAME')

          if [ -z "$APP_PATH" ]; then
            echo "Error: Could not resolve built .app bundle path"
            exit 1
          fi
          if [ ! -d "$APP_PATH" ]; then
            echo "Error: Built .app bundle does not exist at: $APP_PATH"
            exit 1
          fi

          echo "==> Built app: $APP_PATH"
          echo "Installing on $DEVICE..."
          xcrun devicectl device install app --device "$DEVICE" "$APP_PATH"

          echo "==> Install finished"
          echo "Launching on $DEVICE..."
          echo "==> Attaching to device console; output is also saved to $ROOT/logs/ios-device.log"
          xcrun devicectl device process launch --device "$DEVICE" --console --terminate-existing "$BUNDLE_ID" \
            | tee "$ROOT/logs/ios-device.log"
          EOF
        '';
      }
    else
      { };
in
builtins.attrValues (scripts // darwinScripts)
