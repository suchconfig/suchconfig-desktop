#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -d "$SCRIPT_DIR/../phoenix-app/_build/prod/rel/suchconfig_desktop" ]; then
    RELEASE_DIR="$SCRIPT_DIR/../phoenix-app/_build/prod/rel/suchconfig_desktop"
elif [ -d "$SCRIPT_DIR/../Resources/suchconfig_desktop" ]; then
    RELEASE_DIR="$SCRIPT_DIR/../Resources/suchconfig_desktop"
elif [ -d "$SCRIPT_DIR/../../Resources/_build/prod/rel/suchconfig_desktop" ]; then
    RELEASE_DIR="$SCRIPT_DIR/../../Resources/_build/prod/rel/suchconfig_desktop"
else
    echo "ERROR: Could not find Elixir release directory" >&2
    exit 1
fi

export RELEASE_ROOT="$RELEASE_DIR"

unset RELEASE_NODE
unset RELEASE_DISTRIBUTION

echo "Starting Phoenix server from: $RELEASE_DIR" >&2

exec "$RELEASE_DIR/bin/suchconfig_desktop" start

