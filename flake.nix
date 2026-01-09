{
  description = "tuicr-nvim - Neovim plugin for code review";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            lua-language-server
            luajitPackages.luacheck
            stylua
            neovim
            git
          ];

          shellHook = ''
            echo "tuicr-nvim development environment"
            echo "Available tools:"
            echo "  - lua-language-server (type checking)"
            echo "  - luacheck (static analysis)"
            echo "  - stylua (code formatting)"
            echo "  - neovim (testing)"
            echo ""
            echo "Run 'make' to run all checks and tests"
            echo "Run 'make test' to run tests only"
          '';
        };
      }
    );
}
