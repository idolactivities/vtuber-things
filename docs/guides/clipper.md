---
show_downloads: true
github:
  is_project_page: true
  repository_url: https://github.com/idolactivities/vtuber-things/tree/clipper-v1.1.1/clipper
  zip_url: https://github.com/idolactivities/vtuber-things/releases/download/clipper-v1.1.1/clipper-v1.1.1-windows.zip
---

[Home](../index.md) » [Guides](index.md) » Clipper

# Clipper

Clipper is a handy script that allows you to create subtitled (or unsubtitled) clips from a longer video,
directly from Aegisub.

Create your subtitles as normal, then use commented lines to select the parts of the video to clip.
Run Clipper on those lines, and the subtitles will be added onto the video ("hardsubbed")
and the selected parts of the video will be cut out and joined together into a new video file.

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
Mac and Linux users should install `ffmpeg` using a package manager and save the
[Linux version of Clipper]({{ site.github.repository_url }}/blob/master/clipper/clipper-linux.lua)
to Aegisub's `automation/autoload` directory.

1. Download and install Aegisub (see previous section). **Old versions of Aegisub may not be compatible.**
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

The first step to using Clipper is to download the video you want to make a clip from.
There are tons of YouTube downloaders out there, as well as downloaders for any other
video site you can imagine, so I won't walk you through this step. For the record,
I use youtube-dl.

Once you have the video downloaded, open it in Aegisub and save a new subtitles file.
Clipper requires a saved subtitles file, and will only show saved changes in its output,
so be sure to save frequently.

Create your subtitles as normal, adding them to the scenes in the original video that you want to clip.
This guide will not teach you the basics of using Aegisub, but you can check out the
[Subtitling Guide](subtitling.md) for advice on polishing your subtitles.

The next step is to define your **segments**. The final clip will be made of one or more
segments selected from the original video.

You define your segments by adding commented lines to your subtitles file.
Each commented line defines a segment that starts at the line's start time
and ends at the line's end time. To create a clip, select the lines corresponding to
the segments you want and run Clipper.

For example, in the screenshot below, I've made a commented line that starts at 7:50.62
in the video and ends at 8:04.85. If I select that line and run Clipper, it will
cut out the part of the video between 7:50.62 and 8:04.85. If I had any subtitles in the
file, it would also add those to the video.

<a href="{{ '/assets/img/guides_clipper_manual_segment_01.png' | relative_url }}" target="_blank">
  <img src="{{ '/assets/img/guides_clipper_manual_segment_01.png' | relative_url }}" width="520" alt="Click to enlarge" title="Click to enlarge"/>
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

<a href="{{ '/assets/img/guides_clipper_manual_segment_02.png' | relative_url }}" target="_blank">
  <img src="{{ '/assets/img/guides_clipper_manual_segment_02.png' | relative_url }}" width="520" alt="Click to enlarge" title="Click to enlarge"/>
</a>

When you are done creating your subtitles and segments, it's time to run Clipper.
Select the commented lines that you want to make a clip from (hold shift or ctrl to select multiple lines).
In my example, that would be the two lines at the top. Then, from the "Automation" menu at the top,
select "Clipper". That should bring up this dialog:

![Clipper menu]({{ '/assets/img/guides_clipper_clipper_menu.png' | relative_url }})

* **Preset** – The quality settings to use when encoding the clip.
Choose one based on what you plan to do with the final video.
* **Clip Name** – Name your clip. It will be saved in the same folder as your subtitles file.

If everything looks okay, run Clipper, and your selected segments will be cut out of the video,
the subtitles will be added, the segments will be joined together, and the final clip will
be saved in the same folder as the subtitles file.

## Troubleshooting

If you're having issues with Clipper, check the following:

1. Are you using a recent version of Aegisub? See [Requirements](#requirements).
2. Does your directory structure match what was shown in [Installation](#installation)?
3. Have you saved your subtitles file recently? Clipper requires a saved
   subtitles file, and unsaved changes will not show up in the output video.
4. Are there non-English characters or accented characters in any of your file
   names or folder names (both for the video you're working on and the subtitle
   file you're working on)? Try renaming your files and folders to only use
   English (ASCII) characters.

   Alternatively, you can try opening your system's Language Settings, select
   "Administrative language settings", click on "Change system locale", and
   check the box for UTF-8 support.

   ![Change system locale]({{ '/assets/img/guides_clipper_locale_settings.png' | relative_url }})
 5. If you're still having issues, please report the problem by
 [submitting an issue on Github]({{ site.github.repository_url }}/issues).

## Credits

Clipper was developed by [myself](https://github.com/lyger) and [lae](https://github.com/lae)
and uses [FFmpeg](https://www.ffmpeg.org/) for encoding.
