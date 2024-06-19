#!/bin/sh
set -e

# Check if System is Linux
if [ "$(uname -s)" != "Linux" ]; then
  echo "[ERROR] this build script is only for native Linux"
  exit 1
fi

echo ""
echo "------ COMPILING NPAINTER ------"
echo ""

NIMBLE_PATH="~/.nimble/bin"
export PATH="$PATH:$NIMBLE_PATH"
# Check if Nim is Presented
if ! command -v nimble &> /dev/null; then
  echo "[ERROR] Nim is not installed or not configured on \$PATH"
  echo "        Nim can be installed from https://github.com/dom96/choosenim"
  exit 1
fi

# Compile NPainter Binary
nimble build -d:danger
nopack
