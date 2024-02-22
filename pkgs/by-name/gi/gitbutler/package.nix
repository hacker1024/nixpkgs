{ lib
, rustPlatform
, buildGoModule
, stdenv
, stdenvNoCC
, fetchFromGitHub
, makeDesktopItem
, copyDesktopItems
, wrapGAppsHook
, gitbutler
, darwin
, cacert
, dbus
, esbuild
, freetype
, gdk-pixbuf
, glib-networking
, gtk3
, pkg-config
, perl
, jq
, libappindicator-gtk3
, librsvg
, libsoup
, moreutils
, nodePackages
, openssl
, webkitgtk
, git
}:
rustPlatform.buildRustPackage {
  pname = "gitbutler";
  version = "0.10.11";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    rev = "release/${gitbutler.version}";
    hash = "sha256-Y8LurSQKhjHX3RUiuOdHtPkZK5NKmx3eqQ5NGtnhMlY=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "tauri-plugin-context-menu-0.5.0" = "sha256-ftvGrJoQ4YHVYyrCBiiAQCQngM5Em15VRllqSgHHjxQ=";
      "tauri-plugin-single-instance-0.0.0" = "sha256-xJd1kMCnSlTy/XwPWAtYPBsUFIW9AiBFgnmWQ3BpFeo=";
    };
  };

  pnpmDeps = stdenvNoCC.mkDerivation {
    pname = "${gitbutler.pname}-pnpm-deps";
    inherit (gitbutler) version src;

    nativeBuildInputs = [ cacert jq moreutils nodePackages.pnpm ];

    env.pnpmPatch = builtins.toJSON {
      pnpm.supportedArchitectures = {
        # not all of these systems are supported yet,
        # but this should future proof things for a bit
        os = [ "linux" "darwin" ];
        cpu = [ "x64" "arm64" ];
      };
    };

    postPatch = ''
      for packageJson in package.json gitbutler-ui/package.json; do
        mv "$packageJson" "$packageJson".orig
        jq --raw-output ". * $pnpmPatch" "$packageJson".orig > "$packageJson"
      done
    '';

    installPhase = ''
      export HOME=$(mktemp -d)

      pnpm config set store-dir $out
      pnpm install --frozen-lockfile --no-optional --ignore-script
      rm -rf $out/v3/tmp

      for f in $(find $out -name "*.json"); do
        sed -i -E -e 's/"checkedAt":[0-9]+,//g' $f
        jq --sort-keys . $f | sponge $f
      done
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-aAnuoQzoW6OqTs7wuir8QpFEV2snayJQcEEw6p6IaRo=";
  };

  nativeBuildInputs = [ copyDesktopItems wrapGAppsHook pkg-config perl jq moreutils nodePackages.pnpm ];

  buildInputs = [ openssl ] ++ lib.optionals stdenv.isLinux [
    dbus
    freetype
    gtk3
    gdk-pixbuf
    glib-networking
    librsvg
    libsoup
    webkitgtk
  ] ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
    AppKit
    CoreServices
    Security
    WebKit
  ]);

  nativeCheckInputs = [ git ];

  buildAndTestSubdir = "gitbutler-app";

  env = {
    ESBUILD_BINARY_PATH = lib.getExe (esbuild.override {
      buildGoModule = args:
        buildGoModule (args // rec {
          version = "0.18.20";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${version}";
            hash = "sha256-mED3h+mY+4H465m02ewFK/BgA1i/PQ+ksUNxBlgpUoI=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        });
    });

    RUSTC_BOOTSTRAP = 1; # GitButler depends on unstable Rust features.

    RUSTFLAGS = "--cfg tokio_unstable";
  };

  doCheck = false;

  postPatch = ''
    # Disable the updater, as it is not needed for Nixpkgs.
    jq --slurp '.[0] * .[1] | .tauri.updater.active = false' gitbutler-app/tauri.conf{,.release}.json | sponge gitbutler-app/tauri.conf.json
  '';

  preBuild = ''
    export HOME=$(mktemp -d)
    export STORE_PATH=$(mktemp -d)

    cp -r ${gitbutler.pnpmDeps}/* "$STORE_PATH"

    chmod -R +w "$STORE_PATH"
    pnpm config set store-dir "$STORE_PATH"
    pnpm install --offline --frozen-lockfile --no-optional --ignore-script
    pnpm run prepare
    pnpm run build
  '';

  postInstall = ''
    mv "$out"/bin/{gitbutler-app,${gitbutler.meta.mainProgram}}

    for size in 128x128@2x 128x128 32x32; do
      install -DT "gitbutler-app/icons/$size.png" "$out/share/icons/hicolor/$size/apps/gitbutler.png"
    done
  '';

  preFixup = lib.optionalString stdenv.isLinux ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libappindicator-gtk3 ]}
    )
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "gitbutler";
      desktopName = "GitButler";
      genericName = "Git client";
      categories = [ "Development" ];
      comment = gitbutler.meta.description;
      exec = gitbutler.meta.mainProgram;
      icon = "gitbutler";
      terminal = false;
      type = "Application";
    })
  ];

  meta = with lib; {
    description = "A Git client for simultaneous branches on top of your existing workflow.";
    homepage = "https://gitbutler.com";
    downloadPage = gitbutler.meta.homepage;
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${gitbutler.version}";
    license = licenses.fsl-10-mit;
    maintainers = with maintainers; [ hacker1024 getchoo ];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "git-butler";
    sourceProvenance = with sourceTypes; [ fromSource ];
  };
}
