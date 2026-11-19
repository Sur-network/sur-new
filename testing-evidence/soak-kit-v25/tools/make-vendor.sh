#!/bin/bash
# Rebuilds vendor/node_modules.tgz (ethers 6.17.0 + its runtime dependencies, pruned) from an existing node_modules folder.
# Only needed if you want to refresh the vendored libraries; the server never runs this.
#   NODE_MODULES_SRC=/path/to/node_modules tools/make-vendor.sh
set -eu
SRC="${NODE_MODULES_SRC:?set NODE_MODULES_SRC to a node_modules folder containing ethers 6.x}"
T="$(mktemp -d)"; mkdir -p "$T/node_modules"
cp -r "$SRC/ethers" "$T/node_modules/ethers"
rm -rf "$T/node_modules/ethers"/{dist,lib.esm,src.ts,rollup.config.mjs,node_modules}
for d in @adraffy @noble aes-js ws tslib; do cp -r "$SRC/$d" "$T/node_modules/$d"; done
( cd "$T/node_modules" && find . \( -name '*.d.ts' -o -name '*.map' -o -name '*.d.mts' \) -delete && rm -rf @noble/hashes/esm @noble/curves/esm @noble/hashes/src @noble/curves/src )
NODE_PATH="$T/node_modules" node -e "const e=require('ethers');console.log('ethers',e.version,'ok')"
tar -czf "$(dirname "$0")/../vendor/node_modules.tgz" -C "$T" node_modules
ls -l "$(dirname "$0")/../vendor/node_modules.tgz"
