#!/bin/sh
# run_ref.sh - MAME reference frames for one set (fresh CMOS every run)
#   run_ref.sh <wtunit binary> <rom dir> <out root> <set> <frames> [press]
# press: WU_PRESS form, e.g. 200:IN0:0010:5
mame=$1; roms=$2; out=$3; set=$4; frames=$5; press=$6
tmp=$(mktemp -d)
rm -rf "$out/$set"
WU_SET=$set WU_OUT=$out WU_FRAMES=$frames WU_PRESS=$press \
	"$mame" "$set" -rompath "$roms" -nvram_directory "$tmp/nv" -cfg_directory "$tmp/cfg" \
	-video none -sound none -nothrottle -skip_gameinfo \
	-autoboot_script "$(dirname "$0")/../../tools/lua/ref_trace.lua" > "$tmp/log" 2>&1
rm -rf "$tmp"
