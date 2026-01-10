final: prev: {
  jujutsu = prev.jujutsu.overrideAttrs (oldAttrs: rec {
    version = "0.36.0";
    src = prev.fetchFromGitHub {
      owner = "jj-vcs";
      repo = "jj";
      rev = "v${version}";
      hash = "sha256-HGMzNXm6vWKf/RHPwB/soDqxAvCOW1J6BPs0tsrEuTI=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-jai0FNuCUcgN+ZmmYgbFrMK1Z1vcv21wALkEb74h7H0=";
    };

    meta = oldAttrs.meta // {
      description = "Git-compatible VCS (custom version ${version})";
    };
  });
}

