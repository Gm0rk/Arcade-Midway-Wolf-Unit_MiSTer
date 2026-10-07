#!/bin/sh
# run_ref.sh - MAME reference for sim/dcs (fresh CMOS every run)
#   run_ref.sh <wtunit binary> <rom dir> <set> <out dir> <end frame> <full from> [press]
# Writes <out>/ref.txt (the DSP trace without the main loop's DAC buffer
# waits, collapsed on the way: the whole trace is far too big to keep),
# <out>/events.txt for the simulator, <out>/host.txt and <out>/dac.txt.
# <full from>: frame from which the trace has all the registers (0: from
# power-on).
mame=$1; roms=$2; set=$3; out=$4; endf=$5; full=$6; press=$7
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
mkdir -p "$out"
mkfifo "$tmp/fifo"
python3 "$here/../../tools/dcs_trace.py" events - "$out/ref.txt" "$out/events.txt" 3<>"$tmp/fifo" <&3 &
reader=$!
DCS_TRACE="$tmp/fifo" DCS_PIPE=1 DCS_HOST="$out/host.txt" DCS_DAC="$out/dac.txt" DCS_END=$endf DCS_FULL=$full WU_PRESS=$press \
	"$mame" "$set" -rompath "$roms" -nvram_directory "$tmp/nv" -cfg_directory "$tmp/cfg" \
	-debug -debugger none -video none -sound none -nothrottle -skip_gameinfo \
	-autoboot_script "$here/../../tools/lua/dcs_trace.lua" > "$tmp/log" 2>&1
wait $reader
rm -rf "$tmp"
