# source this file. Paths are specific to the machine used for the campaign; adjust for reproduction.
export PLAN_ROOT="D:/Amir/Business/SUR/NewSur/Plan"
export EVID="$PLAN_ROOT/testing-evidence/besu-live-test-v25b-2026-11-19"
export NODE_PATH="$PLAN_ROOT/contracts-tests/node_modules"           # reference, no reinstall: hardhat 2.29.1, ethers 6.17.0
export SUR25_BUILD="${SUR25_BUILD:-C:/Users/Amir/AppData/Local/Temp/claude/f77a4166e619fc45/a9ca4925-d40c-46f3-b1b0-5401de3bb777/scratchpad/build25b}"
export SUR25_RUN="${SUR25_RUN:-C:/Users/Amir/AppData/Local/Temp/claude/f77a4166e619fc45/a9ca4925-d40c-46f3-b1b0-5401de3bb777/scratchpad/run25b}"
export MSYS_NO_PATHCONV=1
hh() { (cd "$EVID" && node "$NODE_PATH/hardhat/internal/cli/cli.js" --config scripts/hh/hardhat.config.js "$@"); }
