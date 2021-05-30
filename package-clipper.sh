#!/bin/bash

FFMPEG_VERSION=4.4
RELEASE_DIR=releases
PKG_DIR=clipper-release

VERSION=$(git describe --match "clipper-*" --long --tags | sed 's/clipper-//;s/\([^-]*-g\)/r\1/;s/-/./g;s/\.g[[:alnum:]]\+//;s/\.r0$//')

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
wget -qO ffmpeg.7z "https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-${FFMPEG_VERSION}-essentials_build.7z"
mkdir -p ${PKG_DIR}/bin
7z e -o"${PKG_DIR}/bin/" ffmpeg.7z "ffmpeg-${FFMPEG_VERSION}-essentials_build/bin/"{ffmpeg.exe,ffprobe.exe}
echo

echo "Creating release package for Windows..."
cp clipper/clipper-windows.lua ${PKG_DIR}/autoload/clipper.lua
( cd "${PKG_DIR}" && zip -r "../${RELEASE_DIR}/clipper-${VERSION}-windows.zip" ./ )
echo

echo "Removing build artifacts..."
rm -rvf ${PKG_DIR} ffmpeg.7z
