#!/usr/bin/env bash

# Requires ARG_USER to be authenticated with X11 via xauth (or xhost)

## Add a group for the shared display resources
# `sudo groupadd shared-display`

## Add both users to the shared-display group
# `sudo usermod --append --groups shared-display <user>`

## After adding your user to the shared-display group, you must log-off and back in,
## or do `su - $USER` to have the group assignments take effect

set -e -o pipefail

ARG_NETNS=$1
ARG_USER=$2
export ARG_COMMAND=${@:3}

display_number=$(echo $DISPLAY | awk 'match($0,/^:([0-9]+)$/, a) { print a[1] }' | grep .)
display="/tmp/.X11-unix/X$display_number"

cleanup() {
    if [ -n "$WAYPIPE_PID" ] && kill -0 "$WAYPIPE_PID" 2>/dev/null; then echo "closing waypipe: $WAYPIPE_PID"; kill -SIGINT "$WAYPIPE_PID"; fi
    if [ -n "$WAYPIPE_DIR" ]; then echo "removing WAYPIPE_DIR: $WAYPIPE_DIR"; rm -rf -- "$WAYPIPE_DIR"; fi
}
trap cleanup EXIT

WAYPIPE_DIR=$(mktemp -d /tmp/waypipe-"$ARG_NETNS"-"$ARG_USER"-XXXXX)
export WAYPIPE_DIR
chmod 774 "$WAYPIPE_DIR"
WAYPIPE="$WAYPIPE_DIR/waypipe"
export WAYPIPE
waypipe -s "$WAYPIPE" client & WAYPIPE_PID=$!
until [ -S "$WAYPIPE" ]; do
    if ! kill -0 "$WAYPIPE_PID" 2>/dev/null; then echo >&2 "waypipe closed before making socket"; exit 1; fi
    sleep 0.01
done

chgrp shared-display "$WAYPIPE_DIR" "$WAYPIPE" "$display"
chmod g+w "$WAYPIPE" "$display"

sudo -E ip netns exec "$ARG_NETNS" su - "$ARG_USER" --whitelist-environment=ARG_COMMAND,DISPLAY,WAYPIPE_DIR,WAYPIPE -c "$(cat <<'EOF_USER'
set -e -o pipefail
XDG_RUNTIME_DIR="$WAYPIPE_DIR-xdg"
export XDG_RUNTIME_DIR
mkdir -m 0700 "$XDG_RUNTIME_DIR"
trap 'rm -rf -- "$XDG_RUNTIME_DIR"' EXIT
waypipe -s "$WAYPIPE" server -- env $ARG_COMMAND
EOF_USER
)"
