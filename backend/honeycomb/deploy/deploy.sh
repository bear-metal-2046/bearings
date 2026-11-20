#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--uploaded] SSH_HOST [PUBLIC_HOSTNAME]\n' "$0"
  printf 'Use --uploaded to install ~/bundle already on the VM. Omit it to build and upload a new release.\n'
}

uploaded=false
case ${1:-} in
  -h|--help) usage; exit 0 ;;
  --uploaded) uploaded=true; shift ;;
esac
ssh_host=${1:-}
domain=${2:-}
if [[ $# -lt 1 || $# -gt 2 || ! $ssh_host =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*$ || ! $domain =~ ^[A-Za-z0-9.-]*$ ]]; then
  usage >&2
  exit 1
fi

deploy_dir=$(cd -- "$(dirname -- "$0")" && pwd)
honeycomb_dir=$(dirname -- "$deploy_dir")
if [[ $uploaded == false ]]; then
  (
    cd "$honeycomb_dir/../.."
    dart pub get
    dart pub global activate dart_frog_cli 1.2.14
    cd "$honeycomb_dir"
    dart pub global run dart_frog_cli:dart_frog build
    cd build
    dart build cli --target bin/server.dart --output release
  )
fi

staging=$(ssh "$ssh_host" 'mktemp -d /tmp/honeycomb-upload.XXXXXX')
if [[ ! $staging =~ ^/tmp/honeycomb-upload\.[A-Za-z0-9]+$ ]]; then
  printf 'Could not create a staging directory on %s.\n' "$ssh_host" >&2
  exit 1
fi
trap 'ssh "$ssh_host" "rm -r -- $staging" || true' EXIT
scp "$deploy_dir/install.sh" "$ssh_host:$staging/install.sh"

if [[ $uploaded == true ]]; then
  remote_bundle='"$HOME/bundle"'
else
  scp -r "$honeycomb_dir/build/release/bundle" "$ssh_host:$staging/bundle"
  remote_bundle="'$staging/bundle'"
fi
ssh -t "$ssh_host" "sudo bash '$staging/install.sh' $remote_bundle '$domain'"
