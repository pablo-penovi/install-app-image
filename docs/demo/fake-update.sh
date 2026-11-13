#!/usr/bin/env bash
# fake-update.sh ID NAME ICON TO TOTAL_MB ASSET [MB_PER_TICK]
#
# Simulates an update for the GIFs in docs/: writes progress/<ID>.json in the
# format of progress_write() in installappimage, stepping through the same
# phases every 0.5 s, and ends with result "ok". The DMS plugin then
# auto-clears it 3 s after every update has succeeded. Touches no AppImage.
set -eu
D=$HOME/.local/state/installappimage/progress; mkdir -p "$D"
id=$1 name=$2 icon=$3 to=$4 total=$(( $5*1024*1024 )) asset=$6 speed=${7:-9}
log=()
w() { # phase done result reason
  local lj; lj=$(printf '%s\n' "${log[@]: -4}" | jq -R . | jq -sc .)
  jq -nc --arg name "$name" --arg icon "$icon" --arg to "$to" --arg phase "$1" --argjson done "$2" --argjson total "$total" \
    --argjson log "$lj" --arg result "${3-}" --arg reason "${4-}" \
    '{name:$name,icon:$icon,to:$to,phase:$phase,done:$done,total:$total,log:$log,result:(if $result=="" then null else $result end),reason:$reason}' >"$D/.$id.tmp"
  mv -f "$D/.$id.tmp" "$D/$id.json"
}
step() { log+=("$1"); w "$1" "${2:-0}"; }
step "Checking for updates"; sleep 1.2
step "Downloading $asset"
d=0; while (( d < total )); do d=$(( d + speed*1024*1024 )); (( d > total )) && d=$total; w "Downloading $asset" $d; sleep 0.5; done
step "Verifying the download" $total; sleep 1
step "Reading the new menu entry" $total; sleep 0.7
step "Installing $to" $total; sleep 0.8
w "Installing $to" $total ok "Updated to $to."
