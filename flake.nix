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
          # This tag is only used locally. ECR doesn't know about this.
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
        
        packages.flyway-docker = pkgs.dockerTools.buildLayeredImage {
          name = "habit-market-migrations";
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
