--- Check if a file exists and is readable
-- Use this for verifying necessary files exist or in overwrite checks
-- @param path string: path to the file
-- @return bool: true if file exists, false if not
local function file_exists(path)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

--- Splits a filename into its name and extension
-- @param filename string: the filename
-- @return table: the separated filename and extension in 2 elements
local function split_ext(filename)
    return string.match(filename, "(.-)%.([^%.]+)$")
end

--- Asks user to confirm when overwriting a file
-- @param path string: path to a file that exists
local function confirm_overwrite(path)
    local config = {
        {
            class = "label",
            label = ("Are you sure you want to overwrite %s?"):format(path),
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

local util = {
    file_exists = file_exists,
    split_ext = split_ext,
    confirm_overwrite = confirm_overwrite
}

return util

