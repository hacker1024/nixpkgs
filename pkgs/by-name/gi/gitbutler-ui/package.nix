{ lib
, mkYarnPackage
, fetchYarnDeps
, fetchFromGitHub
}:

mkYarnPackage rec {
  pname = "gitbutler-ui";
  version = "0.10.27";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    rev = "release/${version}";
    hash = "sha256-Cbvb3mT4XuonB3oluaqXICP/5OMOHJBb5fceTJH1gDs=";
  };

  sourceRoot = "${src.name}/gitbutler-ui";

  # The package.json must use spaces instead of upstream's tabs to pass Nixpkgs
  # CI.
  #
  # There is a branch of pnpm-lock-export that has been updated to work on
  # gitbutler's pnpm-lock.yaml file. To generate an updated yarn.lock run:
  #
  #     $ nix run github:hallettj/pnpm-lock-export?ref=v0.5.0 -- --schema yarn.lock@v1
  #
  packageJSON = ./package.json;
  yarnLock = ./yarn.lock;
  offlineCache = fetchYarnDeps {
    inherit yarnLock;
    hash = "sha256-ilU8t2jj7w41PyGazZvnKCvQ5EMeo4CsZL0hxNeXQ04=";
  };

  preConfigure = ''
    chmod u+w -R "$NIX_BUILD_TOP"
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$(mktemp -d)"
    yarn --offline prepare
    yarn --offline build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    cp -r deps/@gitbutler/ui/build "$out"

    runHook postInstall
  '';

  distPhase = "true";

  meta = {
    description = "Git client for simultaneous branches on top of your existing workflow";
    homepage = "https://gitbutler.com";
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${version}";
    license = lib.licenses.fsl-10-mit;
    maintainers = with lib.maintainers; [ hacker1024 ];
    platforms = lib.platforms.all;
  };
}
