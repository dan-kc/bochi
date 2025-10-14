{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-old.url = "github:NixOS/nixpkgs/886bdc4543438773a6fb50ea3f6ac48e72517a54";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      nixpkgs-old,
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
        pkgs-old = import nixpkgs-old {
          inherit system;
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
              postgresql
              grafana
              pkgs-old.localstack
            ]
            ++ scripts;
          shellHook = ''
            export RUST_LOG=info
            # export RUST_BACKTRACE=1
            export RA_MULTIPLEX_PORT="27632"
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
