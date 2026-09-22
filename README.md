# LGOGDownloader container image

This repository builds a container image from the latest stable
[LGOGDownloader release](https://github.com/Sude-/lgogdownloader/releases).

GitHub Actions checks upstream daily. When it finds a release that has not yet
been published, it verifies the release archive, builds the image, runs the
runtime verification (`scripts/verify-image.sh`), and only then pushes:

```text
ghcr.io/t1nk333r/gogdl:<version>
ghcr.io/t1nk333r/gogdl:latest
```

Pull requests build and verify the image without logging in or publishing.
A weekly rebuild refreshes the pinned base image and runtime for the current
release. Pushes that change the Dockerfile or workflow rebuild the current
upstream release. The workflow can also be run manually from the Actions tab.

## Pull the image

```shell
docker pull ghcr.io/t1nk333r/gogdl:latest
```

## Check the version

```shell
docker run --rm ghcr.io/t1nk333r/gogdl:latest --version
```

## Local directories

Create three directories on the host and make them writable by UID/GID 1000
(the container runs as user `lgogdownloader`, UID/GID 1000, and never as root):

```shell
mkdir -p ~/gogdl/{config,cache,downloads}
sudo chown -R 1000:1000 ~/gogdl
```

Inside the container `XDG_CONFIG_HOME=/config`, `XDG_CACHE_HOME=/cache`, and
the working directory is `/downloads`, so login state and the download cache
persist in the first two mounts and games land in the third.

## Login

```shell
docker run --rm -it \
  -v "$HOME/gogdl/config:/config" \
  -v "$HOME/gogdl/cache:/cache" \
  -v "$HOME/gogdl/downloads:/downloads" \
  ghcr.io/t1nk333r/gogdl --login
```

## Download

```shell
docker run --rm -it \
  -v "$HOME/gogdl/config:/config" \
  -v "$HOME/gogdl/cache:/cache" \
  -v "$HOME/gogdl/downloads:/downloads" \
  ghcr.io/t1nk333r/gogdl --download --language ar,en
```

`--download` fetches all platforms, Arabic where available, and English always;
the wrapper inside the image points LGOGDownloader at `/downloads` so no
`--directory` flag is needed.

## Requirements and behaviour

- The container runs as UID/GID 1000. If the host directories are owned by a
  different user, pass `--user "$(id -u):$(id -g)"` and keep the mounted paths
  writable by that UID.
- Upstream releases are discovered daily; the image for a new release is built,
  runtime-verified, and published as `<version>` and `latest`.
- The base image is a digest-pinned supported Alpine release, and both source
  archives (LGOGDownloader and htmlcxx) are SHA-256 verified before extraction.
- Actions are pinned to full commit SHAs and refreshed weekly by Dependabot.
