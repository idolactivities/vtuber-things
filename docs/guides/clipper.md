[Home](../index.md) » [Guides](index.md) » Clipper

# Clipper

Clipper is a handy script that allows you to create subtitled (or unsubtitled) clips from a longer video,
directly from Aegisub.

## Requirements

The only requirements are 64-bit Windows 7 (or better) and Aegisub.

The releases on the official Aegisub website have not been updated in a while,
so you should install the latest release from **[here](http://plorkyeran.com/aegisub/)**.

If you have troubles with that release, try uninstalling and using the
r8903+1 installer from **[here](https://www.goodjobmedia.com/fansubbing/)**.

You can find a guide to using Aegisub [on the official site](http://docs.aegisub.org/3.2/Main_Page/).
While a lot of the information there is old, it should teach you the
basics of using the program to create subtitles.
Check out the [Subtitling Guide](subtitling.md) for advice on how to make your subtitles
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

The first thing you should do is read **["Before You Translate..."](../vtuber/translating.md)**

Did you read it? Understand it? Good.

The first step to using Clipper is to open the video in Aegisub and save a new subtitles file.
It's okay if you haven't done anything yet. Your subtitles need to be saved in order for Clipper to work.

Create your subtitles as normal, adding them to the scenes in the original video that you want to clip.
This guide will not teach you the basics of using Aegisub, but you can check out the
[Subtitling Guide](subtitling.md) for advice on polishing your subtitles.

When you are done creating your subtitles, it's time to run Clipper.
From the "Automation" menu at the top, select "Clipper".
You should see a dialog like this:

![Clipper menu](/scripts/assets/img/guides_clipper_clipper_menu.png)

* **Preset** – The quality settings to use when encoding the clip.
Choose one based on what you plan to do with the final video.
* **Clip Name** – Name your clip. It will be saved in the same folder as your subtitles file.
* **Segmentation** – Controls what parts of the original video get clipped.
Detailed explanation below.

### Automatic segmentation

Clipper will look for the parts of the video where you've added subtitles, and only cut out those parts.
Parts of the video that don't have subtitles will be left out of the final clip.
This is good for making clips that mostly consist of talking.

### Segments from selected lines

This offers you more control over exactly what gets clipped, allowing you to cut out and join
together many scenes that may or may not have subtitles.

You define your segments by adding commented lines to your subtitles file.
Each commented line defines a segment to clip, which starts at the line's start time
and ends at the line's end time. To create a clip, select the lines corresponding to
the segments you want, and run Clipper set to "Segment from selected lines".

For example, in the screenshot below, I've made a commented line that starts at 7:50.62
in the video and ends at 8:04.85. If I select that line and run Clipper, it will
cut out the part of the video between 7:50.62 and 8:04.85. If I had any subtitles in the
file, it would also add those to the video.

<a href="/scripts/assets/img/guides_clipper_manual_segment_01.png" target="_blank">
  <img src="/scripts/assets/img/guides_clipper_manual_segment_01.png" width="520" alt="Click to enlarge" title="Click to enlarge"/>
</a>

You should always comment the lines you use to define your segments, because they are not
actual subtitles. We are only using them to tell Clipper how to clip our video, but we
don't want those lines to actually appear on the final video. Because the lines are
commented and won't show up in the final video, you can write whatever you want in them.
I recommend putting a name for the segment, so you remember what part of the video it is.

You can create (in theory) as many segments as you want, and Clipper will cut them out
and join them together to create the final video. You can see in the below screenshot,
I've created two segments (the commented lines at the top): one starts at around 7:50
and ends at around 8:04, and the other starts at around 32:11 and ends at around 32:57.
I've also added descriptions of what happens in each segment and some subtitles.

<a href="/scripts/assets/img/guides_clipper_manual_segment_02.png" target="_blank">
  <img src="/scripts/assets/img/guides_clipper_manual_segment_02.png" width="520" alt="Click to enlarge" title="Click to enlarge"/>
</a>

To create my final clip, all I have to do is select the two commented lines (hold shift
or ctrl to select multiple lines) and run Clipper set to "Segment from selected lines".
The two segments will be cut out of the video, the subtitles will be added, the segments
will be joined together, and the final clip will be saved in the same folder as the
subtitles file.

## Troubleshooting

If you're having issues with Clipper, check the following:

1. Are you using a recent version of Aegisub? See [Requirements](#requirements).
2. Does your directory structure match what was shown in [Installation](#installation)?
3. Have you saved your subtitles file recently? Clipper requires a saved subtitles file,
and unsaved changes will not show up in the output video.
4. Are there non-English characters or accented characters in any of your file names
or folder names? Try renaming your files and folders to only use English characters.

   Alternatively, you can try opening your system's Language Settings, select
   "Administrative language settings", click on "Change system locale", and check the
   box for UTF-8 support.

   ![Change system locale](/scripts/assets/img/guides_clipper_locale_settings.png)
5. What kind of segmentation are you using? "From selected lines" or "automatic"?
Make sure you're follow the instructions for each type of segmentation as
explained in [Usage](#usage).
