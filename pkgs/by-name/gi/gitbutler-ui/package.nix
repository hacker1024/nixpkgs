{ lib
, mkYarnPackage
, fetchYarnDeps
, fetchFromGitHub
}:

mkYarnPackage rec {
  pname = "gitbutler-ui";
  version = "0.10.24";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    rev = "release/${version}";
    hash = "sha256-09Ugtjs6AFGpLQQYxRBuNAvHomGfJQIEETl4jfpp7KU=";
  };

  sourceRoot = "${src.name}/gitbutler-ui";

  # The package.json must use spaces instead of upstream's tabs to pass Nixpkgs
  # CI.
  # To generate the Yarn lockfile, run `yarn install`.
  # There is no way to import the tagged pnpm lockfile, so make sure to test the
  # result thoughly as dependency versions may differ from the release.
  packageJSON = ./package.json;
  yarnLock = ./yarn.lock;
  offlineCache = fetchYarnDeps {
    inherit yarnLock;
    hash = "sha256-j/81555t6YOnragX8YSuQ3jNyNrX0KGV/dpP9Trv2hw=";
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

  meta = rec {
    description = "The UI for GitButler.";
    homepage = "https://gitbutler.com";
    downloadPage = homepage;
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${version}";
    license = lib.licenses.fsl-10-mit;
    maintainers = with lib.maintainers; [ hacker1024 ];
    platforms = with lib.platforms; all;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
