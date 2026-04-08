RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.LocalEventPopup then return end

---@class LocalEventPopupModule
local M = {}

---@type ScrollDropdown
local scroll_drop = LibStub:GetLibrary("LibScrollDrop-1.3")

local popup
local event
local signup_id
local frame_cache = {}
local guild_online_cache = {}
local is_loading = false

local buttons = { "Signup", "Bench", "Late", "Tentative", "Absence", "Change Spec" }
local btn_keys = {}
for _, v in ipairs( buttons ) do
    btn_keys[ v ] = "btn_" .. string.gsub( string.lower( v ), "%s", "_" )
end
local button_keys = {
    Signup = "actions.signup",
    Bench = "actions.bench",
    Late = "actions.late",
    Tentative = "actions.tentative",
    Absence = "actions.absence",
    ["Change Spec"] = "actions.change_spec",
}
local class_order = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local class_specs = {
    Warrior = { "Arms", "Fury", "Protection" },
    Paladin = { "Holy", "Protection1", "Retribution" },
    Hunter = { "Beastmastery", "Marksmanship", "Survival" },
    Rogue = { "Assassination", "Combat", "Subtlety" },
    Priest = { "Discipline", "Holy1", "Shadow" },
    Shaman = { "Elemental", "Enhancement", "Restoration" },
    Mage = { "Arcane", "Fire", "Frost" },
    Warlock = { "Affliction", "Demonology", "Destruction" },
    Druid = { "Balance", "Feral", "Restoration1" },
}

local function T(key)
    if m.L then
        return m.L(key)
    end
    return key
end

local function save_position(self)
    local point, _, relative_point, x, y = self:GetPoint()

    m.db.popup_event = m.db.popup_event or {}
    m.db.popup_event.position = {
        point = point,
        relative_point = relative_point,
        x = x,
        y = y,
    }
end

local function close_open_dropdowns()
    if CloseDropDownMenus then
        pcall(CloseDropDownMenus)
    end

    if scroll_drop then
        if scroll_drop.dropdown_list and scroll_drop.dropdown_list.frame then
            scroll_drop.dropdown_list.frame:Hide()
        end
        scroll_drop.active_dropdown = nil
    end

    if popup then
        if popup.dd_class and popup.dd_class.edit_box then
            popup.dd_class.edit_box:ClearFocus()
        end
        if popup.dd_spec and popup.dd_spec.edit_box then
            popup.dd_spec.edit_box:ClearFocus()
        end
    end
end

local function on_hide()
    close_open_dropdowns()
    if m.calendar_popup and m.calendar_popup.unselect then
        m.calendar_popup.unselect()
    end
end

local function get_from_cache(frame_type)
    frame_cache[frame_type] = frame_cache[frame_type] or {}

    local i
    for i = getn(frame_cache[frame_type]), 1, -1 do
        if not frame_cache[frame_type][i].is_used then
            return frame_cache[frame_type][i]
        end
    end
end

local _guild_cache_time = 0
local function update_guild_online_cache()
    local now = GetTime()
    if now - _guild_cache_time < 30 then return end
    _guild_cache_time = now
    m.wipe(guild_online_cache)
    if IsInGuild and IsInGuild() then
        local i
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            guild_online_cache[name] = isOnline
        end
    end
end

local function is_player_online(signup_name)
    local name
    for name in string.gmatch(signup_name or "", "([^/]+)") do
        name = strtrim(name)
        if guild_online_cache[name] then
            return name
        end
    end
    return false
end

local function can_manage_local(ev)
    if not ev then return false end
    if ev.creator == m.player then return true end
    if m.db and m.db.user_settings and m.db.user_settings.has_manager_role == true then
        return true
    end
    return false
end

local function get_my_signup(ev)
    local signups = ev and ev.signups or nil
    local i

    if not signups then
        return nil, nil
    end

    for i = 1, getn(signups) do
        if signups[i].player == m.player then
            return signups[i], i
        end
    end

    return nil, nil
end

local function create_local_signup_payload(status_override)
    if not event then return nil end

    local my_signup = get_my_signup(event)

    -- Classe/spec : priorité aux dropdowns s'ils sont visibles et remplis (mode Change Spec)
    -- Sinon réutiliser l'inscription existante. Seulement en l'absence totale d'inscription,
    -- la sélection dans le dropdown est obligatoire.
    local dd_class_value = popup.dd_class and popup.dd_class:IsShown() and popup.dd_class.selected or nil
    local dd_spec_value  = popup.dd_spec  and popup.dd_spec:IsShown()  and popup.dd_spec.selected  or nil

    local className
    local specName

    if dd_class_value and dd_class_value ~= "" then
        -- Dropdown visible et rempli (Change Spec) — utiliser la sélection
        className = dd_class_value
        specName  = dd_spec_value
    elseif my_signup then
        -- Joueur déjà inscrit — réutiliser sa classe/spec existante
        className = (my_signup.className ~= "" and my_signup.className) or nil
        specName  = (my_signup.specName  ~= "" and my_signup.specName)  or nil
    else
        -- Première inscription — les dropdowns doivent être remplis
        className = dd_class_value
        specName  = dd_spec_value
    end

    -- Valider seulement pour une première inscription sans signup existant
    if not my_signup then
        if not className or className == "" then
            m.error(T("ui.class_not_selected") or "Class not selected")
            return nil
        end
        if not specName or specName == "" then
            m.error(T("ui.spec_not_selected") or "Spec not selected")
            return nil
        end
        m.db.user_settings = m.db.user_settings or {}
        m.db.user_settings.local_event_class = className
        m.db.user_settings.local_event_spec  = specName
    end

    return {
        id        = event.id,
        className = className or "",
        specName  = specName  or "",
        status    = status_override or "Signup",
    }
end

local apply_signup_popup_layout

local function on_button_click()
    local btn_name = this.action or this.title
    local payload
    local _, v

    if not event or is_loading then
        return
    end

    if btn_name == "Change Spec" then
        -- Pré-sélectionner la classe/spec de l'inscription existante
        local cs = get_my_signup(event)
        if cs then
            popup.dd_class:SetSelected(cs.className)
            popup.dd_spec:SetSelected(cs.specName)
        end
        for _, v in buttons do
            local btn = btn_keys[ v ]
            if popup[btn] then
                popup[btn]:Hide()
            end
        end
        popup.cs_change:Enable()
        popup.cs_change:Show()
        popup.cs_cancel:Enable()
        popup.cs_cancel:Show()
        apply_signup_popup_layout("change_spec")
        popup.dd_class:Show()
        popup.dd_spec:Show()
        return
    end

    payload = create_local_signup_payload(btn_name)
    if not payload then
        return
    end

    is_loading = true
    for _, v in buttons do
        local btn = btn_keys[ v ]
        if popup[btn] then
            popup[btn]:Disable()
        end
    end
    popup.cs_change:Disable()
    popup.cs_cancel:Disable()

    m.msg.local_event_signup(payload)
end

local function change_spec()
    local current_signup
    local payload

    if not event or is_loading then
        return
    end

    current_signup = get_my_signup(event)
    payload = create_local_signup_payload(current_signup and current_signup.status or "Signup")
    if not payload then
        return
    end

    is_loading = true
    popup.cs_change:Disable()
    popup.cs_cancel:Disable()
    m.msg.local_event_signup(payload)
end

apply_signup_popup_layout = function(mode)
    if not popup then
        return
    end

    local _, v
    local previous

    for _, v in buttons do
        local btn = btn_keys[ v ]
        if popup[btn] then
            popup[btn]:ClearAllPoints()
            popup[btn]:SetWidth(100)
        end
    end

    popup.cs_change:ClearAllPoints()
    popup.cs_change:SetWidth(100)
    popup.cs_cancel:ClearAllPoints()
    popup.cs_cancel:SetWidth(100)
    popup.dd_class:ClearAllPoints()
    popup.dd_spec:ClearAllPoints()

    if mode == "signed" then
        for _, v in buttons do
            local btn = btn_keys[ v ]
            if popup[btn] then
                if previous then
                    popup[btn]:SetPoint("TopRight", previous, "BottomRight", 0, -5)
                else
                    popup[btn]:SetPoint("Top", popup.attending, "TopRight", 0, 0)
                    popup[btn]:SetPoint("Right", popup, "Right", -10, 0)
                end
                previous = popup[btn]
            end
        end
        return
    end

    if mode == "signup" then
        popup.btn_signup:SetPoint("Top", popup.attending, "TopRight", 0, 0)
        popup.btn_signup:SetPoint("Right", popup, "Right", -10, 0)
        popup.dd_class:SetPoint("TopRight", popup.btn_signup, "BottomRight", 0, -14)
        popup.dd_spec:SetPoint("TopRight", popup.dd_class, "BottomRight", 0, -8)
        return
    end

    if mode == "change_spec" then
        popup.cs_change:SetPoint("Top", popup.attending, "TopRight", 0, 0)
        popup.cs_change:SetPoint("Right", popup, "Right", -10, 0)
        popup.cs_cancel:SetPoint("TopRight", popup.cs_change, "BottomRight", 0, -5)
        popup.dd_class:SetPoint("TopRight", popup.cs_cancel, "BottomRight", 0, -14)
        popup.dd_spec:SetPoint("TopRight", popup.dd_class, "BottomRight", 0, -8)
        return
    end
end

local function create_class_frame(parent, class, count)
    local frame = get_from_cache("class")

    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame:SetWidth(100)
        frame:SetHeight(100)

        frame.header = m.GuiElements.create_icon_label(frame, "", 100)
        frame.header:SetPoint("TopLeft", frame, "TopLeft", 0, 0)
        frame.header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        frame.header:SetBackdropColor(0.3, 0.3, 0.3, 1)

        frame.is_used = true
        table.insert(frame_cache["class"], frame)
    else
        frame:SetParent(parent)
        frame.is_used = true
    end

    -- Status sections (Bench/Late/Tentative/Absence/Signup) use action locale keys
    -- WoW class sections (Warrior/Priest/etc.) use class_name
    local status_label_keys = {
        Bench = "actions.bench", Late = "actions.late",
        Tentative = "actions.tentative", Absence = "actions.absence", Signup = "actions.signup",
    }
    local label
    if status_label_keys[class] then
        label = T(status_label_keys[class]) or class
    elseif m.class_name then
        label = m.class_name(class) or class
    else
        label = T(class) or class
    end
    frame.header.set(label .. " (" .. tostring(count) .. ")")

    if m.GuiElements.class_icons[string.upper(class or "")] then
        frame.header.set_icon("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        frame.header.icon:SetTexCoord(unpack(m.GuiElements.class_icons[string.upper(class)]))
        frame.header.icon:Show()
    else
        frame.header.set_icon(nil)
        if frame.header.icon then
            frame.header.icon:Hide()
        end
    end

    frame:Show()
    return frame
end

local function create_player_label(parent, width)
    local label_frame

    if m.GuiElements and m.GuiElements.create_label then
        label_frame = m.GuiElements.create_label(parent, "", width)
        if label_frame and label_frame.label then
            return label_frame
        end
    end

    label_frame = CreateFrame("Frame", nil, parent)
    label_frame:SetWidth(width or 80)
    label_frame:SetHeight(16)

    label_frame.label = label_frame:CreateFontString(nil, "ARTWORK", "RCFontNormal")
    label_frame.label:SetAllPoints(label_frame)
    label_frame.label:SetJustifyH("LEFT")
    label_frame.label:SetTextColor(1, 1, 1)
    label_frame.label:SetNonSpaceWrap(false)

    label_frame.set = function(text)
        label_frame.label:SetText(text or "")
    end

    return label_frame
end

local function create_player_frame(parent, signup)
    local frame = get_from_cache("player")
    local spec_text
    local online

    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame:SetWidth(100)
        frame:SetHeight(17)

        frame.spec = CreateFrame("Frame", nil, frame)
        frame.spec:SetWidth(16)
        frame.spec:SetHeight(16)
        frame.spec:SetPoint("TopLeft", frame, "TopLeft", 2, -1)

        frame.spec.icon = frame.spec:CreateTexture(nil, "ARTWORK")
        frame.spec.icon:SetAllPoints(frame.spec)

        frame.player = create_player_label(frame, 80)
        frame.player:SetPoint("TopLeft", frame, "TopLeft", 20, -1)
        frame.player.label:SetJustifyH("LEFT")

        frame.is_used = true
        table.insert(frame_cache["player"], frame)
    else
        frame:SetParent(parent)
        frame.is_used = true
    end

    spec_text = signup.specName and (m.spec_name and m.spec_name(signup.specName) or signup.specName) or ""
    if m.GuiElements.spec_icons[signup.specName or ""] then
        frame.spec.icon:SetTexture(m.GuiElements.spec_icons[signup.specName])
        frame.spec.icon:Show()
    else
        frame.spec.icon:SetTexture(nil)
        frame.spec.icon:Hide()
    end

    frame.player.set((signup.player or "") .. (spec_text ~= "" and (" (" .. spec_text .. ")") or ""))

    online = is_player_online(signup.player)
    frame.player.label:SetTextColor(online and 1 or 0.75, online and 1 or 0.7, online and 1 or 0.7)
    frame:Show()

    return frame
end

local function apply_local_pfui_skin(frame)
    local api
    local buttons
    local _, v

    if not (m.pfui_skin_enabled and m.api and m.api.pfUI and m.api.pfUI.api and frame) then
        return
    end

    api = m.api.pfUI.api
    buttons = { "Signup", "Bench", "Late", "Tentative", "Absence", "Change Spec" }

    local function skin_dropdown(dd)
        if not dd then
            return
        end
        api.StripTextures(dd)
        api.CreateBackdrop(dd, nil, true)
        if dd.dropdown_button then
            api.SkinArrowButton(dd.dropdown_button, "down", 16)
            dd.dropdown_button:SetPoint("Right", dd, "Right", -4, 0)
        end
    end

    for _, v in buttons do
        local btn = btn_keys[ v ]
        if frame[btn] then
            api.SkinButton(frame[btn])
            frame[btn]:SetHeight(22)
        end
    end

    if frame.cs_change then
        api.SkinButton(frame.cs_change)
        frame.cs_change:SetHeight(22)
    end
    if frame.cs_cancel then
        api.SkinButton(frame.cs_cancel)
        frame.cs_cancel:SetHeight(22)
    end

    if frame.border_desc then
        api.StripTextures(frame.border_desc, nil, "BACKGROUND")
        api.CreateBackdrop(frame.border_desc, nil, true)
    end
    if frame.attending then
        api.StripTextures(frame.attending, nil, "BACKGROUND")
        api.CreateBackdrop(frame.attending, nil, true)
    end
    if frame.missing then
        api.StripTextures(frame.missing, nil, "BACKGROUND")
        api.CreateBackdrop(frame.missing, nil, true)
    end
    if frame.scroll_bar then
        api.SkinScrollbar(frame.scroll_bar)
    end

    skin_dropdown(frame.dd_class)
    skin_dropdown(frame.dd_spec)
end

local function create_frame()
    local frame = m.FrameBuilder.new()
        :name("RaidCalendarLocalEventPopup")
        :title(string.format("Raid Calendar v%s", m.version))
        :frame_style("TOOLTIP")
        :frame_level(100)
        :backdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
        :backdrop_color(0, 0, 0, 0.9)
        :close_button()
        :width(540)
        :height(380)
        :movable()
        :esc()
        :on_drag_stop(save_position)
        :on_hide(on_hide)
        :build()

    if m.db.popup_event and m.db.popup_event.position then
        local p = m.db.popup_event.position
        frame:ClearAllPoints()
        frame:SetPoint(p.point, UIParent, p.relative_point, p.x, p.y)
    end

    frame.btn_manage = m.GuiElements.tiny_button(frame, "E", T("ui.manage_event") or "Manage event", "#1565c0")
    frame.btn_manage:SetPoint("Right", frame.titlebar.btn_close, "Left", -4, 0)
    frame.btn_manage:SetScript("OnClick", function()
        if event and m.EventManagePopup then
            m.EventManagePopup.show_edit_local(event.id)
        end
    end)
    frame.btn_manage:Hide()

    frame.btn_delete = m.GuiElements.tiny_button(frame, "X", T("event_manage.delete") or "Delete", "#c62828")
    frame.btn_delete:SetPoint("Right", frame.btn_manage, "Left", -4, 0)
    frame.btn_delete:SetScript("OnClick", function()
        if not event then return end
        StaticPopupDialogs["RC_CONFIRM_DELETE_LOCAL_POPUP"] = {
            text = T("local_event.confirm_delete") or "Delete this event?",
            button1 = T("event_manage.confirm_delete_yes") or "Delete",
            button2 = T("common.no") or "No",
            OnAccept = function()
                m.LocalEventManager.delete(event.id)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("RC_CONFIRM_DELETE_LOCAL_POPUP")
    end)
    frame.btn_delete:Hide()

    frame.online_indicator = m.GuiElements.create_online_indicator(frame, frame.btn_delete)

    local border_desc = m.FrameBuilder.new()
        :parent(frame)
        :point("TopLeft", frame, "TopLeft", 10, -32)
        :point("BottomRight", frame, "TopRight", -10, -132)
        :frame_style("TOOLTIP")
        :backdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
        :backdrop_color(0.08, 0.08, 0.08, 1)
        :build()

    border_desc:EnableMouseWheel(true)
    border_desc:SetScript("OnMouseWheel", function()
        local value = frame.scroll_bar:GetValue() - arg1 * 11.851852176058
        frame.scroll_bar:SetValue(value)
    end)
    frame.border_desc = border_desc

    local scroll_bar = CreateFrame("Slider", "RaidCalendarLocalDescScrollBar", border_desc, "UIPanelScrollBarTemplate")
    frame.scroll_bar = scroll_bar
    scroll_bar:SetPoint("TopRight", border_desc, "TopRight", -5, -20)
    scroll_bar:SetPoint("Bottom", border_desc, "Bottom", 0, 20)
    scroll_bar:SetMinMaxValues(0, 0)
    scroll_bar:SetValueStep(1)
    scroll_bar:SetScript("OnValueChanged", function()
        frame.desc:SetPoint("Top", border_desc, "Top", 0, arg1 - 10)
    end)

    frame.desc_scroll = CreateFrame("ScrollFrame", nil, border_desc)
    frame.desc_scroll:SetPoint("TopLeft", border_desc, "TopLeft", 8, -5)
    frame.desc_scroll:SetPoint("BottomRight", border_desc, "BottomRight", -22, 5)

    frame.desc_frame = CreateFrame("Frame", nil, frame.desc_scroll)
    frame.desc_scroll:SetScrollChild(frame.desc_frame)
    frame.desc_frame:SetWidth(480)
    frame.desc_frame:SetHeight(1)

    frame.desc = m.GuiElements.create_rich_text_frame(frame.desc_frame, 480)
    frame.desc:SetPoint("Top", frame.desc_frame, "Top", 0, 0)
    frame.desc:SetPoint("Left", frame.desc_frame, "Left", 0, 0)

    frame.leader = m.GuiElements.create_icon_label(frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_leader.tga", 140)
    frame.leader:SetPoint("TopLeft", frame, "TopLeft", 20, -140)

    frame.signups = m.GuiElements.create_icon_label(frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_signups.tga", 80)
    frame.signups:SetPoint("TopLeft", frame.leader, "TopRight", 5, 0)

    frame.date = m.GuiElements.create_icon_label(frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_date.tga", 110)
    frame.date:SetPoint("TopLeft", frame.signups, "TopRight", 5, 0)

    frame.time = m.GuiElements.create_icon_label(frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_time.tga", 70)
    frame.time:SetPoint("TopLeft", frame.date, "TopRight", 5, 0)

    frame.time_offset = m.GuiElements.create_icon_label(frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_hourglass.tga")
    frame.time_offset:SetPoint("TopLeft", frame.time, "TopRight", 5, 0)

    frame.attending = m.FrameBuilder.new()
        :parent(frame)
        :point("Top", frame.leader, "Bottom", 0, -7)
        :point("Left", frame, "Left", 10, 0)
        :frame_style("TOOLTIP")
        :backdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
        :backdrop_color(0.08, 0.08, 0.08, 1)
        :width(416)
        :build()

    frame.missing = m.FrameBuilder.new()
        :parent(frame)
        :point("TopLeft", frame.attending, "BottomLeft", 0, -5)
        :frame_style("TOOLTIP")
        :backdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
        :backdrop_color(0.08, 0.08, 0.08, 1)
        :width(416)
        :build()

    local prev
    local _, v
    for _, v in buttons do
        local btn = btn_keys[ v ]
        frame[btn] = m.GuiElements.create_button(frame, T(button_keys[v] or v) or v, 100, on_button_click)
        frame[btn].action = v
        if prev then
            frame[btn]:SetPoint("TopRight", prev, "BottomRight", 0, -5)
        else
            frame[btn]:SetPoint("Top", frame.attending, "TopRight", 0, 0)
            frame[btn]:SetPoint("Right", frame, "Right", -10, 0)
        end
        prev = frame[btn]
    end

    frame.cs_change = m.GuiElements.create_button(frame, T("Change") or "Change", 100, change_spec)
    frame.cs_change:SetPoint("TopRight", frame, "TopRight", -10, -230)
    frame.cs_change:Hide()

    frame.cs_cancel = m.GuiElements.create_button(frame, T("Cancel") or "Cancel", 100, function()
        if event then
            M.update(event.id)
        end
    end)
    frame.cs_cancel:SetPoint("TopRight", frame.cs_change, "BottomRight", 0, -5)
    frame.cs_cancel:Hide()

    frame.dd_class = scroll_drop:New(frame, {
        default_text = T("ui.select_class"),
        dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
        label_on_select = "value",
        search = false,
        width = 95,
    })
    frame.dd_class:SetPoint("TopRight", frame, "TopRight", -12, -360)
    frame.dd_class:SetItems(function()
        local list = {}
        local i
        for i = 1, getn(class_order) do
            table.insert(list, {
                value = class_order[i],
                text = m.class_name and m.class_name(class_order[i]) or class_order[i],
            })
        end
        return list
    end, function()
        frame.dd_spec:SetText(T("ui.select_spec"))
    end)

    frame.dd_spec = scroll_drop:New(frame, {
        default_text = T("ui.select_spec"),
        dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
        label_on_select = "value",
        search = false,
        width = 95,
    })
    frame.dd_spec:SetPoint("TopRight", frame.dd_class, "BottomRight", 0, -5)
    frame.dd_spec:SetItems(function()
        local list = {}
        local class = frame.dd_class.selected
        local specs = class and class_specs[class] or nil
        local i

        if specs then
            for i = 1, getn(specs) do
                table.insert(list, {
                    value = specs[i],
                    text = m.spec_name and m.spec_name(specs[i]) or specs[i],
                    icon = m.GuiElements.spec_icons[specs[i]],
                })
            end
        end

        return list
    end)

    m.GuiElements.pfui_skin(frame)
    apply_local_pfui_skin(frame)
    return frame
end

local function sort_local_signups(signups)
    table.sort(signups, function(a, b)
        local a_class = a.className or ""
        local b_class = b.className or ""
        local a_name = a.player or ""
        local b_name = b.player or ""
        if a_class == b_class then
            return a_name < b_name
        end
        return a_class < b_class
    end)
end

local function refresh(event_id)
    local now = time(date("*t"))
    -- S'assurer que is_loading est réinitialisé à chaque refresh
    -- pour éviter qu'un état bloqué empêche les clics sur les boutons
    is_loading = false
    local signups_count = { Total = 0 }
    local ordered_groups = {
        attending = {},
        missing = { "Bench", "Late", "Tentative", "Absence" },
    }
    local grouped = { attending = {}, missing = {} }
    local data = {
        attending = { x = 5, y = -5, max_y = 0, count = 0, total_y = 0 },
        missing = { x = 5, y = -5, max_y = 0, count = 0, total_y = 0 },
    }
    local signups
    local i, v

    close_open_dropdowns()
    event = m.LocalEventManager.get(event_id)
    if popup.online_indicator and popup.online_indicator.update then
        popup.online_indicator.update()
    end
    update_guild_online_cache()

    for _, frames in pairs(frame_cache) do
        for _, cached in ipairs(frames) do
            cached.is_used = false
            cached:Hide()
        end
    end

    if not event then
        popup.titlebar.title:SetText(T("local_event.not_found"))
        popup.desc:SetRichText(T("local_event.not_found"))
        popup.leader.set("?")
        popup.signups.set("0")
        popup.date.set("")
        popup.time.set("")
        popup.time_offset.set("")
        return
    end

    if m.L then
        for _, v in buttons do
            local btn = btn_keys[ v ]
            if popup[btn] then
                popup[btn]:SetText(T(button_keys[v] or v) or v)
            end
        end
        popup.cs_change:SetText(T("Change"))
        popup.cs_cancel:SetText(T("Cancel"))
    end

    popup.titlebar.title:SetText(event.title or "")
    popup.desc:SetRichText((event.description and event.description ~= "") and event.description or (T("local_event.no_description") or ""))
    popup.scroll_bar:SetMinMaxValues(0, math.max(0, popup.desc:GetHeight() - 65))
    popup.scroll_bar:SetValue(0)

    popup.leader.set(event.creator or "?")
    popup.date.set(m.format_local_date and m.format_local_date(event.startTime, "day_month_year") or date("%d/%m/%Y", event.startTime))
    popup.time.set(date((m.db.user_settings and m.db.user_settings.time_format == "24") and "%H:%M" or "%I:%M %p", event.startTime))
    popup.time_offset.set(m.format_time_difference and m.format_time_difference(event.startTime - now) or "")

    signups = event.signups or {}
    sort_local_signups(signups)

    signup_id = nil
    for i = 1, getn(signups) do
        local su = signups[i]
        local target
        local key
        if su.status == "Signup" then
            target = "attending"
            key = su.className or ""
            signups_count.Total = signups_count.Total + 1
            signups_count[key] = (signups_count[key] or 0) + 1
            if not m.find(key, ordered_groups.attending) then
                table.insert(ordered_groups.attending, key)
            end
        else
            target = "missing"
            key = su.status or "Absence"
            signups_count[key] = (signups_count[key] or 0) + 1
        end

        grouped[target][key] = grouped[target][key] or {}
        table.insert(grouped[target][key], su)

        if su.player == m.player then
            signup_id = i
        end
    end

    local extra = (signups_count.Tentative or 0) + (signups_count.Late or 0)
    popup.signups.set(tostring(signups_count.Total) .. (extra > 0 and (" (+" .. extra .. ")") or ""))

    table.sort(ordered_groups.attending, function(a, b)
        local ia = m.find(a, class_order) or 999
        local ib = m.find(b, class_order) or 999
        if ia == ib then return a < b end
        return ia < ib
    end)

    local function layout_group(panel_name, names)
        local n
        for n = 1, getn(names) do
            local group_name = names[n]
            local members = grouped[panel_name][group_name]
            local class_frame = create_class_frame(popup[panel_name], group_name, members and getn(members) or 0)
            local y = 17
            local j

            class_frame:SetPoint("TopLeft", popup[panel_name], "TopLeft", data[panel_name].x, data[panel_name].y)
            data[panel_name].x = data[panel_name].x + 102
            data[panel_name].count = data[panel_name].count + 1

            if members then
                for j = 1, getn(members) do
                    local player_frame = create_player_frame(class_frame, members[j])
                    player_frame:SetPoint("TopLeft", class_frame, "TopLeft", 0, -y)
                    y = y + 17
                    if y > data[panel_name].max_y then
                        data[panel_name].max_y = y
                    end
                end
            end

            if y == 17 then
                class_frame:Hide()
                data[panel_name].x = data[panel_name].x - 102
                data[panel_name].count = data[panel_name].count - 1
            end

            if data[panel_name].count ~= 0 and mod(data[panel_name].count, 4) == 0 and n ~= getn(names) then
                data[panel_name].x = 5
                data[panel_name].total_y = data[panel_name].total_y + data[panel_name].max_y + 15
                data[panel_name].y = -5 - data[panel_name].total_y
                data[panel_name].max_y = 0
            end

            class_frame:SetHeight(y)
        end
    end

    layout_group("attending", ordered_groups.attending)
    layout_group("missing", ordered_groups.missing)

    popup.attending:SetHeight(math.max(20, data.attending.total_y + data.attending.max_y + 9))

    if data.missing.count == 0 then
        popup.missing:SetHeight(0)
        popup.missing:Hide()
    else
        popup.missing:SetHeight(data.missing.total_y + data.missing.max_y + 9)
        popup.missing:Show()
    end

    popup:SetHeight(math.max(345, 196 + data.attending.total_y + data.attending.max_y + data.missing.total_y + data.missing.max_y))

    local my_signup = get_my_signup(event)

    -- Ne pré-sélectionne la classe/spec que si l'utilisateur modifie sa spé (Change Spec)
    -- Lors d'une inscription initiale, les dropdowns restent vides pour forcer le choix
    popup.dd_class:SetSelected(nil)
    popup.dd_class:Hide()
    popup.dd_spec:SetSelected(nil)
    popup.dd_spec:Hide()
    popup.cs_change:Hide()
    popup.cs_cancel:Hide()

    if can_manage_local(event) then
        popup.btn_manage:Show()
    else
        popup.btn_manage:Hide()
    end

    if my_signup then
        apply_signup_popup_layout("signed")
        for _, v in buttons do
            local btn = btn_keys[ v ]
            popup[btn]:Enable()
            popup[btn]:Show()
        end

        local status = my_signup.status or "Signup"
        local active_btn = btn_keys[ status ] or ("btn_" .. string.gsub( string.lower( status ), "%s", "_" ))
        if popup[active_btn] then
            popup[active_btn]:Disable()
        end
    else
        -- Vérifier le rôle : nil = pas encore connu (autoriser), false = refusé
        local has_manager = m.db and m.db.user_settings and m.db.user_settings.has_manager_role
        local has_raider  = m.db and m.db.user_settings and m.db.user_settings.has_raider_role
        local has_member  = m.db and m.db.user_settings and m.db.user_settings.has_member_role
        -- Refusé seulement si TOUS les rôles sont explicitement false
        local denied = has_member == false and has_raider == false and has_manager == false
        if not denied then
            apply_signup_popup_layout("signup")
            popup.btn_signup:Show()
            popup.btn_signup:Enable()
            popup.dd_class:Show()
            popup.dd_spec:Show()
            for _, v in buttons do
                if v ~= "Signup" then
                    local btn = btn_keys[ v ]
                    popup[btn]:Hide()
                end
            end
        else
            popup.btn_signup:Hide()
            popup.dd_class:Hide()
            popup.dd_spec:Hide()
            for _, v in buttons do
                popup[btn_keys[v]]:Hide()
            end
        end
    end

    if event.startTime < now then
        for _, v in buttons do
            local btn = btn_keys[ v ]
            popup[btn]:Disable()
        end
        popup.dd_class:Hide()
        popup.dd_spec:Hide()
        popup.cs_change:Hide()
        popup.cs_cancel:Hide()
        apply_local_pfui_skin(popup)
        return
    end

    apply_local_pfui_skin(popup)
end

function M.show(event_id)
    -- Ferme les autres popups secondaires
    if m.close_all_popups then m.close_all_popups() end

    if not popup then
        popup = create_frame()
    end

    -- Reset is_loading so a stale state from a previous session doesn't block clicks
    is_loading = false
    close_open_dropdowns()
    popup:Show()
    refresh(event_id)
end

function M.hide()
    if popup then
        close_open_dropdowns()
        popup:Hide()
    end
end

function M.toggle(event_id)
    if popup and popup:IsVisible() and event and ((event.id and event_id == event.id) or not event_id) then
        popup:Hide()
    elseif (event and event.id) or event_id then
        M.show(event_id or event.id)
    end
end

function M.is_visible()
    return popup and popup:IsVisible() or false
end

function M.update(event_id)
    if popup and popup:IsVisible() then
        if event_id and event and event.id ~= event_id then
            return
        end
        is_loading = false
        refresh(event_id or event.id)
    end
end

function M.refresh_current()
    if popup and popup:IsVisible() and event then
        is_loading = false
        refresh(event.id)
    end
end

function M.on_signup_error(_)
    is_loading = false
    if popup then
        local _, v
        for _, v in buttons do
            local btn = btn_keys[ v ]
            if popup[btn] then
                popup[btn]:Enable()
            end
        end
        popup.cs_change:Enable()
        popup.cs_cancel:Enable()
    end
end

m.LocalEventPopup = M
return M
