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

NIMBLE_PATH="${HOME}/.nimble"
NIM_PATH="${NIMBLE_PATH}/bin"
export PATH=$NIM_PATH:$PATH
# Check if Nim is Presented
if ! command -v nimble > /dev/null; then
  echo "[ERROR] Nim is not installed or not configured on \$PATH"
  echo "        Nim can be installed from https://github.com/nim-lang/choosenim"
  exit 1
fi

# Remove Nimble Packages
rm -rf $NIMBLE_PATH/pkgs2/nogui*
rm -rf $NIMBLE_PATH/pkgs2/nopack*
# Compile NPainter Binary
nimble build -d:danger
nopack
