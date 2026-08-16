# Source this to set up the environment for the owcc -bcpm86 one-command build:
#     . contrib/ravn/cpm86-clib/env.sh
# then:
#     owcc -bcpm86 -march=i186 -mcmodel=s prog.c -o PROG.CMD
#
# It exposes the native osxa64 tools under the bare names owcc drives them by
# (wcc/wasm/wlink/wlib), points WATCOM at the tree (so wlink resolves
# %WATCOM%/lib286/cpm86) and WLINK_LNK at the config that defines `system
# cpm86` (without it wlink reports "undefined system name: cpm86").
#
# NOTE: run contrib/ravn/cpm86-clib/build.sh once (and after every clean.sh) to
# regenerate lib286/cpm86/{cstartcpm.obj,clibs.lib} from source.
_OW="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
_B="$_OW/bld"
_BIN="${TMPDIR:-/tmp}/owcc-cpm86-bin"
mkdir -p "$_BIN"
ln -sf "$_B/cc/i86/osxa64/binbuild/wcc.exe" "$_BIN/wcc"
ln -sf "$_B/wasm/osxa64/wasm.exe"           "$_BIN/wasm"
ln -sf "$_B/wl/osxa64/wlink.exe"            "$_BIN/wlink"
ln -sf "$_B/nwlib/osxa64/wlib.exe"          "$_BIN/wlib"
ln -sf "$_B/wcl/owcc/osxa64/owcc.exe"       "$_BIN/owcc"
cp     "$_B/wcl/owcc/osxa64/specs.owc"      "$_BIN/specs.owc"
export PATH="$_BIN:$PATH"
export WATCOM="$_OW"
export OWROOT="$_OW"
export WLINK_LNK="$_B/wl/lnk/osxa64/wlink.lnk"
echo "owcc -bcpm86 environment ready (WATCOM=$WATCOM)"
