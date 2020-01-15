[Home](../index.md) » [Guides](index.md) » Clipper

# Clipper

Clipper is a handy script that allows you to create subtitled (or unsubtitled) clips from a longer video,
directly from Aegisub.

## Requirements

The only requirements are 64-bit Windows 7 (or better) and Aegisub.

The releases on the official Aegisub website have not been updated in a while,
so you should install the latest release from [here](http://plorkyeran.com/aegisub/).

If you have troubles with that release, try uninstalling and using the
r8903+1 installer from [here](https://www.goodjobmedia.com/fansubbing/).

You can find a guide to using Aegisub [on the official site](http://docs.aegisub.org/3.2/Main_Page/).
While a lot of the information there is old, it should teach you the
basics of using the program to create subtitles.
Check out the [subtitling guide](subtitling.md) for advice on how to make your subtitles
good-looking and easy to read.

## Installation

This installation guide is for **Windows users only**.
Mac and Linux users should install `ffmpeg` using a package manager and save
[lae's version of Clipper](https://github.com/idolactivities/scripts/blob/master/aegisub/clipper.lua)
to Aegisub's `automation/autoload` directory.

1. Download and install Aegisub (see previous section).
2. Download `clipper.zip`.
3. Navigate to `%APPDATA%\Aegisub\automation\autoload` (you can paste that directly into the Windows Explorer navigation bar).
4. Extract the contents of the zip file directly into the `autoload` folder. Your file structure should look like this:  

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
5. Restart Aegisub, and you should see "Clipper" when you open the "Automation" menu.

## Usage

Under construction

## Troubleshooting

If you're having issues with Clipper, check the following:

1. Are you using a recent version of Aegisub? See [Requirements](#requirements), above.
2. Have you saved your subtitles file recently? Clipper requires a saved subtitles file,
and unsaved changes will not show up in the output video.
3. Are there non-English characters or accented characters in any of your file names
or folder names? Try renaming your files and folders to only use English characters.

   You can also try opening your system's Language Settings, select "Administrative
   language settings", click on "Change system locale", and check the box for utf-8
   support.

   ![Change system locale](/scripts/assets/img/guides_clipper_locale_settings.png)