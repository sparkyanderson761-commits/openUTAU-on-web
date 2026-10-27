#!/usr/bin/env bash
# Builds moresampler2 (resampler + wavtool, one binary) to WebAssembly.
# Needs: emscripten (emcc).  No internet needed: every library is inside the repo.
# Usage:  ./build_moresampler2_wasm.sh /path/to/moresampler2-main
# Output: ./out/moresampler2.js  (wasm embedded: this ONE file is all you upload)
#
# Source list verified with a native gcc build + test render (C4 from a 220 Hz tone
# came out at ~260 Hz, as expected).
set -euo pipefail

R="$(cd "${1:-.}" && pwd)"; L="$R/libs"
[ -f "$R/moresampler2.c" ] || { echo "Can't find moresampler2.c in $R"; exit 1; }
command -v emcc >/dev/null || { echo "emcc not found. Install emscripten: https://emscripten.org/docs/getting_started/downloads.html"; exit 1; }

OBJ="$PWD/_obj"; OUT="$PWD/out"; rm -rf "$OBJ"; mkdir -p "$OBJ" "$OUT"
VER="$(tr -d '[:space:]' < "$R/VERSION")"
INC="-I$L -I$L/libllsm -I$L/ciglet -I$L/libpyin -I$L/libgvps -I$L/libpyin/libgvps"
CF="-O3 -std=gnu99 -DFP_TYPE=float -DMORESAMPLER2_VERSION=\"$VER\" -w"

for f in moresampler2.c wavtool.c utils.c \
  libs/ciglet/ciglet.c libs/ciglet/fast_median.c libs/ciglet/wavfile.c libs/ciglet/fftsg_h.c \
  libs/libgvps/gvps_full.c libs/libgvps/gvps_obsrv.c libs/libgvps/gvps_sampled.c libs/libgvps/gvps_variable.c \
  libs/libpyin/pyin.c libs/libpyin/yin.c libs/libpyin/math-funcs.c \
  libs/libllsm/container.c libs/libllsm/frame.c libs/libllsm/dsputils.c libs/libllsm/llsmutils.c \
  libs/libllsm/layer0.c libs/libllsm/layer1.c libs/libllsm/coder.c libs/libllsm/llsmrt.c; do
  emcc -c $CF $INC "$R/$f" -o "$OBJ/$(echo "$f" | tr '/' '_').o"
done

# libpyin and ciglet both define wavread/wavwrite; rename pyin's copy to avoid a clash
emcc -c $CF -Dwavread=pyin_wavread -Dwavwrite=pyin_wavwrite $INC "$L/libpyin/matlabfunctions.c" -o "$OBJ/pyin_matlabfunctions.o"

emcc -O3 "$OBJ"/*.o -o "$OUT/moresampler2.js" \
  -s MODULARIZE=1 -s EXPORT_NAME=Moresampler2Module \
  -s INVOKE_RUN=0 -s EXIT_RUNTIME=0 -s FORCE_FILESYSTEM=1 \
  -s ALLOW_MEMORY_GROWTH=1 -s INITIAL_MEMORY=134217728 -s STACK_SIZE=5242880 \
  -s ENVIRONMENT=web,worker -s SINGLE_FILE=1 \
  -s EXPORTED_RUNTIME_METHODS='["callMain","FS"]'

ls -lh "$OUT/moresampler2.js"
echo "Done. Upload out/moresampler2.js"
