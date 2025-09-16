{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      flake-utils,
      fenix,
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
        scripts = import ./scripts.nix { inherit pkgs; };
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
              rust-analyzer
              nil
              nixfmt-rfc-style
              taplo
              flyway
            ]
            ++ scripts;
          shellHook = ''
            # If localstack and db is not running then start it
            start

            # Init secret management for local deployment
            export AWS_ENDPOINT_URL_SECRETSMANAGER="http://localhost:4566"
            export AWS_ACCESS_KEY_ID="test"
            export AWS_SECRET_ACCESS_KEY= "test"
            export AWS_DEFAULT_REGION="eu-west-1"
            export AWS_SECRETS_PREFIX="" # use "test-" in test runners
            export DATABASE_NAME="habit_market" # use "test_habit_market" in test runnners
            # export RUST_BACKTRACE=1
            export RUST_LOG=info
            export LOG_DESTINATION=logs # If unset then it will be stdout only

            # cargo doc
            # xdg-open ./target/doc/habit_market_backend/index.html
          '';
        };

        packages.server = pkgs.rustPlatform.buildRustPackage {
          pname = "habit-market-backend";
          version = "0.1.0";
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
          ];

          buildInputs = with pkgs; [
            openssl
          ];

        };
        # packages.default = self.packages.${system}.server;

        packages.server-docker = pkgs.dockerTools.buildLayeredImage {
          name = "habit-market-server";
          tag = "latest";

          contents = with pkgs; [
            dockerTools.caCertificates
            curl
            self.packages.${system}.server
          ];

          config = {
            Cmd = [ "${self.packages.${system}.server}/bin/habit-market-backend" ];
            WorkingDir = "/app";
            ExposedPorts = {
              "80/tcp" = { };
            };
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      }
    );
}
