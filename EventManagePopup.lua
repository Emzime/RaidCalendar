RaidCalendar = RaidCalendar or {}
local m = RaidCalendar
if m.EventManagePopup then return end
local M = {}

-- mode: "raidres" | "local" | "edit" | "edit_local"
local popup = nil
local mode = "raidres"
local current_id = nil
local has_perm = false

local dropdown_uid = 0
local active_dropdown = nil

-- -- helpers --------------------------------------------------
local function T(k)
    if m.L then return m.L(k) end
    return k
end

local function get_addon_locale()
    local locale = nil

    if m.db and m.db.user_settings then
        locale = m.db.user_settings.locale_flag or m.db.user_settings.locale or m.db.user_settings.language
    end

    if locale == "Francais" or locale == "Français" or locale == "French" then
        return "frFR"
    end
    if locale == "English" then
        return "enUS"
    end
    if locale == "frFR" or locale == "enUS" then
        return locale
    end

    if GetLocale then
        locale = GetLocale()
    end

    if locale == "frFR" then
        return "frFR"
    end
    return "enUS"
end

local function is_fr_locale()
    return get_addon_locale() == "frFR"
end

local function fmt_date_display(ts)
    if is_fr_locale() then
        return date("%d/%m/%Y", ts)
    end
    return date("%m/%d/%Y", ts)
end

local function fmt_time_display(ts)
    return date("%H:%M", ts)
end

local function parse_date_display(ds)
    local a, b, c

    if is_fr_locale() then
        a, b, c = string.match(ds or "", "(%d+)/(%d+)/(%d+)")
        if not (a and b and c) then return nil end
        return tonumber(c), tonumber(b), tonumber(a)
    end

    a, b, c = string.match(ds or "", "(%d+)/(%d+)/(%d+)")
    if not (a and b and c) then return nil end
    return tonumber(c), tonumber(a), tonumber(b)
end

local function parse_dt_display(ds, ts)
    local year, month, day = parse_date_display(ds)
    local h, mi = string.match(ts or "", "(%d+):(%d+)")
    if not (year and month and day and h and mi) then return nil end

    local base = time({
        year = year,
        month = month,
        day = day,
        hour = 12,
        min = 0,
        sec = 0,
    })
    if not base then return nil end

    local parts = date("*t", base)
    if not parts then return nil end
    parts.hour = tonumber(h)
    parts.min = tonumber(mi)
    parts.sec = 0
    return time(parts)
end

local function is_admin()
    -- Verifie d'abord le role manager Discord (manager_role_id cote bot)
    if m.db and m.db.user_settings and m.db.user_settings.has_manager_role then
        return true
    end
    -- Fallback : liste des admins RaidRes (raidres.admins cote bot)
    local sr_admins = m.db and m.db.user_settings and m.db.user_settings.sr_admins
    if not sr_admins then return false end
    return m.find and m.find(m.player, sr_admins) ~= nil
end

local function set_status(text, color)
    if not popup or not popup.status then return end
    color = color or {1, 0.82, 0}
    popup.status:SetTextColor(color[1], color[2], color[3])
    popup.status:SetText(text or "")
end

local function set_who(character)
    if not popup or not popup.role_info then return end
    popup.role_info:SetText(string.format(
        "|cffFFD000%s|r  |cffFFFFFF%s|r",
        T("event_manage.link_character"), character or m.player or "?"
    ))
end

local function get_storage()
    m.db = m.db or {}
    m.db.popup_event_manage = m.db.popup_event_manage or {}
    return m.db.popup_event_manage
end

local function save_position(self)
    if not self or not self.GetPoint then return end
    local point, _, relative_point, x, y = self:GetPoint()
    local storage = get_storage()

    storage.position = {
        point = point,
        relative_point = relative_point,
        x = x,
        y = y,
    }
end

local function get_frame_from_popup(candidate)
    if not candidate then return nil end
    if candidate.frame and candidate.frame.GetPoint then
        return candidate.frame
    end
    if candidate.GetPoint then
        return candidate
    end
    return nil
end

local function get_visible_source_position()
    local frames = {
        get_frame_from_popup(m.event_popup),
        get_frame_from_popup(m.EventPopup),
        get_frame_from_popup(m.local_popup),
        get_frame_from_popup(m.LocalEventPopup),
    }

    local i
    for i = 1, table.getn(frames) do
        local f = frames[i]
        if f and f.IsVisible and f:IsVisible() then
            local point, _, relative_point, x, y = f:GetPoint()
            if point then
                return {
                    point = point,
                    relative_point = relative_point,
                    x = x,
                    y = y,
                }
            end
        end
    end

    return nil
end

-- (close_popup_fronts remplace par close_all_popups)

local function apply_saved_or_default_position(f, source_pos)
    if not f then return end
    local storage = get_storage()
    local pos = source_pos or storage.position or (m.db and m.db.popup_event and m.db.popup_event.position)

    f:ClearAllPoints()

    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relative_point or pos.point, pos.x or 0, pos.y or 0)
        f:SetFrameStrata("DIALOG")
    elseif m.calendar_popup and m.calendar_popup.frame and m.calendar_popup.frame:IsVisible() then
        f:SetPoint("CENTER", m.calendar_popup.frame, "CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
    end

    f:SetToplevel(true)
    f:Raise()
end

local function extract_tagged_link(description, tag)
    if not description or description == "" then return nil end
    local pattern = tag .. "[ ]*%-%>[ ]*(https://[^%s]+)"
    return string.match(description, pattern)
end

local function strip_tagged_links(description)
    if not description or description == "" then return description end
    local cleaned = description
    cleaned = string.gsub(cleaned, "SR[ ]*%-%>[ ]*https://[^\r\n]+[\r\n]*", "")
    cleaned = string.gsub(cleaned, "RF[ ]*%-%>[ ]*https://[^\r\n]+[\r\n]*", "")
    cleaned = string.gsub(cleaned, "\n\n\n+", "\n\n")
    cleaned = string.gsub(cleaned, "^[\r\n%s]+", "")
    cleaned = string.gsub(cleaned, "[\r\n%s]+$", "")
    return cleaned
end


local function build_sr_url(ev)
    if not ev then return nil end
    local sr_id = ev.srId
    if sr_id and sr_id ~= "" then
        return "https://raidres.top/res/" .. sr_id
    end
    return extract_tagged_link(ev.description or "", "SR")
end

local function build_rf_url(ev)
    if not ev then return nil end
    local rf_url = extract_tagged_link(ev.description or "", "RF")
    if rf_url and rf_url ~= "" then
        return rf_url
    end
    local sr_id = ev.srId
    if sr_id and sr_id ~= "" then
        return "https://raidres.top/api/events/" .. sr_id .. "/rollfor"
    end
    return nil
end

local function sep(parent, y)
    local l = parent:CreateTexture(nil, "ARTWORK")
    l:SetTexture("Interface\\Buttons\\WHITE8x8")
    l:SetVertexColor(1, 0.82, 0, 0.35)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    l:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    l:SetHeight(1)
    return l
end

local function lbl(parent, text, x, y, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(1, 0.82, 0, 1)
    if size then
        fs:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", size, "")
    end
    fs:SetText(text)
    return fs
end

local function eb(parent, x, y, w)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetAutoFocus(false)
    e:SetHeight(22)
    e:SetWidth(w)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    e:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 12, "")
    e:SetTextColor(1, 1, 1, 1)
    e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    return e
end

local function hint(parent, anchor, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -2)
    fs:SetTextColor(0.55, 0.50, 0.18, 1)
    fs:SetText(text)
    return fs
end

local function style_dropdown_border(frame, active)
    if not frame or not frame.SetBackdropBorderColor then return end
    if active then
        frame:SetBackdropBorderColor(0.80, 0.66, 0.10, 0.95)
    else
        frame:SetBackdropBorderColor(0.33, 0.33, 0.35, 0.95)
    end
end

local function hide_active_dropdown()
    if active_dropdown and active_dropdown.HideList then
        active_dropdown:HideList()
    end
end

local function start_of_day(ts)
    local dt = date("*t", ts or time())
    dt.hour = 0
    dt.min = 0
    dt.sec = 0
    return time(dt)
end

local function normalize_day_seed(ts)
    local dt = date("*t", ts or time())
    dt.hour = 12
    dt.min = 0
    dt.sec = 0
    return time(dt)
end

local function ceil_time_to_step(ts, step_minutes)
    local step = (step_minutes or 15) * 60
    local base = ts or time()
    local rem = math.mod(base, step)
    if rem == 0 then
        return base
    end
    return base + (step - rem)
end

local function round_time_to_step(ts, step_minutes)
    local step = (step_minutes or 15) * 60
    local base = ts or time()
    local rem = math.mod(base, step)
    if rem == 0 then
        return base
    end
    if rem >= (step / 2) then
        return base + (step - rem)
    end
    return base - rem
end

local function build_reference_now()
    return ceil_time_to_step(time(), 15)
end

local function normalize_time_for_dropdown(ts)
    return round_time_to_step(ts or time(), 15)
end

local function create_custom_dropdown(parent, default_text, width, on_select_mode)
    dropdown_uid = dropdown_uid + 1

    local name = "RaidCalendarCustomDropdown" .. tostring(dropdown_uid)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(width or 100)
    btn:SetHeight(22)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.02, 0.02, 0.03, 1)
    style_dropdown_border(btn, false)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    btn.bg:SetVertexColor(0.05, 0.05, 0.06, 1)
    btn.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "RCFontNormal")
    btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetTextColor(1, 1, 1, 1)
    btn.text:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 13, "")
    btn.text:SetText(default_text or "")

    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.arrow:SetTextColor(1, 0.82, 0, 1)
    btn.arrow:SetText("v")

    btn.default_text = default_text or ""
    btn.label_on_select = on_select_mode or "text"
    btn.items = {}
    btn.selected = nil
    btn.offset = 0
    btn.visible_rows = 8
    btn.row_height = 22

    local list = CreateFrame("Frame", name .. "List", UIParent)
    list:SetWidth(width or 100)
    list:SetHeight((btn.visible_rows * btn.row_height) + 6)
    btn.list = list
    list:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    list:SetBackdropColor(0.01, 0.01, 0.02, 0.98)
    list:SetBackdropBorderColor(0.33, 0.33, 0.35, 0.98)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetToplevel(true)
    list:EnableMouseWheel(true)
    list:Hide()
    btn.list = list

    list.up = CreateFrame("Button", nil, list)
    list.up:SetWidth(18)
    list.up:SetHeight(18)
    list.up:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2)
    list.up:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    list.up:SetBackdropColor(0.06, 0.06, 0.07, 1)
    list.up:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)
    list.up.txt = list.up:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    list.up.txt:SetPoint("CENTER", list.up, "CENTER", 0, 0)
    list.up.txt:SetTextColor(1, 0.82, 0, 1)
    list.up.txt:SetText("^")

    list.down = CreateFrame("Button", nil, list)
    list.down:SetWidth(18)
    list.down:SetHeight(18)
    list.down:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 2)
    list.down:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    list.down:SetBackdropColor(0.06, 0.06, 0.07, 1)
    list.down:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)
    list.down.txt = list.down:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    list.down.txt:SetPoint("CENTER", list.down, "CENTER", 0, 0)
    list.down.txt:SetTextColor(1, 0.82, 0, 1)
    list.down.txt:SetText("v")

    -- ── Scrollbar track + thumb ────────────────────────────────
    local sb_track = list:CreateTexture(nil, "BACKGROUND")
    sb_track:SetTexture("Interface\\Buttons\\WHITE8x8")
    sb_track:SetVertexColor(0.06, 0.06, 0.07, 1)
    sb_track:SetPoint("TOPLEFT",    list.up,   "BOTTOMLEFT",  0, -2)
    sb_track:SetPoint("BOTTOMRIGHT", list.down, "TOPRIGHT",   0,  2)
    list.sb_track = sb_track

    local sb = CreateFrame("Slider", nil, list)
    sb:SetWidth(14)
    sb:SetPoint("TOPLEFT",    list.up,   "BOTTOMLEFT",  2, -2)
    sb:SetPoint("BOTTOMRIGHT", list.down, "TOPRIGHT",  -2,  2)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetValueStep(1)
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = sb:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(0.55, 0.46, 0.12, 0.95)
        thumb:SetHeight(20)
    end
    sb:EnableMouseWheel(true)
    sb:SetScript("OnMouseWheel", function()
        if arg1 and arg1 > 0 then btn:Scroll(-1) else btn:Scroll(1) end
    end)
    sb:SetScript("OnValueChanged", function()
        local v = math.floor(sb:GetValue() + 0.5)
        if v ~= btn.offset then
            btn.offset = v
            btn:RefreshRows()
        end
    end)
    list.sb = sb
    list.sb:Hide()

    btn.rows = {}
    local i
    for i = 1, btn.visible_rows do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(btn.row_height)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -2 - ((i - 1) * btn.row_height))
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -24, -2 - ((i - 1) * btn.row_height))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
        row:SetBackdropBorderColor(0.10, 0.10, 0.11, 0.90)

        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.hl:SetVertexColor(0.20, 0.16, 0.04, 0.45)
        row.hl:SetAllPoints(row)

        row.txt = row:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
        row.txt:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.txt:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.txt:SetJustifyH("LEFT")
        row.txt:SetTextColor(0.92, 0.92, 0.92, 1)
        row.txt:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 13, "")
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function()
            if arg1 and arg1 > 0 then
                btn:Scroll(-1)
            else
                btn:Scroll(1)
            end
        end)
        row:Hide()
        btn.rows[i] = row
    end

    function btn:SetText(value)
        self.text:SetText(value or self.default_text or "")
    end

    function btn:SetItems(items)
        self.items = items or {}
        self.offset = 0
        self:RefreshRows()
    end

    function btn:GetMaxOffset()
        local total = table.getn(self.items or {})
        if total <= self.visible_rows then return 0 end
        return total - self.visible_rows
    end

    function btn:Scroll(delta)
        local max_offset = self:GetMaxOffset()
        local next_offset = self.offset + delta
        if next_offset < 0 then next_offset = 0 end
        if next_offset > max_offset then next_offset = max_offset end
        self.offset = next_offset
        self:RefreshRows()
    end

    function btn:SetSelected(value)
        self.selected = value
        local items = self.items or {}
        local i2
        for i2 = 1, table.getn(items) do
            local item = items[i2]
            if item and tostring(item.value) == tostring(value) then
                if self.label_on_select == "value" then
                    self:SetText(tostring(item.value or ""))
                else
                    self:SetText(item.text or tostring(item.value or ""))
                end
                return
            end
        end
        self:SetText(tostring(value or self.default_text or ""))
    end

    function btn:RefreshRows()
        local total = table.getn(self.items or {})
        local i2
        for i2 = 1, self.visible_rows do
            local idx = self.offset + i2
            local item = self.items[idx]
            local row = self.rows[i2]
            if item then
                row.item = item
                row.txt:SetText(item.text or tostring(item.value or ""))
                if item.is_header then
                    row.txt:SetTextColor(1, 0.82, 0, 1)
                    row:SetBackdropColor(0.06, 0.05, 0.01, 0.95)
                    row:SetBackdropBorderColor(0.25, 0.20, 0.05, 0.80)
                    row:EnableMouse(false)
                elseif self.selected and tostring(self.selected) == tostring(item.value) then
                    row:EnableMouse(true)
                    row.txt:SetTextColor(1, 1, 1, 1)
                    row:SetBackdropColor(0.09, 0.07, 0.02, 0.95)
                    row:SetBackdropBorderColor(0.55, 0.46, 0.12, 0.95)
                else
                    row:EnableMouse(true)
                    row.txt:SetTextColor(0.85, 0.85, 0.85, 1)
                    row:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
                    row:SetBackdropBorderColor(0.10, 0.10, 0.11, 0.90)
                end
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end

        if total > self.visible_rows then
            list.up:Show()
            list.down:Show()
            if self.offset <= 0 then
                list.up.txt:SetTextColor(0.45, 0.45, 0.45, 1)
            else
                list.up.txt:SetTextColor(1, 0.82, 0, 1)
            end
            if self.offset >= self:GetMaxOffset() then
                list.down.txt:SetTextColor(0.45, 0.45, 0.45, 1)
            else
                list.down.txt:SetTextColor(1, 0.82, 0, 1)
            end
        -- Scrollbar
        local max_off = self:GetMaxOffset()
        list.sb:SetMinMaxValues(0, max_off)
        list.sb:SetValue(math.min(self.offset, max_off))
        list.sb:Show()
    else
        list.up:Hide()
        list.down:Hide()
        list.sb:Hide()
    end
    end

    function btn:ShowList()
        hide_active_dropdown()
        active_dropdown = self
        list:ClearAllPoints()
        if self.open_up then
            list:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
        else
            list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        end
        list:SetWidth(self:GetWidth())
        list:Show()
        list:Raise()
        style_dropdown_border(self, true)
        self.arrow:SetText("^")
        self:RefreshRows()
    end

    function btn:HideList()
        list:Hide()
        style_dropdown_border(self, false)
        self.arrow:SetText("v")
        if active_dropdown == self then
            active_dropdown = nil
        end
    end

    function btn:ToggleList()
        if list:IsShown() then
            self:HideList()
        else
            self:ShowList()
        end
    end

    btn:SetScript("OnClick", function()
        btn:ToggleList()
    end)

    btn:SetScript("OnMouseWheel", function()
        if not list:IsShown() then
            btn:ShowList()
        end
        if arg1 and arg1 > 0 then
            btn:Scroll(-1)
        else
            btn:Scroll(1)
        end
    end)

    btn:SetScript("OnHide", function()
        btn:HideList()
    end)

    list:SetScript("OnMouseWheel", function()
        if arg1 and arg1 > 0 then
            btn:Scroll(-1)
        else
            btn:Scroll(1)
        end
    end)

    list:SetScript("OnHide", function()
        if active_dropdown == btn then
            active_dropdown = nil
        end
        style_dropdown_border(btn, false)
        btn.arrow:SetText("v")
    end)

    list.up:SetScript("OnClick", function()
        btn:Scroll(-1)
    end)

    list.down:SetScript("OnClick", function()
        btn:Scroll(1)
    end)

    local j
    for j = 1, btn.visible_rows do
        local row = btn.rows[j]
        row:SetScript("OnClick", function()
            if not row.item then return end
            if row.item.is_header then return end
            btn:SetSelected(row.item.value)
            btn:HideList()
        end)
    end

    return btn
end

local function build_date_items(base_ts, days)
    local list = {}
    local seen = {}
    local seed = normalize_day_seed(base_ts or time())
    local i

    for i = 0, (days or 180) do
        local dt = date("*t", seed)
        dt.day = dt.day + i
        dt.hour = 12
        dt.min = 0
        dt.sec = 0

        local ts = time(dt)
        local value = fmt_date_display(ts)

        if not seen[value] then
            table.insert(list, { value = value, text = value, timestamp = ts })
            seen[value] = true
        end
    end

    return list
end

local function build_time_items()
    local list = {}
    local minutes = 0

    while minutes < 1440 do
        local h = math.floor(minutes / 60)
        local mi = math.mod(minutes, 60)
        local value = string.format("%02d:%02d", h, mi)
        table.insert(list, { value = value, text = value })
        minutes = minutes + 15
    end

    return list
end

local RAID_LIST = {
    { is_header = true, text = "── 40-man ──" },
    { value = 94,  text = "Blackwing Lair" },
    { value = 102, text = "Emerald Sanctum" },
    { value = 95,  text = "Molten Core" },
    { value = 96,  text = "Naxxramas" },
    { value = 97,  text = "Onyxia's Lair" },
    { value = 99,  text = "Temple of Ahn'Qiraj" },
    { value = 109, text = "Tower of Karazhan" },
    { is_header = true, text = "── 20-man ──" },
    { value = 98,  text = "Ruins of Ahn'Qiraj" },
    { value = 115, text = "Timbermaw Hold" },
    { value = 100, text = "Zul'Gurub" },
    { is_header = true, text = "── 10-man ──" },
    { value = 101, text = "Lower Karazhan Halls" },
    { value = 106, text = "Upper Blackrock Spire" },
    { is_header = true, text = "── World Boss ──" },
    { value = 116, text = "Azuregos" },
    { value = 110, text = "Cla'ckora" },
    { value = 120, text = "Concavius" },
    { value = 118, text = "Dark Reaver of Karazhan" },
    { value = 121, text = "Emeriss" },
    { value = 122, text = "Lethon" },
    { value = 117, text = "Lord Kazzak" },
    { value = 119, text = "Ostarius" },
    { value = 123, text = "Taerar" },
    { value = 124, text = "Ysondre" },
}

local function build_raid_items()
    local items = {}
    local i
    for i = 1, table.getn(RAID_LIST) do
        table.insert(items, RAID_LIST[i])
    end
    return items
end

local function build_template_items()
    return {
        { value = "1", text = "1 - Generic" },
        { value = "2", text = "2 - TH/DPS" },
        { value = "3", text = "3 - Classe" },
        { value = "4", text = "4 - Spec" },
        { value = "5", text = "5 - Donjon" },
        { value = "6", text = "6 - PVP" },
        { value = "7", text = "7 - Custom" },
    }
end

local function ensure_dropdown_value(dropdown, value)
    if not dropdown then return end
    if not value or value == "" then
        dropdown.selected = nil
        dropdown:SetText(dropdown.default_text or "")
        dropdown:RefreshRows()
        return
    end

    local items = dropdown.items or {}
    local i
    for i = 1, table.getn(items) do
        local item = items[i]
        if item and tostring(item.value) == tostring(value) then
            dropdown:SetSelected(value)
            dropdown:RefreshRows()
            return
        end
    end

    table.insert(items, 1, { value = value, text = value })
    dropdown:SetItems(items)
    dropdown:SetSelected(value)
    dropdown:RefreshRows()
end

local function get_date_text()
    if popup and popup.dd_date and popup.dd_date.selected then
        return popup.dd_date.selected
    end
    if popup and popup.inp_date then
        return popup.inp_date:GetText()
    end
    return ""
end

local function get_time_text()
    if popup and popup.dd_time and popup.dd_time.selected then
        return popup.dd_time.selected
    end
    if popup and popup.inp_time then
        return popup.inp_time:GetText()
    end
    return ""
end

local function get_template_text()
    if popup and popup.dd_template and popup.dd_template.selected then
        return popup.dd_template.selected
    end
    if popup and popup.inp_template then
        return popup.inp_template:GetText()
    end
    return ""
end

local function set_date_value(value)
    if popup and popup.dd_date then ensure_dropdown_value(popup.dd_date, value) end
    if popup and popup.inp_date then popup.inp_date:SetText(value or "") end
end

local function set_time_value(value)
    if popup and popup.dd_time then ensure_dropdown_value(popup.dd_time, value) end
    if popup and popup.inp_time then popup.inp_time:SetText(value or "") end
end

local function set_template_value(value)
    if popup and popup.dd_template then ensure_dropdown_value(popup.dd_template, value) end
    if popup and popup.inp_template then popup.inp_template:SetText(value or "") end
end

local function refresh_date_dropdown(base_ts)
    if popup and popup.dd_date then
        -- Le dropdown de date commence TOUJOURS depuis aujourd'hui
        -- pour permettre de choisir n'importe quelle date future
        popup.dd_date:SetItems(build_date_items(time(), 180))
    end
end

local function refresh_time_dropdown(ref_ts)
    if popup and popup.dd_time then
        popup.dd_time:SetItems(build_time_items())
        -- Positionner le scroll au plus proche de l'heure de référence
        if ref_ts then
            local target = fmt_time_display(normalize_time_for_dropdown(ref_ts))
            local items = popup.dd_time.items or {}
            local best_idx = 1
            local i
            for i = 1, table.getn(items) do
                if items[i] and items[i].value == target then
                    best_idx = i
                    break
                end
            end
            -- Centrer le scroll sur l'heure cible
            local offset = best_idx - math.floor((popup.dd_time.visible_rows or 8) / 2)
            if offset < 0 then offset = 0 end
            local max_off = popup.dd_time:GetMaxOffset()
            if offset > max_off then offset = max_off end
            popup.dd_time.offset = offset
            popup.dd_time:RefreshRows()
        end
    end
end

local function fill_datetime(reference_ts, use_now_rounding)
    local base_ts = reference_ts or time()

    refresh_date_dropdown(base_ts)
    refresh_time_dropdown(use_now_rounding and build_reference_now() or base_ts)

    if use_now_rounding then
        base_ts = build_reference_now()
    else
        base_ts = normalize_time_for_dropdown(base_ts)
    end

    set_date_value(fmt_date_display(base_ts))
    set_time_value(fmt_time_display(base_ts))
end

-- construction
local function build()
    local f = m.FrameBuilder.new()
        :name("RaidCalendarManagePopup")
        :title("RaidCalendar")
        :frame_style("TOOLTIP")
        :backdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        :backdrop_color(0, 0, 0, 1)
        :close_button()
        :frame_level(120)
        :width(520)
        :height(415)
        :movable()
        :esc()
        :on_hide(function()
            if popup and popup.inp_title then popup.inp_title:ClearFocus() end
            if popup and popup.inp_desc then popup.inp_desc:ClearFocus() end
            -- inp_limit remplace par dd_limit (dropdown)
            hide_active_dropdown()
            if popup then
                save_position(popup)
            end
        end)
        :build()

    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetClampedToScreen(true)
    f:Hide()
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        save_position(this)
    end)

    local gui = m.GuiElements

    local TAB_W = 120
    local TAB_H = 22
    local TOTAL = TAB_W * 2 + 4
    local TX = math.floor((520 - TOTAL) / 2)

    local function make_tab(txt, x)
        local t = CreateFrame("Button", nil, f)
        t:SetHeight(TAB_H)
        t:SetWidth(TAB_W)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -28)
        t:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        t:SetBackdropColor(0, 0, 0, 1)
        t:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        t.lbl = t:CreateFontString(nil, "OVERLAY", "RCFontNormal")
        t.lbl:SetPoint("CENTER", t, "CENTER", 0, 0)
        t.lbl:SetText(txt)
        return t
    end

    f.tab_raidres = make_tab(T("event_manage.tab_raidres") or "Raidres.top", TX)
    f.tab_local = make_tab(T("event_manage.tab_local") or "In-Game", TX + TAB_W + 4)

    f.tab_raidres:SetScript("OnClick", function()
        if mode == "raidres" then return end
        mode = "raidres"
        M._update_tabs()
        M._configure_fields()
        popup.titlebar.title:SetText(T("event_manage.create_title_remote"))
        popup.btn_submit:SetText(string.format("|cff44DD44%s|r", T("event_manage.create_button")))
        set_status(T("event_manage.checking_permissions"), {1, 0.82, 0})
        if m.RaidTracker and m.RaidTracker.check_raid_role then
            m.RaidTracker.check_raid_role()
        end
    end)

    f.tab_local:SetScript("OnClick", function()
        if mode == "local" then return end
        mode = "local"
        M._update_tabs()
        M._configure_fields()
        popup.titlebar.title:SetText(T("event_manage.create_title_local"))
        popup.btn_submit:SetText(string.format("|cff44DD44%s|r", T("event_manage.create_button_local")))
        set_status(T("event_manage.checking_member_role"), {1, 0.82, 0})
        if m.db and m.db.user_settings and m.db.user_settings.discord_id then
            m.msg.check_member_role(m.db.user_settings.discord_id)
        elseif m.db and m.db.user_settings and m.db.user_settings.has_member_role then
            M.on_member_role_result(true)
        end
    end)

    sep(f, -53)

    f.lbl_title_field = lbl(f, T("event_manage.label_title"), 12, -63)
    lbl(f, T("event_manage.label_date"), 296, -63)
    lbl(f, T("event_manage.label_time"), 420, -63)

    -- Dropdown raid (mode raidres uniquement)
    f.dd_title = create_custom_dropdown(f, T("event_manage.hint_raid") or "Raid...", 276, "text")
    f.dd_title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -78)
    f.dd_title:SetItems(build_raid_items())

    -- Champ texte titre (mode local/edit)
    f.inp_title = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.inp_title:SetAutoFocus(false)
    f.inp_title:SetHeight(22)
    f.inp_title:SetWidth(268)
    f.inp_title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -78)
    f.inp_title:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 12, "")
    f.inp_title:SetTextColor(1, 1, 1, 1)
    f.inp_title:SetMaxLetters(100)
    f.inp_title:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    f.inp_date = eb(f, 296, -78, 116)
    f.inp_time = eb(f, 420, -78, 88)
    -- Dropdown limite joueurs (1-40) : ligne 2
    f.lbl_limit = lbl(f, T("event_manage.label_limit"), 12, -113)
    f.dd_limit = create_custom_dropdown(f, "25", 70, "text")
    f.dd_limit:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -129)
    f.dd_limit:SetItems({
        { value = 1, text = "1" },
        { value = 2, text = "2" },
        { value = 3, text = "3" },
        { value = 4, text = "4" },
        { value = 5, text = "5" },
        { value = 6, text = "6" },
        { value = 7, text = "7" },
        { value = 8, text = "8" },
        { value = 9, text = "9" },
        { value = 10, text = "10" },
        { value = 11, text = "11" },
        { value = 12, text = "12" },
        { value = 13, text = "13" },
        { value = 14, text = "14" },
        { value = 15, text = "15" },
        { value = 16, text = "16" },
        { value = 17, text = "17" },
        { value = 18, text = "18" },
        { value = 19, text = "19" },
        { value = 20, text = "20" },
        { value = 21, text = "21" },
        { value = 22, text = "22" },
        { value = 23, text = "23" },
        { value = 24, text = "24" },
        { value = 25, text = "25" },
        { value = 26, text = "26" },
        { value = 27, text = "27" },
        { value = 28, text = "28" },
        { value = 29, text = "29" },
        { value = 30, text = "30" },
        { value = 31, text = "31" },
        { value = 32, text = "32" },
        { value = 33, text = "33" },
        { value = 34, text = "34" },
        { value = 35, text = "35" },
        { value = 36, text = "36" },
        { value = 37, text = "37" },
        { value = 38, text = "38" },
        { value = 39, text = "39" },
        { value = 40, text = "40" },
    })
    f.dd_limit.selected = 25

    f.dd_date = create_custom_dropdown(f, T("event_manage.hint_date"), 116, "text")
    f.dd_date:SetPoint("TOPLEFT", f, "TOPLEFT", 296, -78)
    f.dd_date:SetItems(build_date_items(build_reference_now(), 180))
    f.inp_date:Hide()

    f.dd_time = create_custom_dropdown(f, T("event_manage.hint_time"), 88, "text")
    f.dd_time:SetPoint("TOPLEFT", f, "TOPLEFT", 420, -78)
    f.dd_time:SetItems(build_time_items())
    f.inp_time:Hide()

    hint(f, f.dd_date or f.inp_date, T("event_manage.hint_date"))
    hint(f, f.dd_time or f.inp_time, T("event_manage.hint_time"))
    hint(f, f.dd_limit, T("event_manage.hint_players"))

    f.lbl_template = lbl(f, T("event_manage.label_template"), 12, -155)
    f.inp_template = eb(f, 12, -171, 44)
    f.dd_template = create_custom_dropdown(f, T("event_manage.label_template"), 140, "text")
    f.dd_template:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -171)
    f.dd_template:SetItems(build_template_items())
    f.inp_template:Hide()

    f.hint_template = hint(f, f.dd_template or f.inp_template, T("event_manage.hint_template_range"))
    f.template_info = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
    f.template_info:SetPoint("LEFT", (f.dd_template or f.inp_template), "RIGHT", 8, 0)
    f.template_info:SetTextColor(0.55, 0.50, 0.18, 1)
    f.template_info:SetText(T("event_manage.template_info"))

    -- Limite SR par joueur (mode raidres uniquement)
    f.lbl_sr_limit = lbl(f, T("event_manage.label_sr_limit"), 100, -113)
    f.dd_sr_limit = create_custom_dropdown(f, "1", 70, "text")
    f.dd_sr_limit:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -129)
    f.dd_sr_limit:SetItems({
        { value = 1, text = "1" },
        { value = 2, text = "2" },
        { value = 3, text = "3" },
        { value = 4, text = "4" },
    })
    f.dd_sr_limit.selected = 1
    f.dd_sr_limit.visible_rows = 4
    f.dd_sr_limit.list:SetHeight((4 * f.dd_sr_limit.row_height) + 6)
    f.hint_sr_limit = hint(f, f.dd_sr_limit, T("event_manage.hint_sr_limit"))

    f.sep_mid = sep(f, -199)


    local function make_link_box_em(parent, y)
        local box = CreateFrame("EditBox", nil, parent)
        box:SetAutoFocus(false)
        box:SetMultiLine(false)
        box:SetFontObject(GameFontHighlightSmall)
        box:SetHeight(16)
        box:SetPoint("TOPLEFT",  parent, "TOPLEFT",  50, y)
        box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, y)
        box:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
        box:SetBackdropBorderColor(0.35, 0.28, 0.08, 0.95)
        box:SetTextInsets(6, 4, 0, 0)
        box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        box:SetScript("OnEditFocusGained", function() this:HighlightText() end)
        box:Hide()
        return box
    end

    lbl(f, T("event_manage.label_description"), 12, -190)

    -- Boîtes SR/RF copiables (mode edit uniquement)
    f.lbl_sr_edit = lbl(f, T("event_manage.sr_label") or "SR :", 12, -206)
    f.lbl_sr_edit:SetTextColor(1, 0.82, 0, 1)
    f.lbl_sr_edit:Hide()
    f.sr_edit_box = make_link_box_em(f, -206)

    f.lbl_rf_edit = lbl(f, T("event_manage.rf_label") or "RF :", 12, -226)
    f.lbl_rf_edit:SetTextColor(1, 0.82, 0, 1)
    f.lbl_rf_edit:Hide()
    f.rf_edit_box = make_link_box_em(f, -226)


    local desc_bg = m.FrameBuilder.new()
        :parent(f)
        :backdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        :backdrop_color(0.03, 0.03, 0.04, 1)
        :build()
    desc_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -206)
    desc_bg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -206)
    -- Note: repositionné dynamiquement dans _configure_fields
    desc_bg:SetHeight(100)
    f.desc_bg = desc_bg

    f.inp_desc = CreateFrame("EditBox", nil, desc_bg)
    f.inp_desc:SetPoint("TOPLEFT", desc_bg, "TOPLEFT", 6, -6)
    f.inp_desc:SetPoint("BOTTOMRIGHT", desc_bg, "BOTTOMRIGHT", -6, 6)
    f.inp_desc:SetAutoFocus(false)
    f.inp_desc:SetMultiLine(true)
    f.inp_desc:SetFont("Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 11, "")
    f.inp_desc:SetTextColor(1, 1, 1, 1)
    f.inp_desc:SetMaxLetters(1000)
    f.inp_desc:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    f.sep_after_desc = sep(f, -314)

    f.role_info = f:CreateFontString(nil, "OVERLAY", "RCFontNormal")
    f.role_info:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -324)
    f.role_info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -324)
    f.role_info:SetJustifyH("LEFT")
    f.role_info:SetText("")

    f.status = f:CreateFontString(nil, "OVERLAY", "RCFontNormal")
    f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -342)
    f.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -342)
    f.status:SetJustifyH("LEFT")
    f.status:SetText("")

    f.sep_bot = sep(f, -365)

    f.btn_cancel = gui.create_button(f, T("actions.cancel"), 90, function() f:Hide() end)
    f.btn_cancel:SetPoint("BOTTOM", f, "BOTTOM", 49, 10)

    f.btn_delete = gui.create_button(
        f,
        string.format("|cffDD3333%s|r", T("event_manage.delete")),
        90,
        function()
            if not current_id then return end
            StaticPopupDialogs["RC_CONFIRM_DELETE"] = {
                text = T("event_manage.confirm_delete_remote"),
                button1 = T("event_manage.confirm_delete_yes"),
                button2 = T("common.no"),
                OnAccept = function()
                    set_status(T("event_manage.status_updating"), {1, 0.7, 0})
                    if mode == "edit" then
                        m.msg.delete_event(current_id)
                    else
                        m.LocalEventManager.delete(current_id)
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("RC_CONFIRM_DELETE")
        end
    )
    f.btn_delete:SetPoint("RIGHT", f.btn_submit, "LEFT", -8, 0)
    f.btn_delete:Hide()

    f.btn_submit = gui.create_button(f, T("event_manage.create_button"), 90, function()
        M.on_submit()
    end)
    f.btn_submit:SetPoint("BOTTOM", f, "BOTTOM", -49, 10)
    -- Garder la souris active (hover) même quand désactivé
    f.btn_submit.Disable = function()
        f.btn_submit:SetScript("OnClick", nil)
        local fs = f.btn_submit:GetFontString()
        if fs then fs:SetTextColor(0.5, 0.41, 0) end
        local nt = f.btn_submit:GetNormalTexture()
        if nt then nt:SetVertexColor(0.5, 0.5, 0.5) end
    end
    f.btn_submit.Enable = function()
        f.btn_submit:SetScript("OnClick", function() M.on_submit() end)
        local fs = f.btn_submit:GetFontString()
        if fs then fs:SetTextColor(1, 0.82, 0) end
        local nt = f.btn_submit:GetNormalTexture()
        if nt then nt:SetVertexColor(1, 1, 1) end
    end

    if m.GuiElements and m.GuiElements.pfui_skin then
        m.GuiElements.pfui_skin(f)
    end

    return f
end

-- -- mise a jour visuelle des onglets -------------------------
function M._update_tabs()
    if not popup then return end

    local is_rr = (mode == "raidres")
    popup.tab_raidres:SetBackdropColor(is_rr and 0.08 or 0, is_rr and 0.06 or 0, 0, 1)
    popup.tab_raidres:SetBackdropBorderColor(is_rr and 1 or 0.3, is_rr and 0.82 or 0.3, 0, 1)
    popup.tab_raidres.lbl:SetTextColor(is_rr and 1 or 0.5, is_rr and 0.82 or 0.5, 0, 1)

    local is_lo = (mode == "local")
    popup.tab_local:SetBackdropColor(is_lo and 0.05 or 0, is_lo and 0.08 or 0, is_lo and 0.05 or 0, 1)
    popup.tab_local:SetBackdropBorderColor(is_lo and 0.3 or 0.3, is_lo and 0.9 or 0.3, is_lo and 0.3 or 0.3, 1)
    popup.tab_local.lbl:SetTextColor(is_lo and 0.4 or 0.4, is_lo and 1 or 0.4, is_lo and 0.4 or 0.4, 1)
end

function M._configure_fields()
    if not popup then return end
    local is_edit_rr = (mode == "edit")
    local is_rr_mode = (mode == "raidres")

    -- Dropdown raid : visible uniquement en mode raidres
    if popup.dd_title then
        if is_rr_mode then popup.dd_title:Show() else popup.dd_title:Hide() end
    end
    -- Champ texte titre : visible en mode local/edit
    if popup.inp_title then
        if is_rr_mode then popup.inp_title:Hide() else popup.inp_title:Show() end
    end
    -- Label du champ titre
    if popup.lbl_title_field then
        if is_rr_mode then
            popup.lbl_title_field:SetText(T("event_manage.label_raid") or "Raid")
        else
            popup.lbl_title_field:SetText(T("event_manage.label_title") or "Title")
        end
    end

    -- Template : masqué dans tous les modes (déplacé hors UI)
    if popup.lbl_template then popup.lbl_template:Hide() end
    if popup.dd_template   then popup.dd_template:Hide() end
    if popup.inp_template  then popup.inp_template:Hide() end
    if popup.hint_template then popup.hint_template:Hide() end
    if popup.template_info then popup.template_info:Hide() end

    -- Limite SR : visible en mode raidres ET edit
    local show_sr = is_rr_mode or is_edit_rr
    if popup.lbl_sr_limit then
        if show_sr then popup.lbl_sr_limit:Show() else popup.lbl_sr_limit:Hide() end
    end
    if popup.dd_sr_limit then
        if show_sr then popup.dd_sr_limit:Show() else popup.dd_sr_limit:Hide() end
    end
    if popup.hint_sr_limit then
        if show_sr then popup.hint_sr_limit:Show() else popup.hint_sr_limit:Hide() end
    end
    -- Séparateur dynamique : toujours à -178 (template toujours caché)
    if popup.sep_mid then
        popup.sep_mid:ClearAllPoints()
        local sep_y = -178
        popup.sep_mid:SetPoint("TOPLEFT", popup.sep_mid:GetParent(), "TOPLEFT", 12, sep_y)
        popup.sep_mid:SetPoint("TOPRIGHT", popup.sep_mid:GetParent(), "TOPRIGHT", -12, sep_y)
    end

    -- Boîtes SR/RF en mode edit
    if popup.lbl_sr_edit then
        if is_edit_rr then popup.lbl_sr_edit:Show() else popup.lbl_sr_edit:Hide() end
    end
    if popup.sr_edit_box then
        if is_edit_rr then popup.sr_edit_box:Show() else popup.sr_edit_box:Hide() end
    end
    if popup.lbl_rf_edit then
        if is_edit_rr then popup.lbl_rf_edit:Show() else popup.lbl_rf_edit:Hide() end
    end
    if popup.rf_edit_box then
        if is_edit_rr then popup.rf_edit_box:Show() else popup.rf_edit_box:Hide() end
    end
    -- Repositionner desc_bg + éléments inférieurs selon mode
    local dy = is_edit_rr and 44 or 0
    if popup.desc_bg then
        popup.desc_bg:ClearAllPoints()
        local desc_top_y = -206 - dy
        popup.desc_bg:SetPoint("TOPLEFT",  popup, "TOPLEFT",  12, desc_top_y)
        popup.desc_bg:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, desc_top_y)
    end
    if popup.sep_after_desc then
        popup.sep_after_desc:ClearAllPoints()
        popup.sep_after_desc:SetPoint("TOPLEFT",  popup, "TOPLEFT",  12, -314 - dy)
        popup.sep_after_desc:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -314 - dy)
    end
    if popup.role_info then
        popup.role_info:ClearAllPoints()
        popup.role_info:SetPoint("TOPLEFT",  popup, "TOPLEFT",  12, -324 - dy)
        popup.role_info:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -324 - dy)
    end
    if popup.status then
        popup.status:ClearAllPoints()
        popup.status:SetPoint("TOPLEFT",  popup, "TOPLEFT",  12, -342 - dy)
        popup.status:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -342 - dy)
    end
    if popup.sep_bot then
        popup.sep_bot:ClearAllPoints()
        popup.sep_bot:SetPoint("TOPLEFT",  popup, "TOPLEFT",  12, -365 - dy)
        popup.sep_bot:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -365 - dy)
    end
    -- Ajuster la hauteur du frame
    local needed_h = 415 + dy
    if popup:GetHeight() ~= needed_h then popup:SetHeight(needed_h) end

    local show_tabs = (mode == "raidres" or mode == "local")
    if show_tabs then popup.tab_raidres:Show() else popup.tab_raidres:Hide() end
    if show_tabs then popup.tab_local:Show() else popup.tab_local:Hide() end

    if show_tabs then
        local admin = is_admin()
        if admin then
            popup.tab_raidres:Show()
            popup.tab_raidres:EnableMouse(true)
        else
            popup.tab_raidres:Hide()
            if mode == "raidres" then
                mode = "local"
                M._update_tabs()
            end
        end
    end
end

-- -- soumission -----------------------------------------------
function M.on_submit()
    if not has_perm then
        set_status(T("event_manage.missing_manager_role"), {1, 0.3, 0.3})
        return
    end

    local title
    if mode == "raidres" and popup.dd_title and popup.dd_title.selected then
        title = popup.dd_title.selected
    elseif popup.inp_title then
        title = popup.inp_title:GetText()
    else
        title = ""
    end
    local desc = popup.inp_desc:GetText()
    -- Note: SR/RF préservés côté bot (handleEditEvent)
    local lim = popup.dd_limit and tonumber(popup.dd_limit.selected) or 25
    local sr_lim = (mode == "raidres" or mode == "edit") and (popup.dd_sr_limit and tonumber(popup.dd_sr_limit.selected) or 1) or nil
    local ts = parse_dt_display(get_date_text(), get_time_text())

    if title == "" then
        set_status((T("event_manage.label_title") or "Title") .. " " .. (T("common.required") or "required."), {1, 0.3, 0.3})
        return
    end
    if not ts then
        set_status(T("event_manage.invalid_datetime") or "Invalid date/time.", {1, 0.3, 0.3})
        return
    end

    if mode == "local" or mode == "edit_local" then
        if mode == "local" then
            set_status(T("event_manage.status_creating"), {1, 0.82, 0})
            m.LocalEventManager.create({
                title = title,
                startTime = ts,
                description = desc,
                location = "",
                limit = lim or 0,
            })
        else
            set_status(T("event_manage.status_updating"), {1, 0.82, 0})
            m.LocalEventManager.edit(current_id, {
                title = title,
                startTime = ts,
                description = desc,
                location = "",
                limit = lim or 0,
            })
        end
        return
    end

    if mode == "raidres" then
        -- Récupérer raidId (numérique) et le nom du raid depuis dd_title
        local raid_id = popup.dd_title and popup.dd_title.selected
        local raid_name = ""
        if popup.dd_title and popup.dd_title.selected then
            local items = popup.dd_title.items or {}
            local k
            for k = 1, table.getn(items) do
                if items[k].value and items[k].value == popup.dd_title.selected then
                    raid_name = items[k].text or ""
                    break
                end
            end
        end
        if not raid_id or raid_id == "" then
            set_status(T("event_manage.label_raid") or "Raid" .. " obligatoire.", {1, 0.3, 0.3})
            return
        end
        set_status(T("event_manage.status_creating"), {1, 0.82, 0})
        m.msg.raidres_create({
            title       = raid_name,
            raidId      = raid_id,
            startTime   = ts,
            description = desc,
            limit             = lim or 25,
            reservationLimit  = sr_lim or 1,
        })
    else
        set_status(T("event_manage.status_updating"), {1, 0.82, 0})
        m.msg.edit_event(current_id, {
            title            = title,
            startTime        = ts,
            description      = desc,
            limit            = lim,
            reservationLimit = sr_lim,
            locale           = get_addon_locale(),
        })
    end

    popup.btn_submit:Disable()
    popup.btn_delete:Disable()
end

-- -- callbacks resultats --------------------------------------
function M.on_create_result(success, event_id, status_msg)
    if not popup then return end
    popup.btn_submit:Enable()
    if success then
        set_status(string.format("|cff44DD44%s|r", T("event_manage.status_created")), {0, 1, 0})
        m.msg.request_events()
        m.ace_timer.ScheduleTimer(M, function() if popup then popup:Hide() end end, 2)
    else
        set_status("|cffDD4444" .. (status_msg or T("event_manage.unknown_error")) .. "|r", {1, 0.3, 0.3})
    end
end

function M.on_edit_result(success, event_id, status_msg)
    if not popup then return end
    popup.btn_submit:Enable()
    popup.btn_delete:Enable()
    if success then
        set_status(string.format("|cff44DD44%s|r", T("event_manage.status_saved")), {0, 1, 0})
        m.msg.request_event(event_id or current_id)
        m.ace_timer.ScheduleTimer(M, function() if popup then popup:Hide() end end, 2)
    else
        set_status("|cffDD4444" .. (status_msg or T("event_manage.unknown_error")) .. "|r", {1, 0.3, 0.3})
    end
end

function M.on_delete_result(success, event_id, status_msg)
    if not popup then return end
    if success then
        set_status(string.format("|cff44DD44%s|r", T("event_manage.status_deleted")), {0, 1, 0})
        if m.db.events and current_id then m.db.events[current_id] = nil end
        if m.calendar_popup and m.calendar_popup.update then
            m.calendar_popup.update()
        end
        m.ace_timer.ScheduleTimer(M, function() if popup then popup:Hide() end end, 2)
    else
        set_status("|cffDD4444" .. (status_msg or "?") .. "|r", {1, 0.3, 0.3})
        popup.btn_delete:Enable()
    end
end

function M.on_local_result(success, action, event_id, status_msg)
    if not popup then return end
    if success then
        set_status(string.format("|cff44DD44%s|r", status_msg or "OK"), {0.3, 0.85, 0.3})
        if action == "deleted" then
            if m.LocalEventPopup and m.LocalEventPopup.hide then
                m.LocalEventPopup.hide()
            end
            popup:Hide()
        else
            m.ace_timer.ScheduleTimer(M, function() if popup then popup:Hide() end end, 2)
        end
    else
        set_status("|cffDD4444" .. (status_msg or (m.L and m.L("event_manage.unknown_error")) or "Unknown error") .. "|r", {1, 0.3, 0.3})
        if popup.btn_submit then popup.btn_submit:Enable() end
        if popup.btn_delete then popup.btn_delete:Enable() end
    end
end

function M.on_role_result(ok, status_msg, linked, requested, character)
    has_perm = ok
    if not popup or not popup:IsShown() then return end
    set_who(character or m.player)
    if ok then
        -- Manager confirme : on peut passer en mode raidres si on etait en local par defaut
        if mode == "local" then
            mode = "raidres"
            popup.titlebar.title:SetText(T("event_manage.create_title_remote"))
            popup.btn_submit:SetText(string.format("|cff44DD44%s|r", T("event_manage.create_button")))
            M._update_tabs()
            M._configure_fields()
        end
        set_status(string.format("|cff44DD44%s|r", T("event_manage.manager_role_verified")), {0, 1, 0})
        popup.btn_submit:Enable()
        if mode == "edit" then popup.btn_delete:Enable() end
    else
        set_status(string.format("|cffDD4444%s|r", T("event_manage.missing_manager_role")), {1, 0.3, 0.3})
        popup.btn_submit:Disable()
        popup.btn_delete:Disable()
    end
end

function M.on_member_role_result(ok, status_msg, linked, requested, character)
    if not popup or not popup:IsShown() then return end
    if mode ~= "local" then return end
    set_who(character or m.player)
    if ok then
        has_perm = true
        popup.btn_submit:Enable()
        set_status(string.format("|cff44DD44%s|r", T("event_manage.member_role_verified")), {0.3, 0.85, 0.3})
    else
        has_perm = false
        popup.btn_submit:Disable()
        set_status(string.format("|cffDD4444%s|r", T("event_manage.missing_member_role")), {1, 0.3, 0.3})
    end
end

-- -- API publique ---------------------------------------------
function M.show_create()
    if not popup then popup = build() end
    if m.close_all_popups then m.close_all_popups() end
    mode = is_admin() and "raidres" or "local"
    current_id = nil
    has_perm = false

    popup.titlebar.title:SetText(T(mode == "local" and "event_manage.create_title_local" or "Create event"))
    popup.inp_title:SetText("")
    fill_datetime(build_reference_now(), true)
    popup.inp_desc:SetText("")
    set_template_value("3")
    if popup.dd_limit then popup.dd_limit.selected = 25; popup.dd_limit:SetText("25") end
    if popup.dd_sr_limit then popup.dd_sr_limit.selected = 1; popup.dd_sr_limit:SetText("1") end
    popup.btn_submit:SetText(string.format("|cff44DD44%s|r", T(mode == "local" and "event_manage.create_button_local" or "Create")))
    popup.btn_submit:Disable()
    popup.btn_delete:Hide()

    M._update_tabs()
    M._configure_fields()
    set_who(m.player)
    set_status(T("event_manage.checking_permissions"), {1, 0.82, 0})
    apply_saved_or_default_position(popup, nil)
    popup:Show()

    if mode == "raidres" then
        if m.RaidTracker and m.RaidTracker.check_raid_role then
            m.RaidTracker.check_raid_role()
        end
    else
        if m.db and m.db.user_settings and m.db.user_settings.discord_id then
            m.msg.check_member_role(m.db.user_settings.discord_id)
        elseif m.db and m.db.user_settings and m.db.user_settings.has_member_role then
            M.on_member_role_result(true)
        else
            set_status(string.format("|cffDD4444%s|r", T("event_manage.connect_discord_first")), {1, 0.3, 0.3})
        end
    end
end

function M.show_edit(event_id)
    local ev = m.db and m.db.events and m.db.events[event_id]
    local source_pos

    if not ev then
        m.error(T("event_manage.remote_not_found") .. ": " .. tostring(event_id))
        return
    end

    source_pos = get_visible_source_position()

    if not popup then popup = build() end
    if m.close_all_popups then m.close_all_popups() end
    mode = "edit"
    current_id = event_id
    has_perm = false

    popup.titlebar.title:SetText(T("event_manage.edit_title_remote"))
    popup.inp_title:SetText(ev.title or "")
    fill_datetime(ev.startTime or time(), false)
    popup.inp_desc:SetText(strip_tagged_links(ev.description or "") or "")
    set_template_value(tostring(ev.templateId or "3"))
    if popup.dd_limit then local v = ev.limit or 25; popup.dd_limit.selected = v; popup.dd_limit:SetText(tostring(v)) end
    if popup.dd_sr_limit then local v = ev.reservationLimit or 1; popup.dd_sr_limit.selected = v; popup.dd_sr_limit:SetText(tostring(v)) end
    -- Conserver le lien SR copiables, mais afficher le contenu RF (comme la gestion de groupe)
    local sr_url_edit = build_sr_url(ev)
    local rf_url_edit = build_rf_url(ev)
    if popup.sr_edit_box then popup.sr_edit_box:SetText(sr_url_edit or "") end
    if popup.rf_edit_box then popup.rf_edit_box:SetText(rf_url_edit and "..." or "") end
    popup._edit_sr_url = sr_url_edit
    popup._edit_rf_url = rf_url_edit
    popup._edit_rf_event_id = event_id
    popup.btn_submit:SetText(string.format("|cffFFD000%s|r", T("actions.save")))
    popup.btn_submit:Disable()
    popup.btn_delete:Show()
    popup.btn_delete:Disable()

    M._update_tabs()
    M._configure_fields()
    set_who(m.player)
    set_status(T("event_manage.checking_permissions"), {1, 0.82, 0})
    apply_saved_or_default_position(popup, source_pos)
    popup:Show()

    if rf_url_edit and rf_url_edit ~= "" and m.msg and m.msg.rf_data_request then
        m.msg.rf_data_request(rf_url_edit)
    end

    if m.RaidTracker and m.RaidTracker.check_raid_role then
        m.RaidTracker.check_raid_role()
    end
end

function M.show_create_local()
    if not popup then popup = build() end
    if m.close_all_popups then m.close_all_popups() end
    mode = "local"
    current_id = nil
    has_perm = false

    popup.titlebar.title:SetText(T("event_manage.create_title_local"))
    popup.inp_title:SetText("")
    fill_datetime(build_reference_now(), true)
    popup.inp_desc:SetText("")
    if popup.dd_limit then popup.dd_limit.selected = 1; popup.dd_limit:SetText("1") end
    popup.btn_submit:SetText(string.format("|cff44DD44%s|r", T("event_manage.create_button_local")))
    popup.btn_submit:Disable()
    popup.btn_delete:Hide()

    M._update_tabs()
    M._configure_fields()
    set_who(m.player)
    set_status(T("event_manage.checking_member_role"), {1, 0.82, 0})
    apply_saved_or_default_position(popup, nil)
    popup:Show()

    if m.db and m.db.user_settings and m.db.user_settings.discord_id then
        m.msg.check_member_role(m.db.user_settings.discord_id)
    elseif m.db and m.db.user_settings and m.db.user_settings.has_member_role then
        M.on_member_role_result(true)
    else
        set_status(string.format("|cffDD4444%s|r", T("event_manage.connect_discord_first")), {1, 0.3, 0.3})
    end
end

function M.show_edit_local(event_id)
    local ev = m.LocalEventManager and m.LocalEventManager.get(event_id)
    local source_pos

    if not ev then
        m.error(T("event_manage.local_not_found"))
        return
    end
    if not m.LocalEventManager.can_edit(event_id) then
        m.error(T("event_manage.no_edit_permission"))
        return
    end

    source_pos = get_visible_source_position()

    if not popup then popup = build() end
    if m.close_all_popups then m.close_all_popups() end
    mode = "edit_local"
    current_id = event_id
    has_perm = true

    popup.titlebar.title:SetText(T("event_manage.edit_title_local_prefix") .. " " .. ev.title)
    popup.inp_title:SetText(ev.title or "")
    fill_datetime(ev.startTime or time(), false)
    popup.inp_desc:SetText(ev.description or "")
    if popup.dd_limit then local v = ev.limit or 1; popup.dd_limit.selected = v; popup.dd_limit:SetText(tostring(v)) end
    popup.btn_submit:SetText(string.format("|cffFFD000%s|r", T("actions.save")))
    popup.btn_submit:Enable()
    popup.btn_delete:Show()
    popup.btn_delete:Enable()

    M._update_tabs()
    M._configure_fields()
    set_who(ev.creator or m.player)
    set_status(T("event_manage.local_edit_active"), {0.4, 0.75, 1})
    apply_saved_or_default_position(popup, source_pos)
    popup:Show()
end

function M.hide()
    if popup then popup:Hide() end
end

function M.toggle_create()
    if popup and popup:IsShown() and (mode == "raidres" or mode == "local") then
        M.hide()
    else
        M.show_create()
    end
end


function M.on_rf_data_result(success, rf_data, status)
    if not popup or not popup.rf_edit_box then return end
    if mode ~= "edit" then return end
    if not popup:IsShown() then return end
    if success and rf_data and rf_data ~= "" then
        popup.rf_edit_box:SetText(rf_data)
    else
        popup.rf_edit_box:SetText(status or "Error")
    end
end

m.EventManagePopup = M
return M
