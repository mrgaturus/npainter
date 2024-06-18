#!/bin/sh
set -e

# Check MSYS2 MinGW Environment
if [ $MSYSTEM != "MINGW64" ]; then
  echo "[ERROR] this build script is only for MSYS2 MinGW-w64"
  exit 1
fi

echo ""
echo "------ INSTALLING DEPENDENCIES ------"
echo ""

# Configure MSYS2 Dependencies
pacman -S --needed --noconfirm \
  git \
  base-devel \
  mingw-w64-x86_64-toolchain \
  mingw-w64-x86_64-gdk-pixbuf2 \
  mingw-w64-x86_64-freetype \
  mingw-w64-x86_64-wintab-sdk

echo ""
echo "------ COMPILING NOPACK ------"
echo ""

# Append PATH to nimble folder
NIMBLE_PATH="${HOMEPATH}\.nimble"
export PATH="$PATH:$NIMBLE_PATH\bin"
# XXX: nimble install don't create proper links for nim compile
nimble install https://github.com/mrgaturus/nopack
NOPACK=$(find "$NIMBLE_PATH\pkgs2" -name "nopack.exe" | head -n 1)
cp $NOPACK "$NIMBLE_PATH\bin"

echo ""
echo "------ COMPILING NPAINTER ------"
echo ""

# Compile NPainter Pass-1
nimble build -d:danger
nopack

# Assemble Release Folder
rm -rf release
mkdir -p release
mkdir -p release/npainter.shared
cp npainter.exe release/npainter.exe
cp -r data release/npainter.data

SHARED="release/npainter.shared"
SXS="" # Copy DLL Libraries and Prepare WinSXS DLLs
DLLS=$(ldd "npainter.exe" | grep '=> /' | awk '{print $3}' | sort -u | grep ${MSYSTEM_PREFIX})
for DLL in $DLLS
do
  cp "${DLL}" ${SHARED}/$(basename $DLL)
  SXS="${SXS}<file name=\"$(basename $DLL)\"/>"
done

# Assemble SXS Manifest from Template and Store on Shared
SXS=$(cat pack/winsxs.manifest | sed "s@\[build_win32.sh\]@${SXS}@g")
echo "$SXS" > ${SHARED}/npainter.shared.manifest
cp pack/win32.manifest ${SHARED}/win32.manifest

# Create Resource File and Compile Again
echo "1 24 win32.manifest" >> ${SHARED}/win32.rc
windres -o win32.o ${SHARED}/win32.rc
# Compile NPainter Pass-2
nimble build -d:danger --passL:win32.o --app:gui
cp npainter.exe release/npainter.exe
rm npainter.exe win32.o
