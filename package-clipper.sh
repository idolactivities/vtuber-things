#!/bin/bash

FFMPEG_VERSION=4.2.2
RELEASE_DIR=releases
PKG_DIR=clipper-release

VERSION=$(git describe --match "clipper-*" --long --tags | sed 's/clipper-//;s/\([^-]*-g\)/r\1/;s/-/./g;s/\.g[[:alnum:]]\+//')

echo "Current release: ${VERSION}"
mkdir -p ${RELEASE_DIR}
echo

echo "Packaging Clipper libraries..."
mkdir -p ${PKG_DIR}/{autoload,include/clipper}
cp -v clipper.lua ${PKG_DIR}/autoload/
git ls-files clipper/*.lua | xargs -I{} cp -v "{}" ${PKG_DIR}/include/clipper/
echo

echo "Creating release package for Linux/OS X..."
( cd "${PKG_DIR}" && tar czvf "../${RELEASE_DIR}/clipper-${VERSION}-linux.tar.gz" ./ )
echo

echo "Downloading ffmpeg Windows binaries..."
wget -qO ffmpeg.zip "https://ffmpeg.zeranoe.com/builds/win64/static/ffmpeg-${FFMPEG_VERSION}-win64-static.zip"
mkdir -p ${PKG_DIR}/bin
unzip -jx ffmpeg.zip "ffmpeg-${FFMPEG_VERSION}-win64-static/bin/"{ffmpeg.exe,ffprobe.exe} -d release/bin/
echo

echo "Creating release package for Windows..."
cp clipper/clipper-windows.lua ${PKG_DIR}/autoload/clipper.lua
( cd "${PKG_DIR}" && zip -r "../${RELEASE_DIR}/clipper-${VERSION}-windows.zip" ./ )
echo

echo "Removing build artifacts..."
rm -rvf ${PKG_DIR} ffmpeg.zip
