-- RaidTrackerUI.lua
-- Interface graphique du RaidTracker pour RaidCalendar
-- Panneau flottant : Kill / Wipe / Pause / Summary + loot en temps rel

RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

if m.RaidTrackerUI then return end

local M = {}
local f = nil  -- frame principale

local function T(key) return m.L(key) or key end

-- ============================================================
--  CRATION DU FRAME
-- ============================================================

local function create_frame()
    local frame = CreateFrame("Frame", "RCRaidTrackerFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(370)
    frame:SetPoint("CENTER", UIParent, "CENTER", 300, 100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:SetFrameStrata("MEDIUM")

    -- Fond et bordure
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- -- Titre ----------------------------------------------
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("|cffFFD700Raid|r|cffffffff Tracker|r")
    frame.title = title

    -- Bouton fermer
    local close_btn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close_btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    close_btn:SetScript("OnClick", function() frame:Hide() end)

    -- Sparateur 1
    local function make_sep(parent, yoffset)
        local s = parent:CreateTexture(nil, "ARTWORK")
        s:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
        s:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yoffset)
        s:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, yoffset)
        s:SetHeight(2)
        return s
    end
    make_sep(frame, -32)

    -- -- Inputs ---------------------------------------------

    -- Nom du raid
    local lbl_raid = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_raid:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
    lbl_raid:SetText("|cffAAAAAA" .. T("raidtracker.label_raid") .. "|r")

    local inp_raid = CreateFrame("EditBox", "RCRT_RaidName", frame, "InputBoxTemplate")
    inp_raid:SetWidth(175)
    inp_raid:SetHeight(20)
    inp_raid:SetPoint("TOPLEFT", lbl_raid, "TOPRIGHT", 4, 2)
    inp_raid:SetText(
        (m.db and m.db.user_settings and m.db.user_settings.last_raid_name) or "Molten Core"
    )
    inp_raid:SetAutoFocus(false)
    frame.inp_raid = inp_raid

    -- Channel Discord
    local lbl_ch = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_ch:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -64)
    lbl_ch:SetText("|cffAAAAFF" .. T("raidtracker.label_channel") .. "|r")

    local inp_ch = CreateFrame("EditBox", "RCRT_ChannelId", frame, "InputBoxTemplate")
    inp_ch:SetWidth(175)
    inp_ch:SetHeight(20)
    inp_ch:SetPoint("TOPLEFT", lbl_ch, "TOPRIGHT", 4, 2)
    inp_ch:SetText(
        (m.db and m.db.user_settings and m.db.user_settings.raid_log_channel_id) or ""
    )
    inp_ch:SetAutoFocus(false)
    frame.inp_ch = inp_ch

    -- Boss courant
    local lbl_boss = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_boss:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -86)
    lbl_boss:SetText("|cffFF9944" .. T("raidtracker.label_boss") .. "|r")

    local inp_boss = CreateFrame("EditBox", "RCRT_BossName", frame, "InputBoxTemplate")
    inp_boss:SetWidth(175)
    inp_boss:SetHeight(20)
    inp_boss:SetPoint("TOPLEFT", lbl_boss, "TOPRIGHT", 4, 2)
    inp_boss:SetText("")
    inp_boss:SetAutoFocus(false)
    frame.inp_boss = inp_boss

    make_sep(frame, -108)

    -- Barre de statut
    local lbl_status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_status:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -117)
    lbl_status:SetText("|cffFF4444" .. T("raidtracker.status_inactive") .. "|r")
    frame.lbl_status = lbl_status

    local lbl_perm = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_perm:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -117)
    lbl_perm:SetText("|cffFF4444" .. T("raidtracker.perm_denied") .. "|r")
    frame.lbl_perm = lbl_perm

    -- -- Boutons de contrle --------------------------------

    -- Helper bouton
    local function make_btn(label, x, y, w, h)
        local b = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        b:SetWidth(w or 128)
        b:SetHeight(h or 26)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        b:SetText(label)
        return b
    end

    -- Ligne 1: Start / Stop
    local btn_start = make_btn("|cff00DD00" .. T("raidtracker.btn_start") .. "|r",  16, -136)
    local btn_end   = make_btn("|cffFF4444" .. T("raidtracker.btn_end") .. "|r",  155, -136)
    frame.btn_start = btn_start
    frame.btn_end   = btn_end

    -- Ligne 2: Kill / Wipe
    local btn_kill  = make_btn("|cffFFD700 Kill|r",       16, -168)
    local btn_wipe  = make_btn("|cffFF5555 Wipe|r",       155, -168)
    frame.btn_kill  = btn_kill
    frame.btn_wipe  = btn_wipe

    -- Ligne 3: Pause / Rsum
    local btn_pause   = make_btn("|cffAAAAAA" .. T("raidtracker.btn_pause") .. "|r", 16,  -200)
    local btn_summary = make_btn("|cff88BBFF" .. T("raidtracker.btn_summary") .. "|r",      155, -200)
    frame.btn_pause   = btn_pause
    frame.btn_summary = btn_summary

    make_sep(frame, -231)

    -- Statistiques
    local lbl_stats = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_stats:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -240)
    lbl_stats:SetWidth(270)
    lbl_stats:SetJustifyH("LEFT")
    lbl_stats:SetText(string.format(T("raidtracker.stats_format"), 0, 0, 0))
    frame.lbl_stats = lbl_stats

    -- Mini liste des kills rcents
    local lbl_kills = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl_kills:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -258)
    lbl_kills:SetWidth(270)
    lbl_kills:SetHeight(70)
    lbl_kills:SetJustifyH("LEFT")
    lbl_kills:SetText("")
    frame.lbl_kills = lbl_kills

    -- -- Handlers -------------------------------------------

    btn_start:SetScript("OnClick", function()
        local raid_name  = frame.inp_raid:GetText()
        local channel_id = frame.inp_ch:GetText()

        if not m.db.user_settings.discord_id then
            m.error(m.L( "raidtracker.discord_not_auth" ) or "Not authenticated.")
            return
        end
        if channel_id == "" then
            m.error(m.L( "raidtracker.enter_channel_id" ) or "Enter channel ID.")
            return
        end

        if m.RaidTracker.start_raid(raid_name, channel_id) then
            M.update()
        end
    end)

    btn_end:SetScript("OnClick", function()
        m.RaidTracker.end_raid()
        M.update()
    end)

    btn_kill:SetScript("OnClick", function()
        local boss = frame.inp_boss:GetText()
        if boss == "" then
            m.error(m.L( "raidtracker.enter_boss_name" ) or "Enter boss name.")
            return
        end
        if m.RaidTracker.register_kill(boss) then
            frame.inp_boss:SetText("")
            M.update()
        end
    end)

    btn_wipe:SetScript("OnClick", function()
        local boss = frame.inp_boss:GetText()
        if boss == "" then
            m.error(m.L( "raidtracker.enter_boss_name" ) or "Enter boss name.")
            return
        end
        if m.RaidTracker.register_wipe(boss) then
            M.update()
        end
    end)

    btn_pause:SetScript("OnClick", function()
        m.RaidTracker.toggle_pause()
        M.update()
    end)

    btn_summary:SetScript("OnClick", function()
        m.RaidTracker.send_summary()
    end)

    -- Raccourci clavier Boss input : Entre -> Pull timer
    frame.inp_boss:SetScript("OnEnterPressed", function(self)
        local boss = self:GetText()
        if boss ~= "" then
            m.RaidTracker.set_pull(boss)
            m.info("|cffFF9944" .. T("raidtracker.pull_started") .. boss .. "|r")
        end
        self:ClearFocus()
    end)

    frame:Hide()
    return frame
end

-- ============================================================
--  API PUBLIQUE
-- ============================================================

function M.show()
    if not f then f = create_frame() end
    -- Pr-remplir avec les valeurs sauvegardes
    if m.db and m.db.user_settings then
        if m.db.user_settings.last_raid_name then
            f.inp_raid:SetText(m.db.user_settings.last_raid_name)
        end
        if m.db.user_settings.raid_log_channel_id then
            f.inp_ch:SetText(m.db.user_settings.raid_log_channel_id)
        end
    end
    f:Show()
    M.update()
    m.RaidTracker.check_raid_role()
end

function M.hide()
    if f then f:Hide() end
end

function M.toggle()
    if f and f:IsShown() then
        M.hide()
    else
        M.show()
    end
end

--- Mise  jour de l'interface selon l'tat courant du tracker
function M.update()
    if not f then return end

    local state = m.RaidTracker.get_state()

    -- Statut session
    if state.active then
        local elapsed = time() - (state.startTime or time())
        local h       = math.floor(elapsed / 3600)
        local mins    = math.floor((math.mod(elapsed, 3600)) / 60)
        f.lbl_status:SetText(string.format(
            "|cff00FF00* %s (%dh%02dm)|r", state.raidName, h, mins
        ))
    else
        f.lbl_status:SetText("|cffFF4444" .. T("raidtracker.status_inactive") .. "|r")
    end

    -- Statistiques
    f.lbl_stats:SetText(string.format(
        "|cffFFD700" .. T("raidtracker.stats_format") .. "|r",
        table.getn(state.kills), state.wipes, table.getn(state.loots)
    ))

    -- Derniers kills (4 max)
    local lines = {}
    local start = math.max(1, table.getn(state.kills) - 3)
    for i = start, table.getn(state.kills) do
        local k = state.kills[i]
        if k then
            local attempts = state.attempts[k.name] or k.attempt
            table.insert(lines, string.format(
                "|cffFFD700OK|r %-20s  |cffAAAAAA%s|r (x%d)",
                k.name, string.format("%d:%02d", math.floor(k.duration/60), math.mod(k.duration, 60)), attempts
            ))
        end
    end
    f.lbl_kills:SetText(table.concat(lines, "\n"))

    -- Etat pause
    if state.paused then
        f.btn_pause:SetText("|cff00FF00" .. T("raidtracker.btn_resume") .. "|r")
    else
        f.btn_pause:SetText("|cffAAAAAA" .. T("raidtracker.btn_pause") .. "|r")
    end
end

--- Met  jour l'affichage de la permission Discord
function M.update_permission(has_perm)
    if not f then return end
    if has_perm then
        f.lbl_perm:SetText("|cff00FF00" .. T("raidtracker.perm_granted") .. "|r")
    else
        f.lbl_perm:SetText("|cffFF4444" .. T("raidtracker.perm_denied") .. "|r")
    end
end

m.RaidTrackerUI = M
return M
