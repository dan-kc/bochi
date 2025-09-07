{ pkgs }:
[
  (pkgs.writeShellScriptBin "clean" ''
    if [ -z "$1" ]; then
      echo "Usage: clean <database_name>"
      exit 1
    fi
    DB_NAME="$1"
    echo "Truncating all tables in ''${DB_NAME} database..."
    docker compose exec -T db psql -U user -d "''${DB_NAME}" -c "TRUNCATE habits, refresh_tokens, tags, task_dependencies, task_tags, tasks, trades, users CASCADE;"
    echo "Database cleaned!"
  '')

  (pkgs.writeShellScriptBin "t" ''
    export AWS_SECRETS_PREFIX="test-" 
    export DATABASE_NAME="test_habit_market" 
    make clean-test-db
    cargo test "$@"
    export AWS_SECRETS_PREFIX="" 
    export DATABASE_NAME="habit_market" 
  '')
]