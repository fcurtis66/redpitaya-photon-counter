#!/usr/bin/env bash
# Deploy bitstream + C server to a Red Pitaya board.
# Usage: ./scripts/deploy.sh <board-alias>      e.g. ./scripts/deploy.sh board-a
#
# Requires:
#   - SSH config entry for the alias (see docs/hardware/deploy.md)
#   - SSH key auth set up (no password prompts)
#
# Intentionally minimal. Fill in the TODOs once upstream's file names and
# compiled-binary locations are confirmed.

set -euo pipefail

# ---- args ----
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <board-alias>   (e.g. board-a, board-b)" >&2
    exit 1
fi
BOARD="$1"

# ---- paths ----
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIT="${REPO_ROOT}/bitstreams/latest.bit"       # TODO: confirm naming convention
SERVER_BIN="${REPO_ROOT}/host/build/tdc_server" # TODO: confirm once C server build is set up
REMOTE_DIR="/root/photon_counter"

# ---- sanity ----
if [[ ! -f "$BIT" ]]; then
    echo "Bitstream not found at $BIT — build it in Vivado first." >&2
    exit 1
fi

# ---- info ----
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Deploying commit $GIT_SHA to $BOARD"

# ---- push files ----
ssh "$BOARD" "mkdir -p $REMOTE_DIR"
rsync -avz --progress "$BIT" "$BOARD:$REMOTE_DIR/latest.bit"
if [[ -f "$SERVER_BIN" ]]; then
    rsync -avz --progress "$SERVER_BIN" "$BOARD:$REMOTE_DIR/tdc_server"
fi
echo "$GIT_SHA" | ssh "$BOARD" "cat > $REMOTE_DIR/COMMIT"

# ---- load bitstream into PL ----
# TODO: confirm whether Adamic's flow loads via /dev/xdevcfg or fpgautil.
# Original method (xdevcfg) — works on Zynq-7000:
ssh "$BOARD" "cat $REMOTE_DIR/latest.bit > /dev/xdevcfg"

echo "Done. Bitstream loaded on $BOARD (commit $GIT_SHA)."
echo "Next: ssh $BOARD, then run ./PLclock and start the C server."
