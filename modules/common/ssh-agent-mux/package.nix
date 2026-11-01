{
  lib,
  rustPlatform,
  fetchFromGitHub,
  openssh,
  python3,
}:
rustPlatform.buildRustPackage {
  pname = "ssh-agent-mux";
  version = "0.1.0-unstable-2026-11-01";

  src = fetchFromGitHub {
    owner = "chipturner";
    repo = "ssh-agent-muxer";
    rev = "b4e6dfeef19309d27e0ea499b64db30577cacd50";
    hash = "sha256-8Wb6+IEMoifUBnet85dD31I62m6fXPXHwJLpQpFT0vo=";
  };

  cargoHash = "sha256-ZGbf4Av/eM67lq9VOjLbP826oKuOymE6epoX5Z/9ioE=";

  # Keep startup and identity refresh restricted to explicit backend sockets.
  patches = [./explicit-agents.patch];

  # Integration tests require live agents and host-specific OpenSSH behavior.
  cargoTestFlags = ["--lib"];

  doInstallCheck = true;
  nativeInstallCheckInputs = [openssh python3];
  installCheckPhase = ''
    runHook preInstallCheck
    python3 ${./test.py} "$out/bin/ssh-agent-mux"
    runHook postInstallCheck
  '';

  meta = {
    description = "Merge SSH agents behind a stable local socket";
    homepage = "https://github.com/chipturner/ssh-agent-muxer";
    license = lib.licenses.mit;
    mainProgram = "ssh-agent-mux";
    platforms = lib.platforms.linux;
  };
}
