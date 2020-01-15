--[[
Creates easy video clips from Aegisub.

Guide here:
https://lyger.github.io/scripts/guides/clipper.html

]] --

---------------------
-- BASIC CONSTANTS --
---------------------

script_name = 'Clipper'
script_description = 'Encode a video clip based on the subtitles.'
script_version = '0.1'

clipboard = require('aegisub.clipboard')

ENCODE_PRESETS = {
    ['Test Encode (fast)'] = {
        options = '-c:v libx264 -preset ultrafast -tune zerolatency -c:a aac',
        extension = '.mp4'
    },
    ['Twitter Encode (quick, OK quality)'] = {
        options = '-c:v libx264 -preset slow -profile:v high -level 3.2 -tune film -c:a aac',
        extension = '.mp4'
    },
    ['YouTube Encode (slow, WebM)'] = {
        options = '-c:v libvpx-vp9 -crf 20 -b:v 0 -c:a libopus',
        extension = '.webm'
    }
}

CONFIG_PATH = aegisub.decode_path('?user/clipper.conf')

global_config = { version = script_version }

-------------------
-- GENERAL UTILS --
-------------------

function file_exists(name)
    local f = io.open(name, 'r')
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

function split_ext(fname) return string.match(fname, '(.-)%.([^%.]+)$') end

function table.keys(tb)
    local keys = {}
    for k, v in pairs(tb) do table.insert(keys, k) end
    return keys
end

function table.update(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
end

--------------------------
-- FIND FFMPEG BINARIES --
--------------------------

function find_bin_or_error(name)
    -- Check user directory
    -- This should take precedence, as it is recommended by the install instructions
    local file = aegisub.decode_path(('?user/automation/autoload/bin/%s'):format(name))
    if file_exists(file) then return file end

    -- If that fails, check install directory
    local file = aegisub.decode_path(('?data/automation/autoload/bin/%s'):format(name))
    if file_exists(file) then return file end

    -- If that fails, check for executable in path
    local path = os.getenv('PATH') or ''
    for prefix in path:gmatch('([^:]+):?') do
        local file = prefix .. '/' .. name
        if file_exists(file) then return name end
    end

    -- Else, error
    error((
        'Could not find %s.' ..
        'Make sure it is in Aegisub\'s "automation/autoload/bin" folder ' ..
        'or in your PATH.'
    ):format(name))
end

FFMPEG = find_bin_or_error('ffmpeg.exe')
FFPROBE = find_bin_or_error('ffprobe.exe')

---------------------------------
-- DEFINE SEGMENTATION METHODS --
---------------------------------

function manual_segment(sub, sel)
    -- collect the lines selected in aegisub
    local warn_uncomment = false
    local segments = {}
    for _, si in ipairs(sel) do
        line = sub[si]
        -- Skip lines with zero duration
        if  line.end_time > line.start_time then
            table.insert(segments, {line.start_time, line.end_time})
        end
        if not line.comment then warn_uncomment = true end
    end

    if warn_uncomment then
        show_help(
            'manual segment uncommented',
            'Some of your selected lines were uncommented.\n' ..
            'It\'s recommended to define your segments using\n' ..
            'commented lines. Check that you meant to do this.'
        )
    end

    return segments
end

function auto_segment(sub, _)
    -- collect all dialogue lines
    local raw_segments = {}
    for i = 1, #sub do
        line = sub[i]
        -- Only use uncommented dialogue lines with positive duration
        if line.class == 'dialogue' and not line.comment and line.end_time > line.start_time then
            table.insert(raw_segments, {line.start_time, line.end_time})
        end
    end

    -- sort selected lines by start time
    local modified = true
    while modified do
        modified = false
        for i = 1, #raw_segments - 1 do
            if raw_segments[i][1] > raw_segments[i + 1][1] then
                modified = true
                raw_segments[i], raw_segments[i + 1] = raw_segments[i + 1], raw_segments[i]
            end
        end
    end

    -- init segments with the first line
    local segments = {{raw_segments[1][1], raw_segments[1][2]}}
    for i = 2, #raw_segments do
        local previous_end = segments[#segments][2]
        -- merge lines with less than 500ms gap, otherwise insert new segment
        if raw_segments[i][2] > previous_end and raw_segments[i][1] - previous_end < 500 then
            segments[#segments][2] = raw_segments[i][2]
        elseif raw_segments[i][2] <= previous_end then
            -- skip since the line overlaps with an earlier line
        else
            table.insert(segments, {raw_segments[i][1], raw_segments[i][2]})
        end
    end

    return segments
end

SEGMENT_OPTIONS = {
    ['Segments from selected lines'] = manual_segment,
    ['Automatic segmentation'] = auto_segment,
}

--------------------
-- ENCODING UTILS --
--------------------

function estimate_frames(segments)
    local fr = (aegisub.ms_from_frame(1001) - aegisub.ms_from_frame(1)) / 1000
    local frame_count = 0
    for _, segment in ipairs(segments) do
        frame_count = frame_count + math.floor((segment[2] - segment[1]) / fr)
    end
    return frame_count
end

function run_as_batch(cmd, callback)
    local temp_file = aegisub.decode_path('?temp/clipper.bat')
    local fh = io.open(temp_file, 'w')
    fh:write(cmd .. '\r\n')
    fh:close()

    local res = nil
    -- If a callback is provided, run it on the process output
    if callback ~= nil then
        local pipe = assert(io.popen('"' .. temp_file .. '"', 'r'))
        callback(pipe)
        res = {pipe:close()}
        res = res[1]
    -- Otherwise, just execute it
    else
        res = os.execute('"' .. temp_file .. '"')
    end

    -- Cleanup and return the exit code
    os.remove(temp_file)
    return res
end

function id_colorspace(video)
    local values = {}

    local cmd = ('"%s" -show_streams -select_streams v "%s"'):format(FFPROBE, video)

    run_as_batch(
        cmd,
        function(pipe)
            for line in pipe:lines() do
                if line:match('^color') then
                    local key, value = line:match('^([%w_]+)=(%w+)$')
                    if key then values[key] = value end
                end
            end
        end
    )

    -- https://kdenlive.org/en/project/color-hell-ffmpeg-transcoding-and-preserving-bt-601/
    if values['color_space'] == 'bt470bg' then
        return 'bt470bg', 'gamma28', 'bt470bg'
    else
        if values['color_space'] == 'smpte170m' then
            return 'smpte170m', 'smpte170m', 'smpte170m'
        else
            return values['color_space'], values['color_transfer'],
                   values['color_primaries']
        end
    end
end

function encode_cmd(video, ss, to, options, filter, afilter, output)
    local command = table.concat({
        ('"%s"'):format(FFMPEG),
        '-y', -- Force overwrite
        ('-ss %s -to %s -i "%s" -copyts'):format(ss, to, video),
        options,
        ('-vf "%s" -af "%s"'):format(filter, afilter),
        ('"%s"'):format(output),
        ('-color_primaries %s -color_trc %s -colorspace %s'):format(
            id_colorspace(video)),
        '2>&1' -- stderr to stdout
    }, ' ')

    return command
end

-----------------------------
-- CONFIG/DIALOG FUNCTIONS --
-----------------------------

function show_info(message, extra)
    local buttons = {'OK'}
    local button_ids = {ok = 'OK'}

    -- This is only used internally, so just lazy match links
    local link = message:match('http[s]://%S+')
    if link then buttons = {'Copy link', 'OK'} end

    dialog = {{class = 'label', label = message, x = 0, y = 0, width = 1, height = 1}}
    
    if extra ~= nil and type(extra) == 'table' then
        for _, control in ipairs(extra) do
            table.insert(dialog, control)
        end
    end

    local is_okay = nil
    while is_okay ~= 'OK' do
        is_okay, results = aegisub.dialog.display(
            dialog,
            buttons,
            button_ids
        )

        if is_okay == 'Copy link' then
            clipboard.set(link)
        end
    end
    return results
end

function show_help(key, message, show_hide_confirmation)
    if global_config['skip_help'][key] ~= nil then return end

    if show_hide_confirmation == nil then show_hide_confirmation = true end

    local extras = nil
    if show_hide_confirmation then
        extras = {{
            class = 'checkbox', label = 'Don\'t show this message again',
            name = 'skip', value = false, x = 0, y = 1, width = 1, height = 1,
        }}
    end

    results = show_info(message, extras)

    if results['skip'] then global_config['skip_help'][key] = true end
end

function init_config()
    global_config['preset'] = table.keys(ENCODE_PRESETS)[1]
    global_config['segmentation'] = table.keys(SEGMENT_OPTIONS)[1]
    global_config['skip_help'] = {}

    show_help(
        'welcome',
        'Welcome to Clipper! If this is your first time\n' ..
        'using Clipper, please read the guide here:\n\n' ..
        'https://lyger.github.io/scripts/guides/clipper.html',
        false
    )

    save_config()
end

function update_config_version(conf)
    -- To be written if a future update changes the configuration format
    return conf
end

function save_config()
    conf_fp = io.open(CONFIG_PATH, 'w')

    global_config['clipname'] = nil

    for k, v in pairs(global_config) do
        -- Lists always end in a comma
        if type(v) == 'table' then
            -- But they are stored as keys to a table
            v = table.concat(table.keys(v), ',') .. ','
        end
        conf_fp:write(('%s = %s\n'):format(k, v))
    end

    conf_fp:close()
end

function load_config()
    if not file_exists(CONFIG_PATH) then return init_config() end

    conf = {}
    conf_fp = io.open(CONFIG_PATH, 'r')

    for line in conf_fp:lines() do
        -- Strip leading whitespace
        line = line:match('%s*(.+)')

        -- Skip empty lines and comments
        if line and line:sub( 1, 1 ) ~= '#' and line:sub( 1, 1 ) ~= ';' then
            option, value = line:match('(%S+)%s*[=:]%s*(.*)')

            -- Lists always end in a comma
            if value:sub(-1) == ',' then
                values = {}
                -- But we store them as keys for easy indexing
                for k in value:gmatch('%s*([^,]+),') do values[k] = true end
                conf[option] = values
            else
                conf[option] = value
            end
        end
    end

    if conf['version'] ~= script_version then
        conf = update_config_version(conf)
    end

    table.update(global_config, conf)

    conf_fp:close()
end

function find_unused_clipname(output_dir, basename)
    -- build a set of extensions that our presets may have
    local extensions = {}
    for k, v in pairs(ENCODE_PRESETS) do extensions[v['extension']] = true end

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

function confirm_overwrite(filename)
    local config = {
        {
            class = 'label',
            label = ('Are you sure you want to overwrite %s?'):format(filename),
            x = 0,
            y = 0,
            width = 4,
            height = 2
        }
    }
    local buttons = {'Yes', 'Cancel'}
    local button_ids = {ok = 'Yes', cancel = 'Cancel'}
    local button, _ = aegisub.dialog.display(config, buttons, button_ids)
    if button == false then aegisub.cancel() end
end

function select_clip_options(clipname)
    local config = {
        {
            class = 'label',
            label = 'Preset',
            x = 0,
            y = 0,
            width = 1,
            height = 1
        },
        {
            class = 'dropdown',
            name = 'preset',
            items = table.keys(ENCODE_PRESETS),
            value = global_config['preset'],
            x = 2,
            y = 0,
            width = 2,
            height = 1
        },
        {
            class = 'label',
            label = 'Clip Name',
            x = 0,
            y = 1,
            width = 1,
            height = 1
        },
        {
            class = 'edit',
            name = 'clipname',
            value = clipname,
            x = 2,
            y = 1,
            width = 2,
            height = 1
        },
        {
            class = 'label',
            label = 'Segmentation',
            x = 0,
            y = 2,
            width = 1,
            height = 1
        },
        {
            class = 'dropdown',
            name = 'segmentation',
            items = table.keys(SEGMENT_OPTIONS),
            value = global_config['segmentation'],
            x = 2,
            y = 2,
            width = 2,
            height = 1
        },

    }
    local buttons = {'OK', 'Cancel'}
    local button_ids = {ok = 'OK', cancel = 'Cancel'}
    local button, results = aegisub.dialog.display(config, buttons, button_ids)
    if button == false then aegisub.cancel() end

    table.update(global_config, results)
    save_config()

    return results
end

---------------------------
-- MAIN CLIPPER FUNCTION --
---------------------------

function clipper(sub, sel, _)
    -- path of video
    local video_path = aegisub.project_properties().video_file
    -- path/filename of subtitle script
    local work_dir = aegisub.decode_path('?script') .. package.config:sub(1, 1)
    local ass_fname = aegisub.file_name()
    local ass_path = work_dir .. ass_fname

    load_config()

    local clipname = find_unused_clipname(work_dir, split_ext(ass_fname))
    local results = select_clip_options(clipname)
    local output_path = work_dir .. results['clipname'] ..
                            ENCODE_PRESETS[results['preset']]['extension']
    local options = ENCODE_PRESETS[results['preset']]['options']

    if file_exists(output_path) then
        if output_path == video_path then
            show_info((
                'The specified output file (%s) is the same as\n' ..
                'the input file, which isn\'t allowed. Specify\n' ..
                'a different clip name instead.'):format(output_path))
            aegisub.cancel()
        end
        confirm_overwrite(output_path)
        options = options .. ' -y'
    end

    local logfile_path = work_dir .. clipname .. '_encode.log'

    local segments = SEGMENT_OPTIONS[results['segmentation']](sub, sel)

    if #segments == 0 then
        show_info(
            'Unable to find or create segments to clip.\n' ..
            'Does your subtitle file or selection contain\n' ..
            'lines with non-zero duration?'
        )
        aegisub.cancel()
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
            ass_path:gsub('\\', '\\\\'):gsub(':', '\\:'), selects)
    local afilter = ('aselect=\'%s\',asetpts=N/SR/TB'):format(selects)
    local seek_start = math.floor(segments[1][1] / 1000)
    local seek_end = math.ceil(segments[#segments][2] / 1000) + 5

    local cmd = encode_cmd(video_path, seek_start, seek_end, options,
                           filter, afilter, output_path)

    -- Save the command to the log file
    local log_fh = io.open(logfile_path, 'w')

    local total_frames = estimate_frames(segments)

    res = run_as_batch(
        cmd,
        function(pipe)
            for line in pipe:lines() do
                log_fh:write(line .. '\n')
                for fnum in line:gmatch('frame=%s*(%d+)') do
                    fnum = tonumber(fnum)
                    aegisub.progress.set(math.floor(100 * fnum / total_frames))
                    aegisub.progress.task(('Encoding frame %d/%d'):format(fnum, total_frames))
                end
            end
        end
    )

    log_fh:close()

    if res == nil then
        show_info((
            'FFmpeg failed to complete! Try the troubleshooting\n' ..
            'here to figure out what\'s wrong:\n\n' ..
            'https://lyger.github.io/scripts/guides/clipper.html#troubleshooting\n\n' ..
            'Detailed information saved to:\n\n%s'
        ):format(logfile_path))
        aegisub.cancel()
    end

    -- The user doesn't need to see the log file unless the encoding fails
    os.remove(logfile_path)
end

function validate_clipper(sub, sel, _)
    if aegisub.decode_path('?script') == '?script'
        or aegisub.decode_path('?video') == '?video'
    then
        return false
    end
    return true
end

aegisub.register_macro(
    script_name, script_description, clipper, validate_clipper
)

