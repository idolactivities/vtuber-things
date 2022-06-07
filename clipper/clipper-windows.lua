--[[
Creates easy video clips from Aegisub.

Guide here:
https://idolactivities.github.io/vtuber-things/guides/clipper.html

]] --
---------------------
-- BASIC CONSTANTS --
---------------------
script_name = 'Clipper'
script_description = 'Encode a video clip based on the subtitles.'
script_version = '1.0.1'

clipboard = require('aegisub.clipboard')

ENCODE_PRESETS = {
    ['Test Encode (fast)'] = {
        options = '-c:v libx264 -preset ultrafast -tune zerolatency -c:a aac',
        extension = '.mp4'
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

CONFIG_PATH = aegisub.decode_path('?user/clipper.conf')

global_config = {version = script_version}

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

function table.values(tb)
    local values = {}
    for k, v in pairs(tb) do table.insert(values, v) end
    return values
end

function table.update(t1, t2) for k, v in pairs(t2) do t1[k] = v end end

--------------------------
-- FIND FFMPEG BINARIES --
--------------------------

function find_bin_or_error(name)
    -- Check user directory
    -- This should take precedence, as it is recommended by the install instructions
    local file = aegisub.decode_path(
                     ('?user/automation/autoload/bin/%s'):format(name))
    if file_exists(file) then return file end

    -- If that fails, check install directory
    local file = aegisub.decode_path(
                     ('?data/automation/autoload/bin/%s'):format(name))
    if file_exists(file) then return file end

    -- If that fails, check for executable in path
    local path = os.getenv('PATH') or ''
    for prefix in path:gmatch('([^:]+):?') do
        local file = prefix .. '/' .. name
        if file_exists(file) then return name end
    end

    -- Else, error
    error(('Could not find %s.' ..
              'Make sure it is in Aegisub\'s "automation/autoload/bin" folder ' ..
              'or in your PATH.'):format(name))
end

FFMPEG = find_bin_or_error('ffmpeg.exe')
FFPROBE = find_bin_or_error('ffprobe.exe')

----------------------------
-- SEGMENTATION FUNCTIONS --
----------------------------

function manual_segment(sub, sel)
    -- collect the lines selected in aegisub
    local warn_uncomment = false
    local line_timings = {}
    for _, si in ipairs(sel) do
        line = sub[si]
        -- Skip lines with zero duration
        if line.end_time > line.start_time then
            table.insert(line_timings, {line.start_time, line.end_time})
        end
        if not line.comment then warn_uncomment = true end
    end

    -- Used for merging segments right after one another
    local frame_duration = aegisub.ms_from_frame(1) - aegisub.ms_from_frame(0)

    -- Initialize a list of segment inputs to feed to ffmpeg as inputs, and a
    -- List of timings for each segment input with the first line timing
    local segment_inputs = {}
    local segments = {{line_timings[1][1], line_timings[1][2]}}
    for i = 2, #line_timings do
        local previous_end = segments[#segments][2]
        if line_timings[i][1] >= previous_end and line_timings[i][1] -
            previous_end <= frame_duration then
            -- Merge lines if they're right after one another
            segments[#segments][2] = line_timings[i][2]
        elseif line_timings[i][1] > previous_end then
            -- Add a timing within the current segment since it falls after
            -- earlier defined segments
            table.insert(segments, {line_timings[i][1], line_timings[i][2]})
        else
            -- If a line goes backwards, save the current segment input and
            -- initialize a new list of segments
            table.insert(segment_inputs, segments)
            segments = {{line_timings[i][1], line_timings[i][2]}}
        end
    end
    -- Save our last segment input once all line timings have been read
    table.insert(segment_inputs, segments)

    if warn_uncomment then
        show_help('manual segment uncommented',
                  'Some of your selected lines were uncommented.\n' ..
                      'It\'s recommended to define your segments using\n' ..
                      'commented lines. Check that you meant to do this.')
    end

    return segment_inputs
end

function filter_complex(inputs, subtitle_file)
    local input_ids = {}
    for i = 1, #inputs do table.insert(input_ids, ('%03d'):format(i)) end

    -- Contains all of the filters needed to pass through filter_complex
    local filters = {}

    -- Initial filter for the input video
    local vin_filter = {
        '[0:v]', -- input video
        'format=pix_fmts=rgb32,', -- convert input video to raw before hardsubbing
        ('ass=\'%s\','):format(subtitle_file:gsub('\\', '\\\\'):gsub(':', '\\:')), -- apply ASS subtitle filter
        ('split=%d'):format(#inputs) -- duplicate input video into several
    }
    -- Specify video outputs for the split filter above
    for _, id in ipairs(input_ids) do
        table.insert(vin_filter, ('[v%s]'):format(id))
    end
    table.insert(filters, table.concat(vin_filter))

    -- Initial filter for the input audio
    local ain_filter = {
        '[0:a]', -- input audio
        ('asplit=%d'):format(#inputs) -- duplicate input audio into several
    }
    -- Specify audio outputs for the split filter above
    for _, id in ipairs(input_ids) do
        table.insert(ain_filter, ('[a%s]'):format(id))
    end
    table.insert(filters, table.concat(ain_filter))

    -- Start building out inputs list for the final concat filter
    local trimmed_vins, trimmed_ains = '', ''
    -- Create a/v filters for trimming segments
    for i = 1, #inputs do
        local id = input_ids[i]
        local segments = inputs[i]

        -- specify inputs for the concat filter to apply at the end
        trimmed_vins = trimmed_vins .. ('[v%st]'):format(id)
        trimmed_ains = trimmed_ains .. ('[a%st]'):format(id)

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
            ('[v%s]'):format(id), -- video segment id
            ('select=\'%s\','):format(selects), -- the filter that trims the input
            'setpts=N/FRAME_RATE/TB', -- constructs correct timestamps for output
            ('[v%st]'):format(id) -- trimmed video output for current segment to concat later
        }
        table.insert(filters, table.concat(vsel_filter))

        local asel_filter = {
            ('[a%s]'):format(id), -- audio segment id
            ('aselect=\'%s\','):format(selects), -- the filter that trims the input
            'asetpts=N/SR/TB', -- constructs correct timestamps for output
            ('[a%st]'):format(id) -- trimmed audio output for current segment to concat later
        }
        table.insert(filters, table.concat(asel_filter))
    end

    vconcat_filter = {
        trimmed_vins, -- list of trimmed inputs built earlier
        ('concat=n=%d:v=1:a=0,'):format(#inputs), -- concat the video inputs
        'format=pix_fmts=yuv420p', -- convert video back to an appropriate pixel format
        '[vo]' -- the final video output
    }
    table.insert(filters, table.concat(vconcat_filter))

    aconcat_filter = {
        trimmed_ains, -- list of trimmed inputs built earlier
        ('concat=n=%d:v=0:a=1'):format(#inputs), -- concat the audio inputs
        '[ao]' -- the final video output
    }
    table.insert(filters, table.concat(aconcat_filter))

    return table.concat(filters, ';')
end

--------------------
-- ENCODING UTILS --
--------------------

function estimate_frames(segment_inputs)
    local fr = (aegisub.ms_from_frame(1001) - aegisub.ms_from_frame(1)) / 1000
    local frame_count = 0
    for _, segments in ipairs(segment_inputs) do
        for _, segment in ipairs(segments) do
            frame_count = frame_count +
                              math.floor((segment[2] - segment[1]) / fr)
        end
    end
    return frame_count
end

function run_as_batch(cmd, callback, mode, debug)
    local temp_file = aegisub.decode_path('?temp/clipper.bat')
    local fh = io.open(temp_file, 'w')
    fh:write('setlocal\r\n')
    fh:write(cmd .. '\r\n')
    if debug then
        fh:write('pause\r\n')
    else
        fh:write('if %ERRORLEVEL% GEQ 1 pause\r\n')
    end
    fh:write('endlocal\r\n')
    fh:close()

    local res = nil
    -- If a callback is provided, run it on the process output
    if callback ~= nil then
        if mode == nil then mode = 'r' end
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

    local cmd = ('"%s" -show_streams -select_streams v:0 "%s"'):format(FFPROBE,
                                                                     video)

    local res = run_as_batch(cmd, function(pipe)
        for line in pipe:lines() do
            if line:match('^color') then
                local key, value = line:match('^([%w_]+)=(%w+)$')
                if key then values[key] = value end
            end
        end
    end)

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

function encode_cmd(video, ss, to, options, filter, output, logfile_path)
    local command = {
        ('"%s"'):format(FFMPEG),
        ('-ss %s -to %s -i "%s" -copyts'):format(ss, to, video), options,
        ('-filter_complex "%s" -map "[vo]" -map "[ao]"'):format(filter),
        ('-color_primaries %s -color_trc %s -colorspace %s'):format(
            id_colorspace(video)), ('"%s"'):format(output)
    }

    local frame_ms = aegisub.ms_from_frame(1) - aegisub.ms_from_frame(0)
    if frame_ms <= 20 then
        table.insert(command, 2, ('-itsoffset -%0.3f'):format(frame_ms / 1000))
    end

    local set_env = ('set "FFREPORT=file=%s:level=32"\r\n'):format(
                        logfile_path:gsub('\\', '\\\\'):gsub(':', '\\:'))

    return set_env .. table.concat(command, ' ')
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

    dialog = {
        -- Top left margin
        {class = 'label', label = '    ', x = 0, y = 0, width = 1, height = 1},
        {class = 'label', label = message, x = 1, y = 1, width = 1, height = 1}
    }

    if extra ~= nil and type(extra) == 'table' then
        for _, control in ipairs(extra) do table.insert(dialog, control) end
    end

    -- Bottom right margin
    table.insert(dialog, {
        class = 'label',
        label = '    ',
        x = 2,
        y = dialog[#dialog].y + 1,
        width = 1,
        height = 1
    })

    local is_okay = nil
    while is_okay ~= 'OK' do
        is_okay, results = aegisub.dialog.display(dialog, buttons, button_ids)

        if is_okay == 'Copy link' then clipboard.set(link) end
    end
    return results
end

function show_help(key, message, show_hide_confirmation)
    if global_config['skip_help'][key] ~= nil then return end

    if show_hide_confirmation == nil then show_hide_confirmation = true end

    local extras = nil
    if show_hide_confirmation then
        extras = {
            {
                class = 'checkbox',
                label = 'Don\'t show this message again',
                name = 'skip',
                value = false,
                x = 1,
                y = 3,
                width = 1,
                height = 1
            }
        }
    end

    results = show_info(message, extras)

    if results['skip'] then global_config['skip_help'][key] = true end
end

function init_config()
    global_config['preset'] = table.keys(ENCODE_PRESETS)[1]
    global_config['skip_help'] = {}

    show_help('welcome', 'Welcome to Clipper! If this is your first time\n' ..
                  'using Clipper, please read the guide here:\n\n' ..
                  'https://idolactivities.github.io/vtuber-things/guides/clipper.html#usage',
              false)

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
        if line and line:sub(1, 1) ~= '#' and line:sub(1, 1) ~= ';' then
            option, value = line:match('(%S+)%s*[=:]%s*(.*)')

            -- Lists always end in a comma
            if value:sub(-1) == ',' then
                values = {}
                -- But we store them as keys for easy indexing
                for k in value:gmatch('%s*([^,]+),') do
                    values[k] = true
                end
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
        {class = 'label', label = 'Preset', x = 0, y = 0, width = 1, height = 1},
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
            class = 'checkbox',
            name = 'debug',
            label = 'Debug mode',
            value = false,
            x = 0,
            y = 2,
            width = 2,
            height = 1
        }
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
    local debug = results['debug']
    local output_path = work_dir .. results['clipname'] ..
                            ENCODE_PRESETS[results['preset']]['extension']
    local options = ENCODE_PRESETS[results['preset']]['options']

    if file_exists(output_path) then
        if output_path == video_path then
            show_info(('The specified output file (%s) is the same as\n' ..
                          'the input file, which isn\'t allowed. Specify\n' ..
                          'a different clip name instead.'):format(output_path))
            aegisub.cancel()
        end
        confirm_overwrite(output_path)
        options = options .. ' -y'
    end

    local logfile_path = work_dir .. clipname .. '_encode.log'

    local segment_inputs = manual_segment(sub, sel)

    if #segment_inputs == 0 or #segment_inputs[1] == 0 then
        show_info('Unable to find or create segments to clip.\n' ..
                      'Does your selection contain lines with\n' ..
                      'non-zero duration?')
        aegisub.cancel()
    end

    -- Generate a ffmpeg filter of selects for the line segments
    local filter = filter_complex(segment_inputs, ass_path)

    -- Identify earliest and latest points in the clip so that we can limit
    -- reading the input file to just the section we need (++execution speed)
    local seek_start = math.floor(segment_inputs[1][1][1] / 1000)
    local seek_end = math.ceil(segment_inputs[1][1][2] / 1000)
    for _, segments in ipairs(segment_inputs) do
        local segment_start = math.floor(segments[1][1] / 1000)
        local segment_end = math.ceil(segments[#segments][2] / 1000)
        if seek_start > segment_start then seek_start = segment_start end
        if seek_end < segment_end then seek_end = segment_end end
    end
    -- Add extra leeway to the seek
    seek_end = seek_end + 5

    local cmd = encode_cmd(video_path, seek_start, seek_end, options, filter,
                           output_path, logfile_path)

    local total_frames = estimate_frames(segment_inputs)

    aegisub.progress.task('Encoding your video...')
    if debug then
        aegisub.debug.out(cmd .. '\n')
    end
    res = run_as_batch(cmd, nil, nil, debug)

    if res == nil then
        show_info(('FFmpeg failed to complete! Try the troubleshooting\n' ..
                      'here to figure out what\'s wrong:\n\n' ..
                      'https://idolactivities.github.io/vtuber-things/guides/clipper.html#troubleshooting\n\n' ..
                      'Detailed information saved to:\n\n%s'):format(
                      logfile_path))
        aegisub.cancel()
    end

    -- The user doesn't need to see the log file unless the encoding fails
    os.remove(logfile_path)
end

function validate_clipper(sub, sel, _)
    if aegisub.decode_path('?script') == '?script' or
        aegisub.decode_path('?video') == '?video' then return false end
    return true
end

aegisub.register_macro(script_name, script_description, clipper,
                       validate_clipper)

