# SuxOS/nix — the shared reproducible dev-toolchain base

One pinned Nix flake the whole org composes on top of, so every clone — and CI — resolves the
**same** toolchain. Its reason to exist is a real bug: suxrouter CI built ucode from a floating
`jow-/ucode` tip that *accepted* `export function` module-export syntax the box's older stock
ucode *rejects*, so a whole class of drift shipped **invisibly** (green in CI, dark on the box)
and blacked out every sux LuCI app until [suxrouter#629](https://github.com/SuxOS/suxrouter/pull/629).
Pinning the toolchain — reproducibly, in one shared place — is what kills that class.

> **Scope of Nix (decided).** Nix is **not** a dotfile manager and **never** runs on the box
> (musl vs glibc, no systemd — it would defeat the router's core-clean posture). Its job here is
> exactly two things: **(1)** a reproducible dev/CI toolchain `devShell` (pinning ucode + friends),
> and **(2)** later, `pkgsStatic` static-musl builds of extra CLI tools pushed to a binary cache
> that the Mac and box *pull* (never build). glibc-OpenWrt was investigated and **rejected as a
> trap**. Generic on-box tools use Entware (`/opt` musl overlay), not Nix.

## Status — Level 1 (bootstrap)

- `flake.nix` — pinned nixpkgs + a `ucode-box` overlay (ucode built from the box's **exact**
  OpenWrt-25.12 commit `@85922056`, pinned as a flake *input* so its hash auto-locks) + a shared
  base `devShell` (`ucode-box` + `jq` + `shellcheck`) + a `checks` output.
- `.github/workflows/flake-check.yml` — **the verification loop.** This flake was authored on a
  Mac with **no local nix**, so its first `nix flake check` run on GitHub's x86_64-linux runners
  is what actually proves it evaluates and `ucode-box` builds. The CI generates `flake.lock` and
  uploads it as an artifact — commit that back to pin the inputs. (This mirrors the "let CI do the
  nix, the Mac just consumes devShells" split from the router research.)

**If the first CI run is red:** it's a bootstrap iteration, not a shipped-broken deliverable — the
likely culprits are the nixpkgs pin (swap `nixos-unstable` → a specific stable rev) or the
`ucode.overrideAttrs` recipe needing a build-input tweak for the newer src. Fix in a nix-having
session (or iterate via CI) and commit `flake.lock`.

## How a per-repo flake consumes this (Level-1 example)

suxrouter is the first intended consumer — a Level-1 devShell whose `ucode` is the box's exact
version, so local `scripts/check.sh` compile-checks against the same ucode CI ([#630](https://github.com/SuxOS/suxrouter/pull/630))
and the box do:

```nix
{
  inputs = {
    suxos-nix.url = "github:SuxOS/nix";
    nixpkgs.follows = "suxos-nix/nixpkgs";
    flake-utils.follows = "suxos-nix/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils, suxos-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = suxos-nix.lib.pkgsFor system; in {
        devShells.default = pkgs.mkShell {
          inputsFrom = [ suxos-nix.devShells.${system}.default ];  # shared base
          packages = [ pkgs.libjson-c ];                            # repo-specific extras
        };
      });
}
```

`nix develop` then drops you into a shell where `ucode -c` is the box's ucode. Not wired into
suxrouter yet — do that once this repo's `flake-check` is green (avoids coupling suxrouter's CI to
an unverified flake).

## Roadmap — Level 2 (deferred)

- **Static-musl tooling → binary cache.** `pkgsStatic` cross-builds of extra CLI tools built once
  in GH Actions (`x86_64-linux`), pushed to a binary cache (Cachix-hosted or self-hosted Attic on
  Fly.io), pulled by the Mac and rsynced to the box's `/opt` — never baked into the image/core.
- **nvfetcher auto-tracking** of the ucode pin against OpenWrt's `package/utils/ucode/Makefile`,
  so a box OS bump regenerates the rev/hash instead of a hand-edit.
- **Per-repo devShell adoption** across sux/suxlib as their toolchains stabilize.

## Invariants

- The `ucode-box` rev is the **single source of truth** for "the ucode the box runs." Keep it in
  lockstep with suxrouter `ci.yml`'s pin (both point at the box's OpenWrt-release commit).
- Bump the ucode rev only when the box's OpenWrt release moves — never to a floating upstream tip.
