{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  pkg-config,
  pcsclite,
  libbsd,
  libedit,
  zlib,
}: let
  # Pivy patches OpenSSH internals and builds against this LibreSSL release.
  opensshSource = fetchurl {
    url = "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.0p1.tar.gz";
    hash = "sha256-AhoucJoO30JQsSVr1anlAEEakN3avqgw7VnO+Q652Fw=";
  };
  libresslSource = fetchurl {
    url = "https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/libressl-4.0.0.tar.gz";
    hash = "sha256-TYQZVfCsw9/HHQ49018oOvRhIiNQ4mhD/qlzHAJGoeQ=";
  };
in
  stdenv.mkDerivation {
    pname = "pivy";
    version = "0.12.1";

    src = fetchFromGitHub {
      owner = "arekinath";
      repo = "pivy";
      rev = "47babc4fabe5c0051bb1d50a7b7b7a43ae890c13";
      hash = "sha256-HFAuGR9Vr1s2VOIS9sCUU+T6tV1wguhodJPdOuNT1nI=";
    };

    nativeBuildInputs = [pkg-config];
    buildInputs = [pcsclite libbsd libedit zlib];

    # Supply upstream's dependency tarballs without network access during build.
    postPatch = ''
      tar xf ${opensshSource}
      mv openssh-10.0p1 openssh
      tar xf ${libresslSource}
      mv libressl-4.0.0 libressl
      touch .openssh.extract .libressl.extract
      patchShebangs openssh libressl
    '';

    dontConfigure = true;
    enableParallelBuilding = true;
    buildFlags = ["pivy-agent" "pivy-tool" "pivy-box"];

    installPhase = ''
      runHook preInstall
      install -Dm755 pivy-agent "$out/bin/pivy-agent"
      install -Dm755 pivy-tool "$out/bin/pivy-tool"
      install -Dm755 pivy-box "$out/bin/pivy-box"
      runHook postInstall
    '';

    meta = {
      description = "PIV smart-card tools and SSH agent";
      homepage = "https://github.com/arekinath/pivy";
      license = [lib.licenses.mpl20 lib.licenses.bsd2];
      mainProgram = "pivy-agent";
      platforms = lib.platforms.linux;
    };
  }
