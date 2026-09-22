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
# Mount preparation and cleanup run through the image itself with a --user 0
# override, so the script needs no host root (the CI runner is not root). The
# write probe and the ownership assertions run INSIDE the container, and the
# container asserts its own bind mounts through /proc/self/mounts first — an
# assertion that would be meaningless without the mounts is not allowed to
# pass silently.
tmp="$(mktemp -d)"
# The helper hands ownership to UID 1000 during the probe; hand it back to the
# caller before removal or the sticky-bit /tmp refuses the delete (the CI
# runner is not root, and the failed rm would fail the whole job after the
# verification has already passed).
caller_uid="$(id -u)"
cleanup() {
  docker run --rm -v "$tmp:/work" --entrypoint sh --user 0 "$image" \
    -c "chown -R ${caller_uid}: /work" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/config" "$tmp/cache" "$tmp/downloads"
docker run --rm -v "$tmp:/work" --entrypoint sh --user 0 "$image" \
  -c 'chown -R 1000:1000 /work'

docker run --rm \
  -v "$tmp/config:/config" \
  -v "$tmp/cache:/cache" \
  -v "$tmp/downloads:/downloads" \
  "$image" --version >/dev/null ||
  fail "the version invocation against mounted paths failed"

probe_output="$(docker run --rm \
  -v "$tmp/config:/config" \
  -v "$tmp/cache:/cache" \
  -v "$tmp/downloads:/downloads" \
  --entrypoint sh "$image" \
  -c '
    set -e
    id -u
    for mount in /config /cache /downloads; do
      grep -q " $mount " /proc/self/mounts ||
        { echo "FATAL: $mount is not a mount in this container"; exit 3; }
    done
    mkdir -p /config/lgogdownloader /cache/lgogdownloader
    touch /config/lgogdownloader/probe /cache/lgogdownloader/probe /downloads/probe
    stat -c "%u %n" /config/lgogdownloader /config/lgogdownloader/probe /cache/lgogdownloader/probe /downloads/probe
  ' 2>&1)" ||
  { printf '%s\n' "$probe_output" >&2; fail "the UID 1000 write probe against the mounted paths failed"; }
printf '%s\n' "$probe_output"

while read -r owner path; do
  [ "$owner" = "$runtime_uid" ] ||
    fail "$path is owned by $owner, want $runtime_uid"
done <<<"$probe_output"

echo "Image verification passed: $image (LGOGDownloader $version)"
