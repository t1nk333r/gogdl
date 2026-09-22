# Security Policy

## Supported versions

Only the image tagged `latest` and the image tagged with the current upstream
LGOGDownloader version are supported. Older version tags on
`ghcr.io/t1nk333r/gogdl` are kept for reproducibility and do not receive
rebuilds.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository (Security tab →
Report a vulnerability). Please do not open a public issue for something you
believe is exploitable.

## Build provenance

- The base image is a digest-pinned, supported Alpine release.
- Both source archives (LGOGDownloader and htmlcxx) are SHA-256 verified before
  extraction; the LGOGDownloader digest comes from the upstream release asset.
- The image runs as UID/GID 1000, not root.
- GitHub Actions are pinned to full commit SHAs and refreshed by Dependabot.
