{
  appimageTools,
  fetchurl,
  lib,
}: let
  pname = "orca";
  version = "1.4.200";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-yC2d31MkMeDaUexdGJmg4xWqu453/ORezOf61HM/yWo=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname src version;
  };
in
  appimageTools.wrapType2 {
    inherit pname src version;

    extraInstallCommands = ''
      install -m 444 -D ${appimageContents}/orca-ide.desktop $out/share/applications/orca.desktop
      install -m 444 -D ${appimageContents}/orca-ide.png $out/share/icons/hicolor/512x512/apps/orca-ide.png
      substituteInPlace $out/share/applications/orca.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=orca'
    '';

    meta = {
      description = "IDE for parallel agentic development";
      homepage = "https://github.com/stablyai/orca";
      license = lib.licenses.mit;
      mainProgram = "orca";
      platforms = ["x86_64-linux"];
    };
  }
