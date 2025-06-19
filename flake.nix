{
  description = "A Nix flake for the task-master-ai agentic orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        task-master-ai = pkgs.buildNpmPackage (finalAttrs: {
          pname = "task-master-ai";
          version = "0.16.2";
          src = pkgs.fetchFromGitHub {
            owner = "eyaltoledano";
            repo = "claude-task-master";
            rev = "v${finalAttrs.version}";
            hash = "sha256-AfufOTq4ZR8dL5PwbkyrzF1VWc7hTjyHEqO8OMFooII=";
          };
          npmDepsHash = "sha256-WjPFg/jYTbxrKNzTyqb6e0Z+PLPg6O2k8LBIELwozo8=";
          dontNpmBuild = true;
          nativeBuildInputs = [ pkgs.nodejs pkgs.nodePackages.npm ];
          meta = with pkgs.lib; {
            description = "Node.js agentic AI workflow orchestrator";
            homepage = "https://task-master.dev";
            changelog = "https://github.com/eyaltoledano/claude-task-master/blob/v${finalAttrs.version}/CHANGELOG.md";
            license = licenses.mit;
            mainProgram = "task-master-ai";
            maintainers = [ maintainers.repparw ];
            platforms = platforms.all;
          };
        });
      in
      {
        packages.default = task-master-ai;
        apps = {
          default = { # This is task-master-ai
            type = "app";
            program = "${task-master-ai}/bin/task-master-ai";
          };
          task-master = {
            type = "app";
            program = "${task-master-ai}/bin/task-master";
          };
          task-master-mcp = {
            type = "app";
            program = "${task-master-ai}/bin/task-master-mcp";
          };
        };
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs
            pkgs.nodePackages.npm
            pkgs.nix-update
          ];
        };
      }
    );
}
