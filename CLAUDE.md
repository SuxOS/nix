# CLAUDE.md

Persistent notes for automated builders working in this repo.

## Gotchas

- **nodejs_20 is insecure (EOL) on the pinned `nixos-unstable` input.** `pkgs.nodejs_20`
  fails `nix build`/`nix flake check` at eval time with "Refusing to evaluate package
  ... marked as insecure". Use `pkgs.nodejs_22` (or whatever the current LTS is) for
  any new package/devShell that needs a Node runtime. Before adding a new package that
  reaches for a pinned runtime version, grep for it first (e.g. `pkgs.nodejs_20`) to
  confirm it isn't already flagged insecure on this nixpkgs pin — the fix is usually
  just bumping to the next LTS.
