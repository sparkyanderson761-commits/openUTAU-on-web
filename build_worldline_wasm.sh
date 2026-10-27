#!/usr/bin/env bash
# Builds WORLDLINE-R (WORLD analysis/synthesis) to WebAssembly.
# Needs: emscripten (emcc), git, patch.  Needs internet (fetches WORLD, spline, libnpy).
# Usage:  ./build_worldline_wasm.sh /path/to/OpenUtau-master
# Output: ./out/worldline.js  (wasm is embedded, so this ONE file is all you upload)
set -euo pipefail

OU="$(cd "${1:-.}" && pwd)"
CPP="$OU/cpp"
[ -d "$CPP/worldline" ] || { echo "Can't find $CPP/worldline. Pass the OpenUtau repo root."; exit 1; }
command -v emcc >/dev/null || { echo "emcc not found. Install emscripten: https://emscripten.org/docs/getting_started/downloads.html"; exit 1; }

W="$PWD/_deps"; OUT="$PWD/out"; mkdir -p "$W" "$OUT"

# fetch <name> <repo-url> <commit>
fetch() {
  [ -d "$W/$1/.git" ] && return 0
  mkdir -p "$W/$1" && ( cd "$W/$1" && git init -q && git remote add origin "$2" \
    && git fetch -q --depth 1 origin "$3" && git checkout -q FETCH_HEAD )
}

# Same versions the Bazel build pins (cpp/WORKSPACE.bazel)
fetch world  https://github.com/mmorise/World.git     f8dd5fb289db6a7f7f704497752bf32b258f9151
fetch spline https://github.com/ttk592/spline.git     5894beaf91e9adbfdbe5c6c9a1c60770e380e8e8
fetch npy    https://github.com/llohse/libnpy.git     v1.0.1

# Apply OpenUtau's patches (once)
[ -f "$W/world/.patched" ]  || { ( cd "$W/world"  && patch -p1 < "$CPP/third_party/world.patch"  ) && touch "$W/world/.patched"; }
[ -f "$W/spline/.patched" ] || { ( cd "$W/spline" && patch -p1 < "$CPP/third_party/spline.patch" ) && touch "$W/spline/.patched"; }

# pyin (method 2) is not needed for Worldline-R, so it is stubbed out
mkdir -p "$W/stub"
cat > "$W/stub/pyin.h" <<'EOF'
typedef struct { int nhop; } pyin_config;
pyin_config pyin_init(int nhop);
double* pyin_analyze(pyin_config c, double* x, int nx, int fs, int* nfrm);
EOF
cat > "$W/stub/pyin_stub.cpp" <<'EOF'
extern "C" {
#include "pyin.h"
}
extern "C" pyin_config pyin_init(int nhop) { pyin_config c; c.nhop = nhop; return c; }
extern "C" double* pyin_analyze(pyin_config, double*, int, int, int* nfrm) {
  *nfrm = 2; return new double[2]{0.0, 0.0};
}
EOF

# libnpy keeps its header in include/ ; spline.h is in spline/src/
NPY_INC="$W/npy/include"; [ -d "$NPY_INC" ] || NPY_INC="$W/npy"

EXPORTS='["_malloc","_free","_F0FrameCount","_F0","_DecodeMgc","_DecodeBap","_InitAnalysisConfig","_WorldAnalysisF0In","_WorldSynthesisSampleCount","_WorldSynthesis"]'

emcc -O3 -std=c++17 -DNDEBUG \
  -I"$W/world/src" -I"$CPP" -I"$W/spline/src" -I"$NPY_INC" -I"$W/stub" \
  "$W"/world/src/*.cpp \
  "$CPP/worldline/worldline.cpp" \
  "$CPP/worldline/common/vec_utils.cpp" \
  "$CPP/worldline/f0/dio_estimator.cpp" \
  "$CPP/worldline/f0/dio_ss_estimator.cpp" \
  "$CPP/worldline/f0/harvest_estimator.cpp" \
  "$CPP/worldline/f0/pyin_estimator.cpp" \
  "$CPP/worldline/model/continuous_noise.cpp" \
  "$CPP/worldline/model/effects.cpp" \
  "$W/stub/pyin_stub.cpp" \
  -o "$OUT/worldline.js" \
  -s MODULARIZE=1 -s EXPORT_NAME=WorldlineModule \
  -s ALLOW_MEMORY_GROWTH=1 -s INITIAL_MEMORY=67108864 \
  -s ENVIRONMENT=web,worker -s SINGLE_FILE=1 \
  -s EXPORTED_FUNCTIONS="$EXPORTS" \
  -s EXPORTED_RUNTIME_METHODS='["HEAPF64","HEAPF32","HEAP32","HEAPU8"]'

ls -lh "$OUT/worldline.js"
echo "Done. Upload out/worldline.js"
