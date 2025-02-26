{
  lib,
  buildFHSEnv,
  callPackage,
  makeDesktopItem,
  runtimeShell,
  runCommand,
  unstick,
  quartus-prime-lite,
  libfaketime,
  pkgsi686Linux,
  supportedDevices ? [
    "Arria II"
    "Cyclone V"
    "Cyclone IV"
    "Cyclone 10 LP"
    "MAX II/V"
    "MAX 10 FPGA"
  ],
  unwrapped ? callPackage ./quartus.nix { inherit unstick supportedDevices; },
  extraProfile ? "",
}:

let
  desktopItem = makeDesktopItem {
    name = "quartus-prime-lite";
    exec = "quartus";
    icon = "quartus";
    desktopName = "Quartus";
    genericName = "Quartus Prime";
    categories = [ "Development" ];
  };
in
# I think questa_fse/linux/vlm checksums itself, so use FHSUserEnv instead of `patchelf`
buildFHSEnv rec {
  pname = "quartus-prime-lite"; # wrapped
  inherit (unwrapped) version;

  targetPkgs =
    pkgs: with pkgs; [
      (runCommand "ld-lsb-compat" { } (
        ''
          mkdir -p "$out/lib"
          ln -sr "${glibc}/lib/ld-linux-x86-64.so.2" "$out/lib/ld-lsb-x86-64.so.3"
        ''
      ))
      # quartus requirements
      glib
      xorg.libICE
      xorg.libSM
      xorg.libXau
      xorg.libXdmcp
      xorg.libXScrnSaver
      libudev0-shim
      bzip2
      brotli
      zlib
      expat
      dbus
      # qsys requirements
      xorg.libXtst
      xorg.libXi
      dejavu_fonts
      gnumake
      # eclipse requirements
      jre8
    ];

  # these libs are installed as 64 bit, plus as 32 bit when multiArch is true
  multiPkgs =
    pkgs:
    with pkgs;
    let
      # This seems ugly - can we override `libpng = libpng12` for all `pkgs`?
      freetype = pkgs.freetype.override { libpng = libpng12; };
      fontconfig = pkgs.fontconfig.override { inherit freetype; };
    in
    [
      # common requirements
      libpng12
      freetype
      fontconfig
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      libxcrypt-legacy
    ];

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/64x64/apps
    ln -s ${desktopItem}/share/applications/* $out/share/applications
    ln -s ${unwrapped}/quartus/adm/quartusii.png $out/share/icons/hicolor/64x64/apps/quartus.png

    progs_to_wrap=(
      "${unwrapped}"/quartus/bin/*
      "${unwrapped}"/quartus/sopc_builder/bin/qsys-{generate,edit,script}
      "${unwrapped}"/nios2eds/nios2_command_shell.sh
      "${unwrapped}"/nios2eds/bin/*/*
    )

    wrapper=$out/bin/${pname}
    progs_wrapped=()
    for prog in ''${progs_to_wrap[@]}; do
        relname="''${prog#"${unwrapped}/"}"
        bname="$(basename "$relname")"
        wrapped="$out/$relname"
        progs_wrapped+=("$wrapped")
        mkdir -p "$(dirname "$wrapped")"
        echo "#!${runtimeShell}" >> "$wrapped"
        NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=1
        # SOURCE_DATE_EPOCH blocklist for programs that are known to hang/break
        # with fixed/static clock.
        case "$bname" in
            jtagd|quartus_pgm|quartus)
                NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=0
                ;;
        esac
        echo "export NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=$NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK" >> "$wrapped"
        echo "exec $wrapper $prog \"\$@\"" >> "$wrapped"
    done

    cd $out
    chmod +x ''${progs_wrapped[@]}
    # link into $out/bin so executables become available on $PATH
    ln --symbolic --relative --target-directory ./bin ''${progs_wrapped[@]}
  '';

  profile =
    ''
      # Implement the SOURCE_DATE_EPOCH specification for reproducible builds
      # (https://reproducible-builds.org/specs/source-date-epoch).
      # Require opt-in with NIXPKGS_QUARTUS_REPRODUCIBLE_BUILD=1 for now, in case
      # the blocklist is incomplete.
      if [ -n "$SOURCE_DATE_EPOCH" ] && [ "$NIXPKGS_QUARTUS_REPRODUCIBLE_BUILD" = 1 ] && [ "$NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK" = 1 ]; then
          export LD_LIBRARY_PATH="${
            lib.makeLibraryPath [
              libfaketime
              pkgsi686Linux.libfaketime
            ]
          }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export LD_PRELOAD=libfaketime.so.1''${LD_PRELOAD:+:$LD_PRELOAD}
          export FAKETIME_FMT="%s"
          export FAKETIME="$SOURCE_DATE_EPOCH"
      fi
    ''
    + extraProfile;

  # Run the wrappers directly, instead of going via bash.
  runScript = "";

  passthru = {
    inherit unwrapped;
    tests = {
      buildSof =
        runCommand "quartus-prime-lite-test-build-sof"
          {
            nativeBuildInputs = [ quartus-prime-lite ];
            env.NIXPKGS_QUARTUS_REPRODUCIBLE_BUILD = "1";
          }
          ''
            cat >mydesign.vhd <<EOF
            library ieee;
            use ieee.std_logic_1164.all;

            entity mydesign is
            port (
                in_0: in std_logic;
                in_1: in std_logic;
                out_1: out std_logic
            );
            end mydesign;

            architecture dataflow of mydesign is
            begin
                out_1 <= in_0 and in_1;
            end dataflow;
            EOF

            quartus_sh --flow compile mydesign

            if ! [ -f mydesign.sof ]; then
                echo "error: failed to produce mydesign.sof" >&2
                exit 1
            fi

            sha1sum mydesign.sof > "$out"
          '';
    };
  };

  inherit (unwrapped) meta;
}
