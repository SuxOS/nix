{
  description = "SuxOS shared Nix base — pinned, reproducible dev toolchain + overlays. Per-repo flakes import this so every clone (and CI) resolves the SAME toolchain.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # ucode pinned to the EXACT commit OpenWrt 25.12.3 ships and the box (owl-tegu) runs
    # (PKG_SOURCE_DATE 2026-01-16). This is the whole point of the shared base: nixpkgs' own
    # ucode is older and a floating jow-/ucode tip ACCEPTS `export function` syntax the box
    # REJECTS — the drift that shipped invisibly and blacked out every sux LuCI app until
    # suxrouter#629. A flake INPUT (not fetchFromGitHub) means the hash auto-locks in
    # flake.lock — no manually-computed NAR hash. Bump this rev only in lockstep with the
    # box's OpenWrt release (mirror of suxrouter ci.yml's pin, #630).
    ucode-src = {
      url = "github:jow-/ucode/85922056ef7abeace3cca3ab28bc1ac2d88e31b1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ucode-src }:
    let
      # ── Shared overlays (per-repo flakes get these by importing self.overlays.default) ──
      # ucode-box: ucode built from the box's exact source, so a devShell's `ucode -c`
      # matches CI (#630) and the live box — the toolchain-level version of the drift fix.
      ucodeOverlay = final: prev: {
        ucode-box = prev.ucode.overrideAttrs (_old: {
          version = "box-85922056";
          src = ucode-src;
        });
      };
    in
    {
      # Consumed by per-repo flakes: `overlays = [ suxos-nix.overlays.default ]`.
      overlays.default = ucodeOverlay;

      # A helper per-repo flakes can call to get a pkgs set already carrying the shared
      # overlays, so they don't re-import nixpkgs + overlays by hand.
      lib.pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = [ ucodeOverlay ];
        };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = self.lib.pkgsFor system;
      in
      {
        packages.ucode-box = pkgs.ucode-box;

        # Base OCI image for org workflow runners (builders/fixers/evals — stateless, bursty,
        # per-run: the image-shaped case, see issue #3). Layered so tool bumps only invalidate
        # their own layer. Every tool version is pinned by nixpkgs' own flake.lock, same as the
        # rest of this repo — no ad-hoc version floats. nodejs_22 (current LTS): nodejs_20 is EOL
        # and nixpkgs marks it insecure, which fails eval outright.
        packages.ci-image = pkgs.dockerTools.buildLayeredImage {
          name = "ci-base";
          tag = "latest";
          contents = [
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.cacert
            pkgs.git
            pkgs.gh
            pkgs.jq
            pkgs.ripgrep
            pkgs.nodejs_22
            pkgs.python3
          ];
          config = {
            Env = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
            Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
          };
        };

        # Level-1 shared base devShell. Per-repo devShells compose on top:
        #   devShells.default = pkgs.mkShell { inputsFrom = [ suxos-nix.devShells.${system}.default ]; packages = [ ... ]; };
        devShells.default = pkgs.mkShell {
          packages = [ pkgs.ucode-box pkgs.jq pkgs.shellcheck ];
          shellHook = ''
            echo "SuxOS base devShell — box-pinned ucode + jq + shellcheck (Level 1)"
          '';
        };

        # `nix flake check` runs this — the CI verification loop (this repo has no local-nix
        # author; see README). Proves the ucode-box override actually builds.
        checks.ucode-box-builds = pkgs.ucode-box;
      });
}
