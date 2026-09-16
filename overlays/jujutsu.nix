# @update github-release jj-vcs/jj
final: prev: {
  jujutsu = prev.jujutsu.overrideAttrs (oldAttrs: rec {
    version = "0.45.1";
    src = prev.fetchFromGitHub {
      owner = "jj-vcs";
      repo = "jj";
      rev = "v${version}";
      hash = "sha256-nqMd9kj6TH/6kTZ8a9XDPBESwCIOMa7c/0TgbEXoo3o=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-rt3mq7+Z+7Z1Y+XUWva+UsrDcVeZs6VjXnhAL0iyP20=";
    };

    meta = oldAttrs.meta // {
      description = "Git-compatible VCS (custom version ${version})";
    };
  });
}

