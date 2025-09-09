{
  description = "A Nix flake for the task-master-ai agentic orchestrator";

  # These are the external dependencies for our flake.
  # nixpkgs is the main Nix package collection.
  # flake-utils provides boilerplate for multi-system support.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # The outputs section defines what this flake provides (packages, apps, etc.).
  outputs = { self, nixpkgs, flake-utils }:
    # This function from flake-utils generates outputs for common systems (x86_64-linux, aarch64-darwin, etc.)
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Import nixpkgs for the specific system.
        pkgs = import nixpkgs { inherit system; };

        # This is the package definition for task-master-ai.
        # It's based on the standard buildNpmPackage function.
        task-master-ai = pkgs.buildNpmPackage (finalAttrs: {
          pname = "task-master-ai";
          version = "task-master-ai@0.26.0"; # This version will be automatically updated by the workflow

          # fetchFromGitHub is the standard fetcher for getting source from GitHub releases.
          src = pkgs.fetchFromGitHub {
            owner = "eyaltoledano";
            repo = "claude-task-master";
            # The 'rev' is derived from the version attribute above.
            rev = "v${finalAttrs.version}";
            # The hash ensures the source code is what we expect. It will also be auto-updated.
            hash = "sha256-AfufOTq4ZR8dL5PwbkyrzF1VWc7hTjyHEqO8OMFooII=";
          };

          # This hash locks the NPM dependencies. It must be updated manually if the
          # upstream project changes its dependencies. The CI log will provide the new hash.
          npmDepsHash = "sha256-WjPFg/jYTbxrKNzTyqb6e0Z+PLPg6O2k8LBIELwozo8=";

          # We don't need to run the `npm build` command as per the original derivation.
          dontNpmBuild = true;

          # These are build-time dependencies needed to install the NPM packages.
          nativeBuildInputs = [ pkgs.nodejs pkgs.nodejs.pkgs.npm ];

          # Metadata about the package.
          meta = with pkgs.lib; {
            description = "Node.js agentic AI workflow orchestrator";
            homepage = "https://task-master.dev";
            changelog = "https://github.com/eyaltoledano/claude-task-master/blob/v${finalAttrs.version}/CHANGELOG.md";
            license = licenses.mit;
            mainProgram = "task-master-ai";
            maintainers = [ maintainers.repparw ]; # Feel free to change this
            platforms = platforms.all;
          };
        });
      in
      {
        # Defines the package that can be built with `nix build .#`
        packages.default = task-master-ai;

        # Defines the application that can be run with `nix run .#`
        apps.default = {
          type = "app";
          program = "${task-master-ai}/bin/task-master-ai";
        };

        # Defines a development shell with useful tools, accessible via `nix develop`
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nix-update
            pkgs.nodejs
            pkgs.nodejs.pkgs.npm
            task-master-ai # Add this line
          ];
        };
      }
    );
}
