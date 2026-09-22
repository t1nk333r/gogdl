#!/usr/bin/env bash
# Runtime verification for the LGOGDownloader container image.
#
# Usage: scripts/verify-image.sh [image] [expected-version]
#
# Asserts the runtime contract the Dockerfile promises (non-root UID/GID 1000,
# entrypoint/CMD, HOME/XDG environment, workdir, volumes) and exercises the
# binary: --version, the default help invocation, and a run against temporary
# bind mounts whose files must end up owned by UID 1000.
set -euo pipefail

image="${1:-gogdl:verify}"
version="${2:-3.18}"
runtime_uid=1000

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- static contract from the image metadata ---------------------------------
user="$(docker image inspect --format '{{.Config.User}}' "$image")" ||
  fail "cannot inspect $image"
[ -n "$user" ] || fail "the image has no configured user"
[ "$user" != "root" ] || fail "the image runs as root"

entrypoint="$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")"
[ "$entrypoint" = '["/usr/bin/lgogdownloader"]' ] ||
  fail "entrypoint is $entrypoint, want [\"/usr/bin/lgogdownloader\"]"

cmd="$(docker image inspect --format '{{json .Config.Cmd}}' "$image")"
[ "$cmd" = '["--help"]' ] || fail "default command is $cmd, want [\"--help\"]"

env="$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image")"
grep -qx 'HOME=/home/lgogdownloader' <<<"$env" ||
  fail "HOME is not /home/lgogdownloader"
grep -qx 'XDG_CONFIG_HOME=/config' <<<"$env" ||
  fail "XDG_CONFIG_HOME is not /config"
grep -qx 'XDG_CACHE_HOME=/cache' <<<"$env" ||
  fail "XDG_CACHE_HOME is not /cache"

workdir="$(docker image inspect --format '{{.Config.WorkingDir}}' "$image")"
[ "$workdir" = "/downloads" ] || fail "workdir is $workdir, want /downloads"

volumes="$(docker image inspect --format '{{json .Config.Volumes}}' "$image")"
for volume in /config /cache /downloads; do
  grep -q "\"$volume\"" <<<"$volumes" || fail "$volume is not a declared volume"
done

ids="$(docker run --rm --entrypoint id "$image" -u)" ||
  fail "cannot run id in $image"
grep -qx "$runtime_uid" <<<"$ids" ||
  fail "runtime uid is not $runtime_uid: $ids"

# the name must resolve too: same UID, the lgogdownloader account
name="$(docker run --rm --entrypoint id "$image" -un)" ||
  fail "cannot run id -un in $image"
[ "$name" = "lgogdownloader" ] ||
  fail "runtime user is $name, want lgogdownloader"

# --- runtime behaviour --------------------------------------------------------
version_output="$(docker run --rm "$image" --version 2>/dev/null)" ||
  fail "--version invocation failed"
grep -q -- "$version" <<<"$version_output" ||
  fail "--version did not report $version: $version_output"

help_output="$(docker run --rm "$image" 2>/dev/null)" ||
  fail "the default invocation failed"
grep -qi 'lgogdownloader' <<<"$help_output" ||
  fail "the default invocation did not display help"

# --- persistence: mounted paths are writable by UID 1000 and stay theirs ------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/config" "$tmp/cache" "$tmp/downloads"
chown -R "$runtime_uid:$runtime_uid" "$tmp"

docker run --rm \
  -v "$tmp/config:/config" \
  -v "$tmp/cache:/cache" \
  -v "$tmp/downloads:/downloads" \
  "$image" --version >/dev/null ||
  fail "the version invocation against mounted paths failed"

docker run --rm \
  -v "$tmp/config:/config" \
  -v "$tmp/cache:/cache" \
  -v "$tmp/downloads:/downloads" \
  --entrypoint sh "$image" \
  -c 'mkdir -p /config/lgogdownloader /cache/lgogdownloader && touch /config/lgogdownloader/probe /cache/lgogdownloader/probe /downloads/probe' ||
  fail "UID $runtime_uid cannot write the mounted paths"

for probe in "$tmp/config/lgogdownloader" "$tmp/cache/lgogdownloader"; do
  [ -d "$probe" ] || fail "$probe was not created by the container"
  owner="$(stat -c '%u' "$probe")"
  [ "$owner" = "$runtime_uid" ] ||
    fail "$probe is owned by $owner, want $runtime_uid"
done

echo "Image verification passed: $image (LGOGDownloader $version)"
