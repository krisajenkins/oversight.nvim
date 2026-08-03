# @update github-release jj-vcs/jj
final: prev: {
  jujutsu = prev.jujutsu.overrideAttrs (oldAttrs: rec {
    version = "0.43.0";
    src = prev.fetchFromGitHub {
      owner = "jj-vcs";
      repo = "jj";
      rev = "v${version}";
      hash = "sha256-XgBq2ZN34iWlwKVgW7Syr46KUdt7pJuSDd/J6QWJwwQ=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-bEvpTd+FAHrD+CZN7+AuCuThyJ5LtufQR7OrGpjrWK0=";
    };

    meta = oldAttrs.meta // {
      description = "Git-compatible VCS (custom version ${version})";
    };
  });
}

