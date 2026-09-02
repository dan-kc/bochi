{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ra-mux = {
      url = "github:dan-kc/ra-mux";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs =
    {
      nixpkgs,
      flake-utils,
      fenix,
      ra-mux,
      self,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ fenix.overlays.default ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        localServiceHost = "127.0.0.1";
        rustToolchain = fenix.packages.${system}.complete.withComponents [
          "cargo"
          "clippy"
          "rust-analyzer"
          "rustc"
          "rustfmt"
          "rust-src"
        ];
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };
        env = {
          # Database
          DB_NAME = "bochi";
          DB_NAME_TEST = "bochi_test";
          DB_HOST = localServiceHost;
          DB_PORT = "5432";
          DB_USER = "user";
          DB_PASSWORD = "password";
          PGDATA = ".pgdata";

          # Backend
          SERVER_PORT = "8501";
          SERVER_LOG_FILE = "./logs/server.log";
          RUST_LOG = "bochi_backend=info,tower_http=info,axum=warn,hyper=warn,sqlx=warn";
          APPLE_SIGN_IN_AUDIENCE = "app.bochi";
          # RUST_BACKTRACE = 1;

          # Postgres
          POSTGRES_LOG_FILE = "./logs/postgres.log";

          # Adminer
          ADMINER_LOG_FILE = "./logs/adminer.log";

          # Adminer
          ADMINER_PORT = 8504;
          LOCAL_SERVICE_HOST = localServiceHost;
        };
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
              rustToolchain
              prettier
              terraform-ls
              adminer
              php83Extensions.pgsql
              nil
              openssl
              nixfmt
              taplo
              flyway
              opentofu
              awscli2
              ra-mux.packages.${system}.default
              circleci-cli
              cargo-audit
              gitleaks
              postgresql
              moreutils
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.cocoapods
              pkgs.xcpretty
            ]
            ++ scripts;
          shellHook = ''
            # export RUST_BACKTRACE=1
          '';
        };

        packages.server = rustPlatform.buildRustPackage {
          pname = "bochi-backend";
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
          name = "bochi-backend";
          # This tag is only used locally. ECR doesn't know about this.
          tag = "latest";

          contents = with pkgs; [
            dockerTools.caCertificates
            self.packages.${system}.server
          ];

          config = {
            Cmd = [ "${self.packages.${system}.server}/bin/bochi-backend" ];
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
          name = "bochi-migrations";
          tag = "latest";

          contents = with pkgs; [
            dockerTools.caCertificates
            flyway
            bash
            coreutils
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
              "PATH=${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.flyway}/bin"
            ];
          };
        };
      }
    );
}
