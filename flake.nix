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

        ra-multiplex-port = "27632";
        ra-config = ''
          instance_timeout = false 
          gc_interval = 10
          listen = ["127.0.0.1", ${ra-multiplex-port}]
          connect = ["127.0.0.1", ${ra-multiplex-port}]
          log_filters = "info"
          pass_environment = []
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
              ra
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
              ra-multiplex
              circleci-cli
              grafana-loki
              grafana
            ]
            ++ scripts;
          shellHook = ''
            export RUST_LOG=info
            # export RUST_BACKTRACE=1
            export RA_MULTIPLEX_PORT="${ra-multiplex-port}"
          '';
        };

        packages.server = pkgs.rustPlatform.buildRustPackage {
          pname = "habit-market-backend";
          version = "0.1.0";
          src = ./.;
          doCheck = false; # Run tests seperately

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
        packages.default = self.packages.${system}.server;
        packages.server-docker = pkgs.dockerTools.buildLayeredImage {
          name = "habit-market-backend";
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
