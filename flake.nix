{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      flake-utils,
      fenix,
      android-nixpkgs,
      self,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ fenix.overlays.default ];
        pkgs = import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;
        };
        env = rec {
          # Database
          DB_NAME = "tofustash";
          DB_NAME_TEST = "tofustash_test";
          DB_HOST = "localhost";
          DB_PORT = "5432";
          DB_USER = "user";
          DB_PASSWORD = "password";
          PGDATA = ".pgdata";

          # Backend
          SERVER_PORT = "8501";
          SERVER_LOG_FILE = "./logs/server.log";
          RUST_LOG = "info";
          # RUST_BACKTRACE = 1;
          JWT_PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd
    -----END PRIVATE KEY-----";
          JWT_PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----
    MCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=
    -----END PUBLIC KEY-----";

          # Frontend
          FRONTEND_PORT = "8502";
          FRONTEND_LOG_FILE = "./logs/frontend.log";

          # Postgres
          POSTGRES_LOG_FILE = "./logs/postgres.log";

          # Adminer
          ADMINER_LOG_FILE = "./logs/adminer.log";

          # lspmux
          LSPMUX_PORT = "8503";
          LSPMUX_LOG_FILE = "./logs/lspmux.log";
          LSPMUX_CONFIG = ''
            instance_timeout = false 
            gc_interval = 10
            listen = ["127.0.0.1", ${LSPMUX_PORT}]
            connect = ["127.0.0.1", ${LSPMUX_PORT}]
            log_filters = "info"
            pass_environment = []
          '';

          # Adminer
          ADMINER_PORT = 8504;
        };
        android-sdk = android-nixpkgs.sdk.${system} (
          sdkPkgs: with sdkPkgs; [
            cmdline-tools-latest
            build-tools-36-0-0
            platform-tools
            platforms-android-36
            emulator
            system-images-android-36-google-apis-x86-64
          ]
        );
        scripts = import ./scripts.nix {
          inherit pkgs;
          inherit env;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs =
            with pkgs;
            [
              (fenix.packages.${system}.complete.withComponents [
                "cargo"
                "clippy"
                "rustc"
                "rustfmt"
              ])
              typescript-language-server
              nodePackages.prettier
              eas-cli
              rust-analyzer
              terraform-ls
              adminer
              php83Extensions.pgsql
              nil
              openssl
              nixfmt-rfc-style
              taplo
              flyway
              opentofu
              awscli2
              lspmux
              circleci-cli
              postgresql
              moreutils
              ktlint
              jdk21
              android-sdk
              # android-studio
            ]
            ++ scripts;
          shellHook = ''
            # export RUST_BACKTRACE=1
            export FRONTEND_PORT="${env.FRONTEND_PORT}"
            export HOST="localhost"
            export LSPMUX_PORT="${env.LSPMUX_PORT}"
            export JAVA_HOME="${pkgs.jdk21}"
            export ANDROID_HOME="${android-sdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"

            # Generate local.properties for Gradle (nix-store paths change on rebuild)
            if [ -d "$PWD/android" ]; then
              cat > "$PWD/android/local.properties" <<LOCALPROPS
            sdk.dir=$ANDROID_HOME
            LOCALPROPS
            fi
            # NixOS: aapt2 override for Gradle (AGP only reads this from gradle.properties, not local.properties)
            export AAPT2_FROM_MAVEN_OVERRIDE="$ANDROID_HOME/build-tools/36.0.0/aapt2"

            status
          '';
        };

        packages.server = pkgs.rustPlatform.buildRustPackage {
          pname = "tofustash-backend";
          version = "0.1.0";
          src = backend/.;
          doCheck = false; # Run tests seperately

          cargoLock = {
            lockFile = backend/Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
          ];

          buildInputs = with pkgs; [
            openssl
          ];

        };
        packages.default = self.packages.${system}.server;
        packages.server-docker = pkgs.dockerTools.buildLayeredImage {
          name = "tofustash-backend";
          # This tag is only used locally. ECR doesn't know about this.
          tag = "latest";

          contents = with pkgs; [
            dockerTools.caCertificates
            self.packages.${system}.server
          ];

          config = {
            Cmd = [ "${self.packages.${system}.server}/bin/tofustash-backend" ];
            WorkingDir = "/app";
            ExposedPorts = {
              "8080/tcp" = { };
            };
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        packages.flyway-docker = pkgs.dockerTools.buildLayeredImage {
          name = "tofustash-migrations";
          tag = "latest";

          contents = with pkgs; [
            dockerTools.caCertificates
            flyway
            awscli2
            bash
            coreutils
            gnugrep
            gnused
            jq
          ];

          extraCommands = ''
            mkdir -p sql scripts
            cp -r ${./migrations}/* sql/
            cp ${./flyway-entrypoint.sh} scripts/flyway-entrypoint.sh
            chmod +x scripts/flyway-entrypoint.sh
          '';

          config = {
            Entrypoint = [ "/scripts/flyway-entrypoint.sh" ];
            WorkingDir = "/";
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "FLYWAY_LOCATIONS=filesystem:/sql"
              "AWS_DEFAULT_REGION=eu-west-2"
              "PATH=${pkgs.gnused}/bin:${pkgs.awscli2}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.jq}/bin:${pkgs.flyway}/bin"
            ];
          };
        };
      }
    );
}
