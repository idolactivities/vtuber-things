--[[
Creates a hardsubbed video clip from selected lines.
]] --
script_name = "Clipper"
script_description =
    "Encode a video clip by reading start and end times from the selected lines."
script_version = "1.0"

FFMPEG = "ffmpeg"
FFPROBE = "ffprobe"

ENCODE_PRESETS = {
    ["Test Encode (fast)"] = {
        options = "-c:v libx264 -preset ultrafast -tune zerolatency -c:a aac",
        extension = ".mp4"
    },
    ["Twitter Encode (quick, OK quality)"] = {
        options = "-c:v libx264 -preset slow -profile:v high -level 3.2 -tune film -c:a aac",
        extension = ".mp4"
    },
    ["YouTube Encode (slow, WebM)"] = {
        options = "-c:v libvpx-vp9 -crf 20 -b:v 0 -c:a libopus",
        extension = ".webm"
    }
}

function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

function split_ext(fname) return string.match(fname, "(.-)%.([^%.]+)$") end

function id_colorspace(video)
    local values = {}

    local cmd = ('%q -show_streams -select_streams v %q'):format(FFPROBE, video)
    local f = assert(io.popen(cmd, 'r'))
    for line in f:lines() do
        if string.match(line, '^color') then
            local key, value = string.match(line, "^([%w_]+)=(%w+)$")
            if key then values[key] = value end
        end
    end

    for key, value in pairs(values) do print(key, value) end

    -- https://kdenlive.org/en/project/color-hell-ffmpeg-transcoding-and-preserving-bt-601/
    if values["color_space"] == "bt470bg" then
        return "bt470bg", "gamma28", "bt470bg"
    else
        if values["color_space"] == "smpte170m" then
            return "smpte170m", "smpte170m", "smpte170m"
        else
            return values["color_space"], values["color_transfer"],
                   values["color_primaries"]
        end
    end
end

function encode_cmd(video, ss, to, options, filter, afilter, output, logfile)
    local command = table.concat({
        ('%q'):format(FFMPEG),
        ('-ss %s -to %s -i %q -copyts'):format(ss, to, video), options,
        ('-vf %q -af %q'):format(filter, afilter),
        ('-color_primaries %s -color_trc %s -colorspace %s'):format(
            id_colorspace(video)), ('%q'):format(output),
        ('2> %q'):format(logfile)
    }, ' ')
    return command
end

function clipper(sub, sel, _)
    -- path of video
    local video_path = aegisub.project_properties().video_file
    -- path/filename of subtitle script
    local work_dir = aegisub.decode_path('?script') .. package.config:sub(1, 1)
    local ass_fname = aegisub.file_name()
    local ass_path = work_dir .. ass_fname

    local clipname = find_unused_clipname(work_dir, split_ext(ass_fname))
    local preset, clipname = select_clip_options(clipname)
    local output_path = work_dir .. clipname ..
                            ENCODE_PRESETS[preset]["extension"]
    local options = ENCODE_PRESETS[preset]["options"]
    if file_exists(output_path) then
        if output_path == video_path then
            aegisub.debug.out(
                ("The specified output file (%s) is the same as the input " ..
                    "file, which isn't allowed. Specify a different clip " ..
                    "name instead."):format(output_path))
            aegisub.cancel()
        end
        confirm_overwrite(output_path)
        options = options .. ' -y'
    end
    local logfile_path = work_dir .. clipname .. '_encode.log'

    -- collect the lines selected in aegisub
    local tlines = {}
    for _, si in ipairs(sel) do
        line = sub[si]
        if not line.comment then
            table.insert(tlines, {line.start_time, line.end_time})
        end
    end

    -- sort selected lines by start time
    local modified = true
    while modified do
        modified = false
        for i = 1, #tlines - 1 do
            if tlines[i][1] > tlines[i + 1][1] then
                modified = true
                tlines[i], tlines[i + 1] = tlines[i + 1], tlines[i]
            end
        end
    end

    -- init segments with the first line
    local segments = {{tlines[1][1], tlines[1][2]}}
    for i = 2, #tlines do
        local previous_end = segments[#segments][2]
        -- merge lines with less than 500ms gap, otherwise insert new segment
        if tlines[i][2] > previous_end and tlines[i][1] - previous_end < 500 then
            segments[#segments][2] = tlines[i][2]
        elseif tlines[i][2] <= previous_end then
            -- skip since the line overlaps with an earlier line
        else
            table.insert(segments, {tlines[i][1], tlines[i][2]})
        end
    end

    -- generate a ffmpeg filter of selects for the line segments
    local selects = ''
    local selects_sep = ''
    for _, segment in ipairs(segments) do
        local current_select = ('between(t,%03f,%03f)'):format(
                                   segment[1] / 1000, segment[2] / 1000)
        selects = selects .. selects_sep .. current_select
        selects_sep = '+'
    end

    local filter =
        ('format=pix_fmts=rgb32,ass=\'%s\',select=\'%s\',setpts=N/FRAME_RATE/TB,format=pix_fmts=yuv420p'):format(
            ass_path, selects)
    local afilter = ('aselect=\'%s\',asetpts=N/SR/TB'):format(selects)
    local seek_start = math.floor(segments[1][1] / 1000)
    local seek_end = math.ceil(segments[#segments][2] / 1000) + 5

    local encode_cmd = encode_cmd(video_path, seek_start, seek_end, options,
                                  filter, afilter, output_path, logfile_path)
    aegisub.debug.out(encode_cmd ..
                          ('\n\nFor command output, please see the log file at %q\n\n'):format(
                              logfile_path))
    res = os.execute(encode_cmd)

    if res == nil then
        aegisub.debug.out('ffmpeg failed to complete.')
        aegisub.cancel()
    end
end

function select_clip_options(clipname)
    local presets = {}
    for k, v in pairs(ENCODE_PRESETS) do presets[#presets + 1] = k end
    local config = {
        {class = "label", label = "Preset", x = 0, y = 0, width = 1, height = 1},
        {
            class = "dropdown",
            name = "preset",
            items = presets,
            value = presets[1],
            x = 2,
            y = 0,
            width = 2,
            height = 1
        },
        {
            class = "label",
            label = "Clip Name",
            x = 0,
            y = 1,
            width = 1,
            height = 1
        }, {
            class = "edit",
            name = "clipname",
            value = clipname,
            x = 2,
            y = 1,
            width = 2,
            height = 1
        }
    }
    local buttons = {"OK", "Cancel"}
    local button_ids = {ok = "OK", cancel = "Cancel"}
    local button, results = aegisub.dialog.display(config, buttons, button_ids)
    if button == false then aegisub.cancel() end
    return results["preset"], results["clipname"]
end

function confirm_overwrite(filename)
    local config = {
        {
            class = "label",
            label = ("Are you sure you want to overwrite %s?"):format(filename),
            x = 0,
            y = 0,
            width = 4,
            height = 2
        }
    }
    local buttons = {"Yes", "Cancel"}
    local button_ids = {ok = "Yes", cancel = "Cancel"}
    local button, _ = aegisub.dialog.display(config, buttons, button_ids)
    if button == false then aegisub.cancel() end
end

function find_unused_clipname(output_dir, basename)
    -- build a set of extensions that our presets may have
    local extensions = {}
    for k, v in pairs(ENCODE_PRESETS) do extensions[v["extension"]] = true end

    local suffix = 2
    local clipname = basename
    -- check if our clipname exists with any of the preset extensions and bump
    -- the clipname with a suffix until one doesn't exist
    while (true) do
        local exists = false
        for ext, _ in pairs(extensions) do
            exists = file_exists(output_dir .. clipname .. ext)
            if exists then break end
        end
        if exists then
            clipname = basename .. '-' .. suffix
            suffix = suffix + 1
        else
            break
        end
    end

    return clipname
end

function validate_clipper(sub, sel, _)
    if aegisub.decode_path('?script') == nil or aegisub.file_name() == nil then
        return false
    end
    if aegisub.decode_path('?video') == nil then return false end
    return true
end

aegisub.register_macro(script_name, script_description, clipper,
                       validate_clipper)

