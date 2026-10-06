#!/bin/sh
# Host unit tests for the logic that does not need the game (Foundation only).
#   sh tests/run.sh
set -e
cd "$(dirname "$0")/.."
OUT=/tmp/pikminauto_tests
clang++ -std=gnu++17 -fobjc-arc -Wall -Werror -DPK_TEST -framework Foundation \
    -ISources/Support -ISources/Model -ISources/Game -ISources/IL2CPP -ISources/App -ISources/Rpc -Itests \
    $(cat tests/sources.txt | sed 's#^#Sources/#') tests/TestKit.mm tests/main.mm $(ls tests/test_*.mm) -o "$OUT"
"$OUT"
