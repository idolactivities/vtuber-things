#!/bin/bash

FFMPEG_VERSION=4.2.2

echo "Current tag: $(git describe --abbrev=0)"

echo "Downloading ffmpeg Windows binaries..."
wget -qO ffmpeg.zip "https://ffmpeg.zeranoe.com/builds/win64/static/ffmpeg-${FFMPEG_VERSION}-win64-static.zip"
mkdir -p release/bin
unzip -jx ffmpeg.zip "ffmpeg-${FFMPEG_VERSION}-win64-static/bin/"{ffmpeg.exe,ffprobe.exe} -d release/bin/

echo "Packaging Clipper for Windows..."
cp clipper/clipper-windows.lua release/clipper.lua
( cd release/ && zip -r ../clipper.zip ./ )

echo "Removing build artifacts..."
rm -rvf release/ ffmpeg.zip
