--[[
    DaVinci Resolve Marker Importer
    =================================
    Imports markers from a CSV file into the currently active timeline.

    CSV Schema
    ----------
    Required: timecode, label, color, note
    Optional: TC IN, TC Out, Duration

    Install
    -------
    Copy to:
        /Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/

    Run via: Workspace ▸ Scripts ▸ Utility ▸ marker_importer
--]]

------------------------------------------------------------------------
-- Color mapping
------------------------------------------------------------------------
local COLOR_MAP = {
    blue="Blue",    cyan="Cyan",     green="Green",  yellow="Yellow",
    red="Red",      pink="Pink",     purple="Purple", fuchsia="Fuchsia",
    magenta="Fuchsia", rose="Rose",  lavender="Lavender", sky="Sky",
    mint="Mint",    lemon="Lemon",   sand="Sand",    cocoa="Cocoa",
    cream="Cream",
}
local DEFAULT_COLOR = "Blue"

------------------------------------------------------------------------
-- Timecode → absolute frame count from 00:00:00:00
------------------------------------------------------------------------
local function tcToFrames(tc, fps)
    tc = tostring(tc):gsub(";", ":")
    local h, m, s, f = tc:match("^%s*(%d+):(%d+):(%d+):(%d+)%s*$")
    if not h then
        error("Invalid timecode: '" .. tc .. "'")
    end
    local n = math.floor(fps + 0.5)   -- nominal fps (24, 25, 30 …)
    return tonumber(h)*3600*n + tonumber(m)*60*n + tonumber(s)*n + tonumber(f)
end

------------------------------------------------------------------------
-- CSV line parser — handles quoted fields and embedded commas
------------------------------------------------------------------------
local function parseLine(line)
    local fields, i = {}, 1
    while i <= #line do
        if line:sub(i, i) == '"' then
            -- Quoted field
            i = i + 1
            local buf = {}
            while i <= #line do
                local c = line:sub(i, i)
                if c == '"' then
                    if line:sub(i+1, i+1) == '"' then   -- escaped quote
                        buf[#buf+1] = '"'; i = i + 2
                    else
                        i = i + 1; break
                    end
                else
                    buf[#buf+1] = c; i = i + 1
                end
            end
            fields[#fields+1] = table.concat(buf)
            if line:sub(i, i) == "," then i = i + 1 end
        else
            -- Unquoted field
            local j = line:find(",", i, true)
            if j then
                fields[#fields+1] = line:sub(i, j-1)
                i = j + 1
            else
                fields[#fields+1] = line:sub(i)
                break
            end
        end
    end
    -- Handle line ending with a comma → trailing empty field
    if line:sub(-1) == "," then fields[#fields+1] = "" end
    return fields
end

------------------------------------------------------------------------
-- Parse the Duration cell to an integer frame count
------------------------------------------------------------------------
local function parseDuration(raw, fps)
    raw = (raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return 1 end
    if raw:find("[;:]") then
        local ok, v = pcall(tcToFrames, raw, fps)
        return ok and math.max(1, v) or 1
    end
    local n = tonumber(raw)
    return n and math.max(1, math.floor(n)) or 1
end

------------------------------------------------------------------------
-- Read and validate the CSV file
------------------------------------------------------------------------
local function parseCSV(path, fps)
    local fh = io.open(path, "rb")   -- binary mode so we see exact bytes
    if not fh then error("Cannot open file: " .. path) end

    -- Read header; strip UTF-8 BOM and trailing \r if present
    local headerLine = (fh:read("*l") or "")
        :gsub("^\239\187\191", "")   -- UTF-8 BOM
        :gsub("\r$", "")             -- Windows CRLF

    local rawHeaders = parseLine(headerLine)
    local hIdx = {}
    for i, h in ipairs(rawHeaders) do
        local norm = h:lower():gsub("^%s+", ""):gsub("%s+$", "")
        hIdx[norm] = i
    end

    -- Validate required columns
    for _, col in ipairs({"timecode", "label", "color", "note"}) do
        if not hIdx[col] then
            fh:close()
            error("CSV is missing required column: '" .. col .. "'")
        end
    end

    -- Helper: get a trimmed field value by column name
    local function get(fields, name)
        local idx = hIdx[name:lower()]
        if not idx then return "" end
        return (fields[idx] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local rows, rowNum = {}, 2
    for line in fh:lines() do
        line = line:gsub("\r$", "")   -- strip trailing \r from Windows files
        if line:gsub("%s", "") ~= "" then
            local f = parseLine(line)
            rows[#rows+1] = {
                timecode = get(f, "timecode"),
                label    = get(f, "label"),
                color    = get(f, "color"):lower(),
                note     = get(f, "note"),
                tc_in    = get(f, "tc in"),
                tc_out   = get(f, "tc out"),
                duration = parseDuration(get(f, "duration"), fps),
                rowNum   = rowNum,
            }
        end
        rowNum = rowNum + 1
    end
    fh:close()
    return rows
end

------------------------------------------------------------------------
-- Core import — connects to Resolve, converts timecodes, stamps markers
------------------------------------------------------------------------
-- syncLTC      : the LTC timecode at the known sync point (e.g. "14:32:00:00")
-- syncTimelineTC: the timeline timecode at that same sync point (e.g. "01:00:05:12")
local function runImport(csvPath, syncLTC, syncTimelineTC)
    local resolve = bmd.scriptapp("Resolve")
    if not resolve then
        error("Could not connect to DaVinci Resolve. Is it running?")
    end

    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then error("No project is currently open.") end

    local timeline = project:GetCurrentTimeline()
    if not timeline then
        error("No timeline is active. Open one in the Edit page first.")
    end

    resolve:OpenPage("edit")

    local fps        = tonumber(project:GetSetting("timelineFrameRate"))
    local tlStartTC  = timeline:GetStartTimecode()
    local startFrame = tcToFrames(tlStartTC, fps)

    local rows = parseCSV(csvPath, fps)

    -- Auto-detect LTC sync from a "Session Start" label if not supplied.
    -- Matches case-insensitively and allows any separator (space, _, -, etc.)
    local function isSessionStart(row)
        -- The device writes the marker text into the 'note' column; 'label' is empty.
        -- Check both fields so it works regardless of which column has the text.
        local function check(s)
            local n = (s or ""):lower():gsub("[^a-z]", "")
            return n == "sessionstart"
        end
        return check(row.note) or check(row.label)
    end

    if not syncLTC or syncLTC == "" then
        for _, row in ipairs(rows) do
            if isSessionStart(row) then
                syncLTC = row.timecode
                break
            end
        end
    end

    -- Compute the frame offset:
    --   frameId = tcToFrames(ltc) - tcToFrames(syncLTC)        -- offset from sync point in frames
    --           + tcToFrames(syncTimelineTC) - startFrame       -- map to 0-based timeline position
    local ltcOffset
    if syncLTC and syncLTC ~= "" and syncTimelineTC and syncTimelineTC ~= "" then
        ltcOffset = tcToFrames(syncTimelineTC, fps) - tcToFrames(syncLTC, fps) - startFrame
    elseif syncLTC and syncLTC ~= "" then
        -- syncTimelineTC not provided — set timeline start TC to the LTC sync point
        -- so the ruler TC matches the recording device while scrubbing
        ltcOffset = -tcToFrames(syncLTC, fps)
        timeline:SetStartTimecode(syncLTC)
    else
        -- Dump raw parsed fields of the first row so we can see the full structure
        local rawFields = {}
        do
            local fh2 = io.open(csvPath, "rb")
            if fh2 then
                local hdr = (fh2:read("*l") or ""):gsub("\r$",""):gsub("^\239\187\191","")
                local dat = (fh2:read("*l") or ""):gsub("\r$","")
                fh2:close()
                rawFields[#rawFields+1] = "Header: " .. hdr
                rawFields[#rawFields+1] = "Row 2:  " .. dat
                local parsed = parseLine(dat)
                for fi, fv in ipairs(parsed) do
                    rawFields[#rawFields+1] = string.format("  [%d] = %q", fi, fv)
                end
            end
        end
        error("No 'Session Start' marker detected.\n\n"
            .. table.concat(rawFields, "\n") .. "\n\n"
            .. "Enter the LTC sync TC manually.")
    end

    local added, errs = 0, {}

    for _, e in ipairs(rows) do
        local ok, err = pcall(function()
            local frameId = tcToFrames(e.timecode, fps) + ltcOffset

            if frameId < 0 then
                errs[#errs+1] = ("Row %d: %s is before timeline start — skipped"):format(
                    e.rowNum, e.timecode)
                return
            end

            -- Build note text (TC range stored in customData only, not shown in note)
            local note = e.note

            local customData = ('{"ltc":"%s","tc_in":"%s","tc_out":"%s"}')
                :format(e.timecode, e.tc_in, e.tc_out)

            local color = COLOR_MAP[e.color] or DEFAULT_COLOR
            -- Device writes text into 'note'; fall back through label → note → " "
            -- Resolve rejects AddMarker when name is an empty string, so use a space.
            local label = (e.label ~= "" and e.label)
                       or (e.note  ~= "" and e.note)
                       or " "

            timeline:DeleteMarkerAtFrame(frameId)   -- remove any existing marker first
            if timeline:AddMarker(frameId, color, label, note, e.duration, customData) then
                added = added + 1
            else
                errs[#errs+1] = ("Row %d: AddMarker failed at %s (frame %d)."):format(
                    e.rowNum, e.timecode, frameId)
            end
        end)

        if not ok then
            errs[#errs+1] = ("Row %d: %s"):format(e.rowNum, tostring(err))
        end
    end

    -- Build summary
    local tcChanged = (not syncTimelineTC or syncTimelineTC == "") and syncLTC and syncLTC ~= ""
    local syncInfo = tcChanged
        and ("Sync: LTC %s → timeline start  (timeline TC set to %s)"):format(syncLTC, syncLTC)
        or  ("Sync: LTC %s → timeline %s  (timeline starts at %s)"):format(syncLTC or "?", syncTimelineTC, tlStartTC)
    local summary = ("Added %d of %d marker(s) to '%s'.\n%s")
        :format(added, #rows, timeline:GetName(), syncInfo)

    if #errs > 0 then
        local shown = {}
        for i = 1, math.min(#errs, 15) do shown[i] = errs[i] end
        summary = summary .. "\n\n" .. #errs .. " issue(s):\n"
               .. table.concat(shown, "\n")
        if #errs > 15 then
            summary = summary .. ("\n…and %d more."):format(#errs - 15)
        end
    end

    return summary
end

------------------------------------------------------------------------
-- UI  (Fusion UIManager — runs natively inside Resolve)
------------------------------------------------------------------------
local ui   = fu.UIManager
local disp = bmd.UIDispatcher(ui)

local win = disp:AddWindow({
    ID          = "MarkerImporter",
    WindowTitle = "Import Markers from CSV",
    Geometry    = {150, 150, 560, 175},

    ui:VGroup{
        ui:HGroup{
            ui:Label{ Text = "CSV:", Weight = 0 },
            ui:LineEdit{
                ID              = "Path",
                PlaceholderText = "Select a CSV file…",
                ReadOnly        = true,
                Weight          = 1,
            },
            ui:Button{ ID = "Browse", Text = "Browse…", Weight = 0 },
        },
        ui:HGroup{
            ui:Label{ ID = "LabelSyncLTC", Text = "LTC sync TC:", Weight = 0 },
            ui:LineEdit{
                ID              = "SyncLTC",
                PlaceholderText = "Auto-detected from 'Session Start' row — or enter manually  e.g. 14:32:00:00",
                Weight          = 1,
            },
        },
        ui:HGroup{
            ui:Label{ ID = "LabelSyncTL", Text = "Timeline sync TC:", Weight = 0 },
            ui:LineEdit{
                ID              = "SyncTL",
                PlaceholderText = "Timeline TC where the LTC sync point falls  e.g. 01:00:00:00",
                Weight          = 1,
            },
        },
        ui:HGroup{
            ui:CheckBox{ ID = "ShowAdvanced", Text = "Manual sync override", Checked = false, Weight = 1 },
            ui:Button{
                ID      = "Import",
                Text    = "Import Markers",
                Enabled = false,
                Weight  = 0,
            },
            ui:Button{ ID = "Cancel", Text = "Cancel", Weight = 0 },
        },
    },
})

local itm = win:GetItems()

local function setSyncVisible(visible)
    if visible then
        itm.LabelSyncLTC:Show(); itm.SyncLTC:Show()
        itm.LabelSyncTL:Show();  itm.SyncTL:Show()
    else
        itm.LabelSyncLTC:Hide(); itm.SyncLTC:Hide()
        itm.LabelSyncTL:Hide();  itm.SyncTL:Hide()
    end
end

setSyncVisible(false)

win.On.ShowAdvanced.Clicked = function(ev)
    if itm.ShowAdvanced.Checked then
        setSyncVisible(true)
    else
        itm.SyncLTC.Text = ""
        itm.SyncTL.Text  = ""
        setSyncVisible(false)
    end
end

-- Browse button: open a native OS file dialog via Fusion
win.On.Browse.Clicked = function()
    local selected = fu:RequestFile("", {
        FReqType = FREQ_LOADFILE,
        FReqS_Filter = "*.csv",
        FReqS_Title  = "Select Marker CSV",
    })
    if selected and selected ~= "" then
        itm.Path.Text    = selected
        itm.Import.Enabled = true
    end
end

-- Import button
win.On.Import.Clicked = function()
    local path     = itm.Path.Text
    local syncLTC  = itm.SyncLTC.Text:gsub("^%s+", ""):gsub("%s+$", "")
    local syncTL   = itm.SyncTL.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then return end

    win:Hide()

    local ok, result = pcall(runImport, path, syncLTC, syncTL)
    local msg   = ok and result or ("Error:\n" .. tostring(result))
    local title = ok and "Import Complete" or "Import Failed"

    -- Result dialog
    local rWin = disp:AddWindow({
        ID          = "Result",
        WindowTitle = title,
        Geometry    = {150, 150, 520, 260},
        ui:VGroup{
            ui:TextEdit{ ID = "Msg", Text = msg, ReadOnly = true, Weight = 1 },
            ui:Button{   ID = "OK",  Text = "OK",               Weight = 0 },
        },
    })
    rWin.On.OK.Clicked     = function() rWin:Hide(); disp:ExitLoop() end
    rWin.On.Result.Close   = function()              disp:ExitLoop() end
    rWin:Show()
    disp:RunLoop()
    rWin:Hide()

    disp:ExitLoop()
end

win.On.Cancel.Clicked          = function() win:Hide(); disp:ExitLoop() end
win.On.MarkerImporter.Close    = function()             disp:ExitLoop() end

win:Show()
disp:RunLoop()
win:Hide()
