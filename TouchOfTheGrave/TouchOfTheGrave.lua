-- Touch of the Grave Timer: shows when the Undead racial passive can proc again.
--
-- On this client, addons cannot read the combat log (COMBAT_LOG_EVENT_UNFILTERED
-- is forbidden). Thus the addon finds a proc with UNIT_COMBAT: Shadow damage on
-- the target, and a heal on the player. The addon "Touch of the Grave - Tracker"
-- (Wakamama, MIT) uses the same method. It worked in game on 2026-11-04 on a
-- Rogue. The cast event and C_Spell.GetSpellCooldown give only secret values
-- for the proc on this client, thus the addon does not use them.

local ADDON = ...

local SHADOW = 32                       -- school mask of Shadow damage
-- Seconds between the damage and the heal of one proc. The client sends both
-- in the same frame (0.00 s on every measured proc), thus a few frames suffice.
local PAIR_WINDOW = 0.1
-- Classes with Shadow spells of their own that heal the caster. For them,
-- detection stops for a time after a drain spell (see DRAINS).
local SHADOW_CLASSES = { PRIEST = true, WARLOCK = true }
-- Priest and Warlock spells that do Shadow damage and heal the caster, with the
-- time in seconds that they can do it. Detection stops for this time after a
-- cast. This works only when the client shows the spell ID (not a secret).
local DRAINS = {
    [2944] = 24, [19276] = 24, [19277] = 24, [19278] = 24, [19279] = 24, [19280] = 24,  -- Devouring Plague
    [18265] = 30, [18879] = 30, [18880] = 30, [18881] = 30,                            -- Siphon Life
    [6789] = 3, [17925] = 3, [17926] = 3,                                               -- Death Coil
}

-- The passives first (1260189 melee, 1260201 caster), then the proc (1260198).
-- The order is the order in which the addon asks the client for the icon.
local SPELLS = { 1260189, 1260201, 1260198 }
-- Icons to use when the client gives none. forever.warcraftdb.com shows file
-- data ID 136157 (Interface\Icons\Spell_Shadow_FingerOfDeath) for both passives,
-- and 136169 (Spell_Shadow_LifeDrain02) for the proc.
local FALLBACK_ICONS = { 136157, "Interface\\Icons\\Spell_Shadow_FingerOfDeath",
    "Interface\\Icons\\INV_Misc_QuestionMark" }
local DEFAULT_ICD = 15                  -- from the Forever beta notes of 2026-10-27
local MAX_LOG = 50
local MAX_DEBUG = 300                   -- debug lines kept in the saved variables
local MAX_RECENT = 60                   -- combat events kept for the problem report
local MAX_REPORT = 1500                 -- the longest problem report, in characters
local REPORT_EVENTS = 15                -- combat events in a problem report
local OFFER_FIGHTS = 15                 -- fights with no proc before the addon offers a report
-- The form for a problem report. The addon adds the report to this link, so
-- the player only opens the link and sends the form.
local REPORT_URL = "https://github.com/KevSteele/TouchOfTheGrave/issues/new?template=problem.yml"

-- Sounds for "Ready": { saved key, label, SOUNDKIT name }
local SOUNDS = {
    { "raid", "Raid warning", "RAID_WARNING" },
    { "ready", "Ready check", "READY_CHECK" },
    { "alarm", "Alarm clock", "ALARM_CLOCK_WARNING_3" },
    { "click", "Soft click", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
}

local defaults = {
    point = "CENTER", relPoint = "CENTER", x = 0, y = -150,
    locked = false, icd = DEFAULT_ICD, sound = true, debug = false,
    soundChoice = "raid", size = 40, showText = true, flash = true,
}

local db
local frame, icon, cd, text, glow, glowAnim
local muteMark             -- the muted speaker in the bottom right corner
local ToggleSound          -- defined after the options panel (it syncs the panel)
local ShowReport           -- defined after the copy window
local readyAt = 0          -- GetTime() value when the next proc can happen
local lastProc             -- GetTime() value of the last proc
local needHeal             -- true for Priest and Warlock (see SHADOW_CLASSES)
local drainNames = {}      -- localized names of the DRAINS spells, with their times
local pauseUntil = 0       -- GetTime() value when detection can start again
local inCombat, leftCombatAt = false, -100
local hitsAtFightStart = 0 -- the counter of hits on the target when the fight started
local lastShadow, lastHeal -- { t = GetTime(), amount = number or nil }
local category             -- the options page in the Settings API
local settings = {}        -- Settings API objects by saved key, to sync slash commands
local openAfterCombat = false

-- Returns nil in place of a secret value (the same guard as ForeverVO Util.Plain).
local function Plain(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

local function Print(fmt, ...)
    print("|cff8f6cffTotG|r " .. format(fmt, ...))
end

-- Keeps a line in the saved debug log while debug mode is on. The log goes
-- to the saved variables at logout or /reload, and /totg copy shows it.
local function Record(line)
    if not db.debug then
        return
    end
    local log = db.debugLog
    log[#log + 1] = format("%s %.2f  %s", date("%H:%M:%S"), GetTime(), line)
    while #log > MAX_DEBUG do
        table.remove(log, 1)
    end
end

-- The counters for the problem report. They always run, so a player does not
-- start a debug mode before a report. They hold only numbers.
local function Count(key)
    local counts = db.counts
    counts[key] = (counts[key] or 0) + 1
end

-- Keeps one combat event for the problem report: the time, and fixed words.
local function Note(now, unit, action, school)
    local recent = db.recent
    recent[#recent + 1] = format("%.2f %s %s %s", now, unit, action, tostring(tonumber(school) or "hidden"))
    while #recent > MAX_RECENT do
        table.remove(recent, 1)
    end
end

-- A debug line: in chat and in the saved debug log, while debug mode is on.
local function Debug(fmt, ...)
    if not db.debug then
        return
    end
    local line = format(fmt, ...)
    Print("%s", line)
    Record(line)
end

-- "15 s" for a whole number, "12.5 s" for other numbers.
local function Seconds(value)
    return format(value == floor(value) and "%d s" or "%.1f s", value)
end

local function SpellName()
    for _, spellID in ipairs(SPELLS) do
        local name = Plain(C_Spell.GetSpellName(spellID))
        if name then
            return name
        end
    end
    return "Touch of the Grave"
end

local MIN_SIZE, MAX_SIZE = 24, 96   -- icon size in pixels

-- A whole number of pixels from MIN_SIZE to MAX_SIZE.
local function ClampSize(value)
    return math.min(MAX_SIZE, math.max(MIN_SIZE, floor(value + 0.5)))
end

local function ShortestGap()
    local minGap
    for _, entry in ipairs(db.log) do
        if entry.gap and (not minGap or entry.gap < minGap) then
            minGap = entry.gap
        end
    end
    return minGap
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

local function PlayReadySound()
    local kit
    for _, sound in ipairs(SOUNDS) do
        if sound[1] == db.soundChoice then
            kit = SOUNDKIT and SOUNDKIT[sound[3]]
        end
    end
    kit = kit or (SOUNDKIT and SOUNDKIT.RAID_WARNING)
    if kit then
        -- The "Master" channel plays the sound also when game sounds are off.
        pcall(PlaySound, kit, "Master")
    end
end

-- Sets the first icon that the client gives. If the client gives no icon, or
-- gives a secret value, it uses the fallbacks.
local function SetIcon()
    for _, spellID in ipairs(SPELLS) do
        local texture = Plain(C_Spell.GetSpellTexture(spellID))
        if texture then
            icon:SetTexture(texture)
            return
        end
    end
    for _, texture in ipairs(FALLBACK_ICONS) do
        -- SetTexture gives false if it cannot find the file.
        if icon:SetTexture(texture) ~= false then
            return
        end
    end
end

-- The ready state is the icon at full brightness, with no text.
local function SetReadyLook()
    icon:SetDesaturated(false)
    icon:SetVertexColor(1, 1, 1)
    text:SetText("")
end

local function BecomeReady(alert)
    readyAt = 0
    CooldownFrame_Clear(cd)
    SetReadyLook()
    if alert then
        if db.flash then
            glowAnim:Stop()
            glowAnim:Play()
        end
        if db.sound then
            PlayReadySound()
        end
    end
end

local function StartCooldown(startTime, duration)
    readyAt = startTime + duration
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.7, 0.7, 0.7)
    CooldownFrame_Set(cd, startTime, duration, true)
end

local function ShowTooltip()
    -- The default anchor, as the action bars use: the bottom right of the
    -- screen, or the place that the player set for tooltips.
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    end
    GameTooltip:AddLine(SpellName(), 1, 1, 1)
    local left = readyAt - GetTime()
    if readyAt == 0 or left <= 0 then
        GameTooltip:AddDoubleLine("State", "Ready", 1, 0.82, 0, 0.3, 1, 0.3)
    else
        GameTooltip:AddDoubleLine("State", format("%.1f s left", left), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Internal cooldown", Seconds(db.icd), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Since last proc",
        lastProc and format("%d s", GetTime() - lastProc) or "no proc yet", 1, 0.82, 0, 1, 1, 1)
    local minGap = ShortestGap()
    GameTooltip:AddDoubleLine("Shortest gap", minGap and Seconds(minGap) or "none yet", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Sound alert", db.sound and "on" or "off", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine("Left-click: sound on or off. Right-click: options.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(db.locked and "Unlock in the options to move." or "Drag: move.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("A problem? Type /totg report.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local elapsedSum = 0
local function OnUpdate(_, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum < 0.1 then
        return
    end
    elapsedSum = 0
    if readyAt ~= 0 then
        local left = readyAt - GetTime()
        if left <= 0 then
            BecomeReady(true)
        else
            text:SetText(format(left >= 10 and "%d" or "%.1f", left))
        end
    end
    if GameTooltip:IsOwned(frame) then
        ShowTooltip()
    end
end

-- The frame always takes the mouse, for the tooltip and the right-click. A
-- locked frame does not move. An unlocked frame shows a thin outline, so that
-- the player can find it. A locked frame shows only the icon.
local function ApplyLock()
    frame:EnableMouse(true)
    for _, edge in ipairs(frame.outline) do
        edge:SetShown(not db.locked)
    end
end

local function ApplyPosition()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function ApplyLook()
    frame:SetSize(db.size, db.size)
    glow:SetSize(db.size * 1.9, db.size * 1.9)   -- the glow texture has a wide empty edge
    -- The countdown number is 40% of the icon size, with an outline.
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", floor(db.size * 0.4 + 0.5), "OUTLINE")
    text:SetShown(db.showText)
    -- The muted speaker is 40% of the icon size, in the bottom right corner.
    local mute = math.max(10, floor(db.size * 0.4 + 0.5))
    muteMark:SetSize(mute, mute)
    muteMark.line:SetSize(mute * 1.2, math.max(2, floor(mute * 0.14 + 0.5)))
end

-- The muted speaker shows only while the sound alert is off.
local function ApplyMute()
    muteMark:SetShown(not db.sound)
end

local function OpenOptions()
    if not category then
        Print("the options panel is not available on this client. Type /totg help.")
    elseif InCombatLockdown() then
        openAfterCombat = true
        Print("the options open when combat ends.")
    else
        Settings.OpenToCategory(category:GetID())
    end
end

local function CreateDisplay()
    frame = CreateFrame("Frame", "TouchOfTheGraveFrame", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    -- A left-click turns the sound alert on or off. A drag is not a click.
    local dragged = false
    frame:SetScript("OnMouseDown", function() dragged = false end)
    frame:SetScript("OnDragStart", function(self)
        dragged = true
        if not db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            OpenOptions()
        elseif button == "LeftButton" and not dragged then
            ToggleSound()
        end
    end)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Four lines of 1 pixel around the icon: the outline of an unlocked frame.
    frame.outline = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -1 },
        { "TOPLEFT", "BOTTOMLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 },
    }
    for _, e in ipairs(edges) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(1, 1, 1, 0.6)
        edge:SetPoint(e[1], frame, e[1], e[3], e[4])
        edge:SetPoint(e[2], frame, e[2], e[3], e[4])
        if e[3] == 0 then edge:SetHeight(1) else edge:SetWidth(1) end
        frame.outline[#frame.outline + 1] = edge
    end

    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    SetIcon()

    cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetHideCountdownNumbers(true)

    -- The countdown number sits in the center of the icon, on a frame above the
    -- cooldown sweep. A font string on the main frame would be under the sweep.
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
    text = overlay:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1)

    -- A speaker with a red line through it: the sound alert is off.
    muteMark = CreateFrame("Frame", nil, overlay)
    muteMark:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    local backing = muteMark:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(0, 0, 0, 0.6)   -- dark, so the mark reads on bright icon art
    local speaker = muteMark:CreateTexture(nil, "ARTWORK")
    speaker:SetAllPoints()
    speaker:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    muteMark.line = muteMark:CreateTexture(nil, "OVERLAY")
    muteMark.line:SetPoint("CENTER")
    muteMark.line:SetColorTexture(1, 0.1, 0.1, 1)
    muteMark.line:SetRotation(math.rad(-45))

    glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    glow:SetAlpha(0)
    glowAnim = glow:CreateAnimationGroup()
    glowAnim:SetLooping("BOUNCE")
    local fade = glowAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.3)
    local loops = 0
    glowAnim:SetScript("OnPlay", function() loops = 0 end)
    glowAnim:SetScript("OnLoop", function(self)
        loops = loops + 1
        if loops >= 6 then self:Stop() end
    end)
    glowAnim:SetScript("OnStop", function() glow:SetAlpha(0) end)

    frame:SetScript("OnUpdate", OnUpdate)
    ApplyPosition()
    ApplyLock()
    ApplyLook()
    ApplyMute()
    SetReadyLook()
end

-- ---------------------------------------------------------------------------
-- Options panel (Game Menu > Options > AddOns), built as ForeverVO builds its own
-- ---------------------------------------------------------------------------

local function Checkbox(key, name, tooltip, onChange)
    local setting = Settings.RegisterAddOnSetting(category, "TOTG_" .. key, key, db,
        Settings.VarType.Boolean, name, defaults[key])
    if onChange then
        setting:SetValueChangedCallback(function(_, value) onChange(value) end)
    end
    Settings.CreateCheckbox(category, setting, tooltip)
    settings[key] = setting
end

local function Slider(key, name, tooltip, minValue, maxValue, step, formatter, onChange)
    local setting = Settings.RegisterProxySetting(category, "TOTG_" .. key, Settings.VarType.Number,
        name, defaults[key], function() return db[key] end, function(value)
            db[key] = value
            if onChange then onChange(value) end
        end)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, options, tooltip)
    settings[key] = setting
end

local function SoundDropdown()
    local function GetValue()
        for index, sound in ipairs(SOUNDS) do
            if sound[1] == db.soundChoice then return index end
        end
        return 1
    end
    local function SetValue(index)
        if SOUNDS[index] then
            db.soundChoice = SOUNDS[index][1]
            PlayReadySound()   -- let the player hear the choice
        end
    end
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        for index, sound in ipairs(SOUNDS) do
            container:Add(index, sound[2])
        end
        return container:GetData()
    end
    local setting = Settings.RegisterProxySetting(category, "TOTG_soundChoice", Settings.VarType.Number,
        "Sound", 1, GetValue, SetValue)
    Settings.CreateDropdown(category, setting, GetOptions, "The sound that plays when the cooldown is over.")
end

local function CreateOptions()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Touch of the Grave Timer")
    Slider("icd", "Internal cooldown", "The time in seconds after a proc before the next proc can happen.",
        5, 60, 1, function(value) return Seconds(value) end)
    Checkbox("sound", "Sound when ready", "Play a sound when the cooldown is over. A left-click on the icon also turns it on or off.", ApplyMute)
    SoundDropdown()
    Checkbox("flash", "Flash when ready", "Flash the icon when the cooldown is over.")
    Checkbox("showText", "Show the countdown text", "Show the seconds left in the center of the icon.", ApplyLook)
    Checkbox("locked", "Lock the frame", "Stop the frame from moving. Clear it to drag the frame.", ApplyLock)
    Slider("size", "Icon size", "The width and height of the icon in pixels.", MIN_SIZE, MAX_SIZE, 1,
        function(value) return format("%d px", value) end, ApplyLook)
    -- A button for the problem report. If this client has no such control,
    -- the page stays as it is, and /totg report does the same.
    pcall(function()
        layout:AddInitializer(CreateSettingsButtonInitializer("Problem report", "Open the report",
            function() ShowReport() end,
            "Open a window with a short report and a link to the report form. The report has no character name.", true))
    end)
    Settings.RegisterAddOnCategory(category)
end

-- Gives a value that a slash command changed to the options panel.
local function SyncSetting(key)
    if settings[key] then
        settings[key]:SetValue(db[key])
    end
end

-- Turns the sound alert on or off: from a left-click on the icon or /totg sound.
function ToggleSound()
    db.sound = not db.sound
    ApplyMute()
    SyncSetting("sound")
    Print("sound alert %s.", db.sound and "on" or "off")
end

-- ---------------------------------------------------------------------------
-- Proc detection
-- ---------------------------------------------------------------------------

local function LogProc(gap, pair)
    local log = db.log
    log[#log + 1] = { at = date("%Y-%m-%d %H:%M:%S"), gap = gap, pair = pair }
    while #log > MAX_LOG do
        table.remove(log, 1)
    end
end

-- Starts the timer from a proc. `pair` is the time in seconds from the hit to
-- the heal; a negative value means the heal came first.
local function OnProc(pair)
    local now = GetTime()
    if lastProc and now - lastProc < 1 then
        return   -- one proc can give more than one event
    end
    local gap = lastProc and (now - lastProc) or nil
    if gap and gap < db.icd - 0.5 then
        -- A real proc cannot come inside the internal cooldown. Thus the hit
        -- and the heal came from two sources (another player, an item), or
        -- the cooldown value is wrong. The timer keeps its time.
        local line = format("match %.1f s after the last proc, inside the cooldown of %s. Ignored. If this repeats, the cooldown may be shorter: /totg icd <seconds>.",
            gap, Seconds(db.icd))
        Print("%s", line)
        Record(line)
        Count("ignored")
        return
    end
    lastProc = now
    Count("procs")
    LogProc(gap and floor(gap * 10 + 0.5) / 10, floor(pair * 100 + 0.5) / 100)
    Debug("proc found, gap %s s, %s %.2f s apart", gap and format("%.1f", gap) or "?",
        pair < 0 and "heal then hit" or "hit then heal", math.abs(pair))
    StartCooldown(now, db.icd)
end

-- Priest and Warlock only: stop detection after a drain spell (see DRAINS).
local function OnSpellcast(_, _, spellID)
    spellID = Plain(spellID)
    local name = spellID and Plain(C_Spell.GetSpellName(spellID))
    local pause = (spellID and DRAINS[spellID]) or (name and drainNames[name])
    if pause then
        pauseUntil = math.max(pauseUntil, GetTime() + pause + 0.5)
    end
end

-- True if the two amounts can be from one proc. An unknown amount matches.
local function SameAmount(a, b)
    return a == nil or b == nil or a == b
end

-- A proc does Shadow damage to the target and heals the player by the
-- same amount. The heal must come in PAIR_WINDOW seconds, before or after the
-- hit. A hit alone is not a proc: items such as Thorncursed Grips do Nature
-- damage to the target on each melee hit, and they do not heal the player.
local function OnUnitCombat(unit, action, _, amount, school)
    unit, action, school = Plain(unit), Plain(action), Plain(school)
    Count("events")
    if not unit or not action then
        Count("hidden")   -- the client hid the unit or the action
        return
    end
    local now = GetTime()
    local isTargetHit = unit == "target" and action == "WOUND"
    local isShadowHit = isTargetHit and tonumber(school) == SHADOW
    local isHeal = unit == "player" and action == "HEAL"
    if isTargetHit then
        Count("targetHits")
        local schools = db.counts.schools
        local key = tostring(tonumber(school) or "hidden")
        schools[key] = (schools[key] or 0) + 1
    end
    -- Physical hits (school 1) are too many for the list. The counter has them.
    if isHeal or (isTargetHit and tonumber(school) ~= 1) then
        Note(now, unit, action, isHeal and 0 or school)
    end
    if isShadowHit then Count("shadowHits") end
    if isHeal then Count("heals") end
    if not isShadowHit and not isHeal then
        if db.debug == "all" and action == "WOUND" then
            -- Shows the school of the hits the filter drops, such as an item effect.
            Debug("other hit: %s school %s amount %s", unit, tostring(school or "?"),
                tostring(tonumber(Plain(amount)) or "?"))
        end
        return
    end
    amount = tonumber(Plain(amount))
    Debug("unit combat: %s %s %s", unit, action, tostring(amount or "?"))
    local channel = UnitChannelInfo("player")
    -- A secret counts as a channel. The test stops before it compares a secret.
    local channeling = (issecretvalue and issecretvalue(channel)) or channel ~= nil
    if needHeal and (now < pauseUntil or channeling) then
        lastShadow, lastHeal = nil, nil   -- a drain spell of the player is active
        Count("paused")
        return
    end
    if isShadowHit then
        -- Shadow damage out of combat is not from the player. A proc on the
        -- last monster can come just after combat ends, thus allow 2 seconds.
        if not inCombat and now - leftCombatAt > 2 then
            Count("outOfCombat")
            return
        end
        if lastHeal and now - lastHeal.t <= PAIR_WINDOW and SameAmount(amount, lastHeal.amount) then
            local pair = lastHeal.t - now   -- the heal came first
            lastShadow, lastHeal = nil, nil
            Count("pairs")
            OnProc(pair)
        else
            lastShadow = { t = now, amount = amount }
        end
    elseif lastShadow and now - lastShadow.t <= PAIR_WINDOW and SameAmount(amount, lastShadow.amount) then
        local pair = now - lastShadow.t   -- the hit came first
        lastShadow, lastHeal = nil, nil
        Count("pairs")
        OnProc(pair)
    else
        lastHeal = { t = now, amount = amount }
    end
end

-- ---------------------------------------------------------------------------
-- The copy window: text in an edit box, selected, for Ctrl+C. It shows the
-- debug lines, or the problem report with the link to the report form.
-- ---------------------------------------------------------------------------

local copyFrame

local function Select(box)
    box:SetFocus()
    box:HighlightText()
end

-- `link` and `steps` are nil for the debug lines.
local function ShowCopyFrame(title, text, link, steps)
    if not copyFrame then
        local f = CreateFrame("Frame", "TouchOfTheGraveCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(620, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -18)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll = scroll
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(540)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(box)
        f.box = box
        -- The parts for the problem report: the steps, the link, and two buttons.
        f.steps = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.steps:SetPoint("TOPLEFT", 24, -42)
        f.steps:SetPoint("RIGHT", -24, 0)
        f.steps:SetJustifyH("LEFT")
        f.link = CreateFrame("EditBox", nil, f)
        f.link:SetAutoFocus(false)
        f.link:SetFontObject(ChatFontNormal)
        f.link:SetPoint("TOPLEFT", 24, -92)
        f.link:SetPoint("RIGHT", -24, 0)
        f.link:SetHeight(18)
        f.link:SetScript("OnEscapePressed", function() f:Hide() end)
        f.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        -- The link must stay as it is, also if the player types in the box.
        f.link:SetScript("OnTextChanged", function(self, byUser)
            if byUser and f.linkText then
                self:SetText(f.linkText)
                self:HighlightText()
            end
        end)
        local function CopyButton(label, x, target)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(150, 22)
            b:SetPoint("BOTTOM", x, 18)
            b:SetText(label)
            b:SetScript("OnClick", function() Select(target) end)
            return b
        end
        f.selectLink = CopyButton("Select the link", 0, f.link)
        tinsert(UISpecialFrames, "TouchOfTheGraveCopyFrame")
        copyFrame = f
    end
    local f = copyFrame
    local report = link ~= nil
    f.title:SetText(title)
    f.linkText = link
    f.link:SetText(link or "")
    f.steps:SetText(steps or "")
    for _, part in ipairs({ f.steps, f.link, f.selectLink }) do
        part:SetShown(report)
    end
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", 22, report and -118 or -44)
    f.scroll:SetPoint("BOTTOMRIGHT", -44, report and 48 or 22)
    f.box:SetText(text)
    f:Show()
    Select(report and f.link or f.box)
end

local function ShowDebugLines()
    local lines = db.debugLog
    ShowCopyFrame("Touch of the Grave debug lines. The text is selected: press Ctrl+C.",
        #lines > 0 and table.concat(lines, "\n") or "No debug lines yet. Type /totg debug, then fight.")
end

-- ---------------------------------------------------------------------------
-- The problem report: numbers and fixed words only. No character name, no
-- realm, and no text from the chat or from other players.
-- ---------------------------------------------------------------------------

-- A short word from the client, with only letters and digits.
local function Word(value)
    value = Plain(value)
    if type(value) ~= "string" and type(value) ~= "number" then
        return "?"
    end
    local word = tostring(value):gsub("[^%w%.%-]", ""):sub(1, 20)
    return word ~= "" and word or "?"
end

local function BuildReport()
    local c = db.counts
    local lines = {}
    local function Add(fmt, ...)
        lines[#lines + 1] = format(fmt, ...)
    end
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local okV, version = pcall(getMeta, ADDON, "Version")
    local okB, game, build, _, toc = pcall(GetBuildInfo)
    local _, classFile = UnitClass("player")
    Add("Touch of the Grave Timer report")
    Add("addon %s | game %s build %s interface %s | locale %s", okV and Word(version) or "?",
        okB and Word(game) or "?", okB and Word(build) or "?", okB and Word(toc) or "?", Word(GetLocale and GetLocale()))
    Add("class %s | level %s | cooldown setting %s | debug %s", Word(classFile), Word(UnitLevel("player")),
        Word(db.icd), Word(tostring(db.debug)))
    Add("events %d | hidden %d | hits on target %d | Shadow hits %d | heals on you %d", c.events or 0, c.hidden or 0,
        c.targetHits or 0, c.shadowHits or 0, c.heals or 0)
    Add("pairs %d | procs %d | ignored inside cooldown %d | paused %d | out of combat %d", c.pairs or 0, c.procs or 0,
        c.ignored or 0, c.paused or 0, c.outOfCombat or 0)
    local schools = {}
    for school, n in pairs(c.schools) do
        schools[#schools + 1] = Word(school) .. "=" .. Word(n)
    end
    table.sort(schools)
    Add("hit schools: %s", #schools > 0 and table.concat(schools, " ") or "none")
    local log = db.log
    Add("procs in the log: %d. Last gaps and hit-to-heal times:", #log)
    for i = math.max(1, #log - 4), #log do
        local e = log[i]
        Add("  gap %s pair %s", Word(e.gap or "-"), Word(e.pair or "-"))
    end
    local recent = db.recent
    Add("last events (time, unit, action, school; school 32 is Shadow):")
    for i = math.max(1, #recent - REPORT_EVENTS + 1), #recent do
        Add("  %s", tostring(recent[i]):gsub("[^%w%. ]", ""):sub(1, 40))
    end
    if #recent == 0 then
        Add("  none. Fight a monster until the racial procs, then open the report again.")
    end
    return table.concat(lines, "\n"):sub(1, MAX_REPORT)
end

-- The probable cause, from the counters. The player sees it in the window,
-- and the form gets it as the description.
local function Cause()
    local c = db.counts
    local hiddenSchool = c.schools.hidden or 0
    if (c.procs or 0) > 0 then
        return format("The addon found %d procs. If the timer is wrong, the cooldown setting can be wrong.", c.procs)
    elseif (c.events or 0) == 0 then
        return "The addon saw no combat event. Fight a monster, then open the report again."
    elseif (c.shadowHits or 0) == 0 and ((c.hidden or 0) > 0 or hiddenSchool > 0) then
        return "The game hides the combat data here, so the addon cannot see a proc."
    elseif (c.shadowHits or 0) == 0 then
        return "The addon saw no Shadow damage on your target. Each proc must be on your target."
    elseif (c.heals or 0) == 0 then
        return "The addon saw Shadow hits, but no heal on you. It needs the heal to know a proc."
    elseif (c.pairs or 0) == 0 then
        return "The addon saw Shadow hits and heals, but not at the same time."
    end
    return "The addon ignored each match. Detection was paused, or the match came inside the cooldown."
end

-- Makes text safe for a link: letters, digits, and four signs stay.
local function UrlEncode(text)
    return (text:gsub("[^%w%-%._~]", function(ch) return format("%%%02X", ch:byte()) end))
end

function ShowReport()
    local report, cause = BuildReport(), Cause()
    local link = REPORT_URL .. "&title=" .. UrlEncode("Problem report")
        .. "&what=" .. UrlEncode("Self-check of the addon: " .. cause) .. "&report=" .. UrlEncode(report)
    ShowCopyFrame("Touch of the Grave problem report", report, link,
        cause .. "\n\nTo send the report: copy the link (Ctrl+C), open it in a browser, and click the green button.\nThe link has the text below in it. It has no character name.")
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

local function Stats()
    local log, minGap = db.log, ShortestGap()
    Print("%d procs in the log. Shortest gap: %s. ICD setting: %s.",
        #log, minGap and Seconds(minGap) or "none", Seconds(db.icd))
    local longest
    for _, e in ipairs(log) do
        if e.pair and (not longest or math.abs(e.pair) > longest) then
            longest = math.abs(e.pair)
        end
    end
    if longest then
        Print("longest time from the hit to the heal: %.2f s (the addon pairs them inside %.2f s).", longest, PAIR_WINDOW)
    end
    for i = math.max(1, #log - 9), #log do
        local e = log[i]
        Print("  %s  gap %s  pair %s", e.at, e.gap and format("%.1f", e.gap) or "-",
            e.pair and format("%+.2f", e.pair) or "-")
    end
end

local function Command(input)
    local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "options" or cmd == "config" then
        OpenOptions()
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = cmd == "lock"
        ApplyLock()
        SyncSetting("locked")
        Print(db.locked and "frame locked." or "frame unlocked. Drag it with the left mouse button.")
    elseif cmd == "reset" then
        db.point, db.relPoint, db.x, db.y = defaults.point, defaults.relPoint, defaults.x, defaults.y
        ApplyPosition()
        lastProc = nil
        BecomeReady(false)
        Print("position and timer reset.")
    elseif cmd == "test" then
        StartCooldown(GetTime(), db.icd)   -- not logged, so the stats stay true
        Print("test proc started. The icon is ready in %s.", Seconds(db.icd))
    elseif cmd == "icd" and tonumber(arg) then
        db.icd = math.max(1, tonumber(arg))
        SyncSetting("icd")
        Print("internal cooldown set to %s.", Seconds(db.icd))
    elseif cmd == "size" and tonumber(arg) then
        db.size = ClampSize(tonumber(arg))
        ApplyLook()
        SyncSetting("size")
        Print("icon size set to %d px.", db.size)
    elseif cmd == "sound" then
        ToggleSound()
    elseif cmd == "debug" and arg == "all" then
        db.debug = "all"
        Print("debug on, with every dropped hit and its school. The lines also go to the saved debug log.")
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print(db.debug and "debug on. Shadow hits, heals and procs show in chat and go to the saved debug log." or "debug off.")
    elseif cmd == "copy" then
        ShowDebugLines()
    elseif cmd == "report" then
        ShowReport()
    elseif cmd == "stats" then
        Stats()
    elseif cmd == "clearlog" then
        wipe(db.log)
        wipe(db.debugLog)
        wipe(db.recent)
        db.counts = { schools = {} }
        db.offered = nil
        Print("proc log, debug log, and report counters cleared.")
    else
        Print("commands: options, lock, unlock, reset, test, icd <seconds>, size <pixels>, sound, report, debug, debug all, copy, stats, clearlog")
    end
end

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        TouchOfTheGraveDB = TouchOfTheGraveDB or {}
        db = TouchOfTheGraveDB
        -- Version 0.1.0 saved a frame scale (1 = 40 px). Version 0.1.1 saves the icon size.
        if db.size == nil and type(db.scale) == "number" then
            db.size = ClampSize(defaults.size * db.scale)
        end
        db.scale = nil
        for key, value in pairs(defaults) do
            if db[key] == nil then db[key] = value end
        end
        db.log = db.log or {}
        db.debugLog = db.debugLog or {}
        db.recent = type(db.recent) == "table" and db.recent or {}
        db.counts = type(db.counts) == "table" and db.counts or {}
        db.counts.schools = type(db.counts.schools) == "table" and db.counts.schools or {}

        SLASH_TOUCHOFTHEGRAVE1 = "/totg"
        local _, raceFile = UnitRace("player")
        raceFile = Plain(raceFile)
        local undead = raceFile == "Scourge"
            or (raceFile == nil and (IsPlayerSpell(SPELLS[1]) or IsPlayerSpell(SPELLS[2])))
        if not undead then
            if not db.toldNotUndead then
                db.toldNotUndead = true
                Print("this character is not Undead. The addon stays off for this character.")
            end
            SlashCmdList.TOUCHOFTHEGRAVE = function()
                Print("this character is not Undead. The addon is off.")
            end
            return
        end

        local _, classFile = UnitClass("player")
        needHeal = SHADOW_CLASSES[Plain(classFile) or ""] or false
        for spellID, pause in pairs(DRAINS) do
            local name = Plain(C_Spell.GetSpellName(spellID))
            if name then drainNames[name] = pause end
        end
        inCombat = Plain(UnitAffectingCombat("player")) and true or false
        CreateDisplay()
        SlashCmdList.TOUCHOFTHEGRAVE = Command
        if Settings and Settings.RegisterVerticalLayoutCategory then
            local ok, err = pcall(CreateOptions)
            if not ok then
                category = nil
                Print("the options panel failed: %s", tostring(err))
            end
        end
        if needHeal then
            self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")   -- drain spells only
        end
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        if not pcall(self.RegisterUnitEvent, self, "UNIT_COMBAT", "player", "target") then
            Print("the client refused UNIT_COMBAT. The addon cannot find procs.")
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcast(...)
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        hitsAtFightStart = db.counts.targetHits or 0
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat, leftCombatAt = false, GetTime()
        -- One time: offer the report after many fights with no proc.
        local c = db.counts
        if (c.targetHits or 0) > hitsAtFightStart then
            c.fights = (c.fights or 0) + 1
            if c.fights >= OFFER_FIGHTS and (c.procs or 0) == 0 and not db.offered then
                db.offered = true
                Print("no proc found in %d fights. Type /totg report to see the cause and to send a report.", c.fights)
            end
        end
        if openAfterCombat then
            openAfterCombat = false
            OpenOptions()
        end
    end
end)
