# Workflow-runner environments: images, not a VPC

**Decision:** org workflow runners (builders, fixers, evals) use lightweight nix-built OCI
images, published to GHCR. No VPC / persistent environment.

## Why

- The workload is CI/workflow runners — stateless, bursty, per-run. That's the image-shaped
  case, not the persistent-environment case.
- A VPC buys nothing today: no long-lived services outside Cloudflare Workers, no private-network
  dependency. It would add standing cost and patch surface for no runtime need.
- Nix already pins this org's toolchain (see `flake.nix`). `nix build .#ci-image` produces a
  reproducible runner image — node, python3, gh, git, ripgrep, jq — so the "works locally, fails
  in CI" drift class (the reason this repo exists, see `README.md`) doesn't reappear at the
  runner-image layer either.

## What shipped (this issue)

1. `packages.ci-image` in `flake.nix` — `dockerTools.buildLayeredImage`, every tool pinned by
   this repo's `flake.lock` (no floating versions).
2. `.github/workflows/ci-image.yml` — builds the image and pushes `ghcr.io/<org>/ci-base:latest`
   and `:<short-sha>` on main, triggered off `flake-check`'s completion so a red gate never
   publishes.
3. A pilot smoke-test job (`pilot-smoke-test` in the same workflow) that loads the built image
   and exercises the pinned toolchain (`git`, `gh`, `jq`, `rg`, `node`, `python3`) as a runtime-
   parity check.

## Deferred

- Migrating a real workflow caller to `container: ghcr.io/<org>/ci-base:latest` — do this once
  the pilot has a few green runs and the image is actually published, so the first adopter isn't
  also the first tester.
- Migrating all workflows — follow-up after the pilot's speed/parity numbers are in.
- Any VPC build. **Revisit trigger:** a service that can't live on Cloudflare Workers and needs a
  private network.
