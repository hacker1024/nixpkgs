{ lib
, hostPlatform
, rustPlatform
, makeDesktopItem
, gitbutler-ui
, copyDesktopItems
, wrapGAppsHook
, pkg-config
, perl
, jq
, moreutils
, libsoup
, webkitgtk
, glib-networking
, libayatana-appindicator
, git
}:

let
  version = "0.10.27";

  buildArgs = {
    inherit (gitbutler-ui) version src;

    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "tauri-plugin-context-menu-0.7.0" = "sha256-/4eWzZwQtvw+XYTUHPimB4qNAujkKixyo8WNbREAZg8=";
        "tauri-plugin-log-0.0.0" = "sha256-uOPFpWz715jT8zl9E6cF+tIsthqv4x9qx/z3dJKVtbw=";
      };
    };

    RUSTC_BOOTSTRAP = 1; # GitButler depends on unstable Rust features.
    RUSTFLAGS = "--cfg tokio_unstable";
  };

  # Provides binaries used internally by gitbutler. These are bundled into the
  # app by tauri.
  gitbutler-git = rustPlatform.buildRustPackage (buildArgs // {
    pname = "gitbutler-git";
    buildAndTestSubdir = "gitbutler-git";

    # The tauri bundler requires that binaries to be bundled with the app have
    # system config suffixes.
    postInstall = ''
      for bin in "$out"/bin/*; do
        mv "$bin" "$bin-${hostPlatform.config}"
      done
    '';
  });
in
assert lib.assertMsg (version == gitbutler-ui.version) "The GitButler version does not match the GitButler UI version!";
rustPlatform.buildRustPackage (buildArgs // rec {
  pname = "gitbutler";

  nativeBuildInputs = [ copyDesktopItems wrapGAppsHook pkg-config perl jq moreutils ];

  buildInputs = [ libsoup webkitgtk glib-networking ];

  nativeCheckInputs = [ git ];

  buildAndTestSubdir = "gitbutler-app";

  postPatch = ''
    # Use the correct path to the prebuilt UI assets.
    substituteInPlace gitbutler-app/tauri.conf.json \
      --replace-fail '../gitbutler-ui/build' '${gitbutler-ui}'

    # Since `cargo build` is used instead of `tauri build`, configs are merged manually.
    #
    # Disable the updater, as it is not needed for Nixpkgs.
    #
    # Gitbutler's inject-git-binaries.sh does not run so gitbutler-git-* binaries are
    # not renamed with system config suffixes that tauri requires. Patch the
    # configuration to point to the binaries that we built with the necessary suffixes.
    jq --slurp '.[0] * .[1] | .tauri.updater.active = false | .tauri.bundle.externalBin |= map(sub("(?<bin>^gitbutler-git-.*)"; "${gitbutler-git}/bin/\(.bin)"))' \
      gitbutler-app/tauri.conf.json gitbutler-app/tauri.conf.release.json \
      | sponge gitbutler-app/tauri.conf.json

    # Patch library paths in dependencies.
    substituteInPlace "$cargoDepsCopy"/libappindicator-sys-*/src/lib.rs \
      --replace-fail 'libayatana-appindicator3.so.1' '${libayatana-appindicator}/lib/libayatana-appindicator3.so.1'
  '';

  postInstall = ''
    mv "$out"/bin/{gitbutler-app,'${meta.mainProgram}'}

    for size in 128x128@2x 128x128 32x32; do
      install -DT "gitbutler-app/icons/$size.png" "$out/share/icons/hicolor/$size/apps/gitbutler.png"
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "gitbutler";
      desktopName = "GitButler";
      genericName = "Git client";
      categories = [ "Development" ];
      comment = meta.description;
      exec = meta.mainProgram;
      icon = "gitbutler";
      terminal = false;
      type = "Application";
    })
  ];

  meta = gitbutler-ui.meta // {
    description = "A Git client for simultaneous branches on top of your existing workflow.";
    platforms = with lib.platforms; linux ++ darwin;
    mainProgram = "git-butler";
  };
})
