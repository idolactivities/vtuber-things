--[[
Creates a hardsubbed video clip from selected lines.
]] --
script_name = "Clipper"
script_description =
    "Encode a video clip by reading start and end times from the selected lines."
script_version = "1.0.1"

FFMPEG = "ffmpeg"
FFPROBE = "ffprobe"
ENCODE_PRESETS = {
    ["Test Encode (fast)"] = {
        options = "-c:v libx264 -preset ultrafast -tune zerolatency -s 1280x720 -c:a aac",
        extension = ".mp4"
    },
    ["Twitter Encode (quick and OK quality, MP4)"] = {
        options = "-c:v libx264 -preset slow -profile:v high -level 3.2 -tune film -c:a aac",
        extension = ".mp4"
    },
    ["YouTube Encode (quick and good quality, MP4)"] = {
        options = "-c:v libx264 -preset slow -profile:v high -level 4.2 -crf 20 -c:a aac",
        extension = ".mp4"
    },
    ["YouTube Encode (very slow but better quality/size, WebM)"] = {
        options = '-c:v libvpx-vp9 -row-mt 1 -cpu-used 2 -crf 20 -b:v 0 -c:a libopus',
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

function encode_cmd(video, ss, to, options, filter, output, logfile)
    local command = {
        ('%q'):format(FFMPEG),
        ('-ss %s -to %s -i %q -copyts'):format(ss, to, video), options,
        ('-filter_complex %q -map "[vo]" -map "[ao]"'):format(filter),
        ('-color_primaries %s -color_trc %s -colorspace %s'):format(
            id_colorspace(video)), ('%q'):format(output),
        ('2> %q'):format(logfile)
    }
    -- add a input video read offset if our video FPS is 50+ to fix off-by-one
    -- frame errors in 60FPS videos (haven't tested on 50FPS videos though, I
    -- just picked a number close to 17)
    local frame_ms = aegisub.ms_from_frame(1) - aegisub.ms_from_frame(0)
    if frame_ms <= 20 then
        table.insert(command, 2, ('-itsoffset -%0.3f'):format(frame_ms / 1000))
    end
    return table.concat(command, ' ')
end

function build_segments(sub, sel, explicit)
    -- default to true if unspecified, for explicitly defined segments
    local explicit = explicit == nil and true or explicit

    local line_timings = {}
    if explicit then
        for _, si in ipairs(sel) do
            line = sub[si]
            if line.end_time > line.start_time then
                table.insert(line_timings, {line.start_time, line.end_time})
            end
        end
    else
        for _, si in ipairs(sel) do
            line = sub[si]
            if not line.comment and line.end_time > line.start_time then
                table.insert(line_timings, {line.start_time, line.end_time})
            end
        end
    end

    -- used for merging segments right after one another
    local frame_duration = aegisub.ms_from_frame(1) - aegisub.ms_from_frame(0)

    -- initialize a list of segment inputs to feed to ffmpeg as inputs, and a
    -- list of timings for each segment input with the first line timing
    local segment_inputs = {}
    local segments = {{line_timings[1][1], line_timings[1][2]}}
    if explicit then
        for i = 2, #line_timings do
            local previous_end = segments[#segments][2]
            if line_timings[i][1] >= previous_end and line_timings[i][1] -
                previous_end <= frame_duration then
                -- merge lines if they're right after one another
                segments[#segments][2] = line_timings[i][2]
            elseif line_timings[i][1] > previous_end then
                -- add a timing within the current segment since it falls after
                -- earlier defined segments
                table.insert(segments, {line_timings[i][1], line_timings[i][2]})
            else
                -- if a line goes backwards, save the current segment input and
                -- initialize a new list of segments
                table.insert(segment_inputs, segments)
                segments = {{line_timings[i][1], line_timings[i][2]}}
            end
        end
        -- save our last segment input once all line timings have been read
        table.insert(segment_inputs, segments)
    else
        for i = 2, #line_timings do
            local previous_end = segments[#segments][2]
            if line_timings[i][1] >= previous_end and line_timings[i][1] -
                previous_end <= 500 then
                -- merge lines with less than 500ms gap
                segments[#segments][2] = line_timings[i][2]
                -- todo: need to identify whether or not selected line is within current segment
            elseif line_timings[i][1] > previous_end then
                -- add a timing within the current segment since it falls after
                -- earlier defined segments
                table.insert(segments, {line_timings[i][1], line_timings[i][2]})
            else
                -- if a line goes backwards, save the current segment input and
                -- initialize a new list of segments
                table.insert(segment_inputs, segments)
                segments = {{line_timings[i][1], line_timings[i][2]}}
            end
        end
        -- save our last segment input once all line timings have been read
        table.insert(segment_inputs, segments)
    end

    return segment_inputs
end

function filter_complex(inputs, subtitle_file, hardsub)
    local input_ids = {}
    for i = 1, #inputs do table.insert(input_ids, ("%03d"):format(i)) end

    -- contains all of the filters needed to pass through filter_complex
    local filters = {}

    -- initial filter for the input video
    local vin_filter = {
        "[0:v]", -- input video
        "format=pix_fmts=rgb32," -- convert input video to raw before hardsubbing
    }

    -- apply ASS subtitle filter for hardsub
    if hardsub then table.insert(vin_filter, ("ass='%s',"):format(subtitle_file)) end

    table.insert(vin_filter, ("split=%d"):format(#inputs)) -- duplicate input video into several

    -- specify video outputs for the split filter above
    for _, id in ipairs(input_ids) do
        table.insert(vin_filter, ("[v%s]"):format(id))
    end
    table.insert(filters, table.concat(vin_filter))

    -- initial filter for the input audio
    local ain_filter = {
        "[0:a]", -- input audio
        ("asplit=%d"):format(#inputs) -- duplicate input audio into several
    }
    -- specify audio outputs for the split filter above
    for _, id in ipairs(input_ids) do
        table.insert(ain_filter, ("[a%s]"):format(id))
    end
    table.insert(filters, table.concat(ain_filter))

    -- start building out inputs list for the final concat filter
    local trimmed_vins, trimmed_ains = '', ''
    -- create a/v filters for trimming segments
    for i = 1, #inputs do
        local id = input_ids[i]
        local segments = inputs[i]

        -- specify inputs for the concat filter to apply at the end
        trimmed_vins = trimmed_vins .. ("[v%st]"):format(id)
        trimmed_ains = trimmed_ains .. ("[a%st]"):format(id)

        -- build expression to pass to the select/aselect filters
        local selects, selects_sep = '', ''
        for _, segment in ipairs(segments) do
            -- https://www.ffmpeg.org/ffmpeg-utils.html#Expression-Evaluation
            local current_select = ('between(t,%0.3f,%0.3f)'):format(
                                       segment[1] / 1000, segment[2] / 1000)
            selects = selects .. selects_sep .. current_select
            selects_sep = '+'
        end

        -- https://ffmpeg.org/ffmpeg-filters.html#select_002c-aselect
        local vsel_filter = {
            ("[v%s]"):format(id), -- video segment id
            ("select='%s',"):format(selects), -- the filter that trims the input
            "setpts=N/FRAME_RATE/TB", -- constructs correct timestamps for output
            ("[v%st]"):format(id) -- trimmed video output for current segment to concat later
        }
        table.insert(filters, table.concat(vsel_filter))

        local asel_filter = {
            ("[a%s]"):format(id), -- audio segment id
            ("aselect='%s',"):format(selects), -- the filter that trims the input
            "asetpts=N/SR/TB", -- constructs correct timestamps for output
            ("[a%st]"):format(id) -- trimmed audio output for current segment to concat later
        }
        table.insert(filters, table.concat(asel_filter))
    end

    vconcat_filter = {
        trimmed_vins, -- list of trimmed inputs built earlier
        ("concat=n=%d:v=1:a=0,"):format(#inputs), -- concat the video inputs
        "format=pix_fmts=yuv420p", -- convert video back to an appropriate pixel format
        "[vo]" -- the final video output
    }
    table.insert(filters, table.concat(vconcat_filter))

    aconcat_filter = {
        trimmed_ains, -- list of trimmed inputs built earlier
        ("concat=n=%d:v=0:a=1"):format(#inputs), -- concat the audio inputs
        "[ao]" -- the final audio output
    }
    table.insert(filters, table.concat(aconcat_filter))

    return table.concat(filters, ";")
end

function save_subtitles(sub, save_path)
    local content = {}
    local section = ""
    for _, line in ipairs(sub) do
        if not (line.section == section) then
            section = line.section
            table.insert(content, section)
        end
        table.insert(content, line.raw)
    end
    subs_fh = io.open(save_path, 'w')
    subs_fh:write(table.concat(content, '\n'))
    subs_fh:close()
end

function clipper(sub, sel, _)
    local dir_sep = package.config:sub(1, 1)

    -- save a copy of the current subtitles to a temporary location
    local subs_path = aegisub.decode_path('?temp/clipper.ass')
    save_subtitles(sub, subs_path)

    -- path of video
    local video_path = aegisub.project_properties().video_file

    -- sets work_dir to the same folder as the script if it exists, otherwise
    -- use the video dir (e.g. for a quick unsubbed clip)
    local work_dir = aegisub.decode_path('?script')
    if work_dir == '?script' then work_dir = aegisub.decode_path('?video') end
    work_dir = work_dir .. dir_sep

    -- default the clipname to either the script's filename or "Untitled" with
    -- a suffix that doesn't conflict with any existing files
    local clipname = aegisub.file_name()
    if not (clipname == 'Untitled') then clipname = split_ext(clipname) end
    clipname = find_unused_clipname(work_dir, clipname)
    -- grab final selected options from the user
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
    local logfile_path = output_path .. '_encode.log'

    local segment_inputs = build_segments(sub, sel, true)
    local filter = filter_complex(segment_inputs, subs_path, hardsub)

    -- identify earliest and latest points in the clip so that we can limit
    -- reading the input file to just the section we need (++execution speed)
    local seek_start = math.floor(segment_inputs[1][1][1] / 1000)
    local seek_end = seek_start
    for _, segments in ipairs(segment_inputs) do
        local segment_start = math.floor(segments[1][1] / 1000)
        local segment_end = math.ceil(segments[#segments][2] / 1000)
        if seek_start > segment_start then seek_start = segment_start end
        if seek_end < segment_end then seek_end = segment_end end
    end

    local encode_cmd = encode_cmd(video_path, seek_start, seek_end, options,
                                  filter, output_path, logfile_path)
    aegisub.debug.out(encode_cmd ..
                          ('\n\nFor command output, please see the log file at %q\n\n'):format(
                              logfile_path))
    res = os.execute(encode_cmd)

    -- remove temporary subtitle file
    os.remove(subs_path)

    if res == nil then
        aegisub.debug.out('ffmpeg failed to complete.')
        aegisub.cancel()
    end
end

----------------------------------
-- Clipper Configuration Dialog --
----------------------------------
function select_clip_options(clipname)
    local presets = {}
    for k, v in pairs(ENCODE_PRESETS) do presets[#presets + 1] = k end
    local config = {
        {x = 0, y = 0, width = 1, height = 1, class = "label", label = "Encoding Preset"},
        {x = 2, y = 0, width = 2, height = 1, class = "dropdown", name = "preset", items = presets, value = presets[1]},
        {x = 0, y = 1, width = 1, height = 1, class = "label", label = "Clip Name"},
        {x = 2, y = 1, width = 2, height = 1, class = "edit", name = "clipname", value = clipname},
        {x = 0, y = 2, width = 1, height = 1, class = "label", label = "Hardsub?"},
        {x = 2, y = 2, width = 1, height = 1, class = "checkbox", name = "hardsub", value = true}
    }
    local buttons = {"OK", "Cancel"}
    local button_ids = {ok = "OK", cancel = "Cancel"}
    local button, results = aegisub.dialog.display(config, buttons, button_ids)
    if button == false then aegisub.cancel() end
    return results["preset"], results["clipname"], results["hardsub"]
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
    -- fail if video is not loaded
    if aegisub.decode_path('?video') == '?video' then return false end
    return true
end

aegisub.register_macro(script_name, script_description, clipper,
                       validate_clipper)

