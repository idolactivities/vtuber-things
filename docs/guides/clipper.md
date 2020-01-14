[« back](../index.md)

# Clipper

Clipper is a handy script that allows you to create subtitled (and unsubtitled) clips from a longer video, directly from Aegisub.

## Installation

1. Download `clipper.zip`
2. Navigate to `%APPDATA%\Aegisub\automation\autoload` (you can paste that directly into the Windows Explorer navigation bar)
3. Extract the contents of the zip file directly into the `autoload` folder. Your file structure should look like this:  

    ```
    Aegisub
    │
    └──automation
       │
       └──autoload
           │  clipper.lua
           │
           └──bin
                  ffmpeg.exe
                  ffprobe.exe
    ```

    That is, `clipper.lua` should be in the `autoload` folder, and the `autoload` folder should contain a `bin` folder which contains `ffmpeg.exe` and `ffprobe.exe`.
4. Restart Aegisub, and you should see "Clipper" when you open the "Automation" menu.

## Usage

Under construction