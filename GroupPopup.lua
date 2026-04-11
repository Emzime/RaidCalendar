RaidCalendar = RaidCalendar or {}
local m = RaidCalendar
if m.GroupPopup then return end

local M = {}

local function T(key, vars) return m.L and m.L(key, vars) or key end

local function extract_tagged_link( description, tag )
	if not description or description == "" then return nil end
	local pattern = tag .. "[ ]*%-%>[ ]*(https://[^%s]+)"
	return string.match( description, pattern )
end

local function sep(parent, y)
	local l = parent:CreateTexture(nil, "ARTWORK")
	l:SetTexture("Interface\\Buttons\\WHITE8x8")
	l:SetVertexColor(1, 0.82, 0, 0.35)
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	l:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
	l:SetHeight(1)
end

local function lbl(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetTextColor(1, 0.82, 0, 1)
	fs:SetText(text)
	return fs
end

local CLASS_COLOR = {
	Druid   = {1, 0.49, 0.04}, Hunter  = {0.67, 0.83, 0.45},
	Mage    = {0.41, 0.80, 0.94}, Paladin = {0.96, 0.55, 0.73},
	Priest  = {1, 1, 1}, Rogue = {1, 0.96, 0.41},
	Shaman  = {0, 0.44, 0.87}, Warlock = {0.58, 0.51, 0.79},
	Warrior = {0.78, 0.61, 0.43},
}

local function cc(cls)
	local c = CLASS_COLOR[cls]
	return c and c[1] or 0.8, c and c[2] or 0.8, c and c[3] or 0.8
end

local GROUPS = 8
local SLOTS  = 5

-- Layout constants bundled into one table so build() needs only 1 upvalue
-- instead of 12, keeping the closure under WoW Classic Lua's 32-upvalue limit.
local K = {
	POP_W         = 700,
	POP_H         = 458,     -- espace suplementaire pour lead/assistant + SR + RF + RH
	GRP_HDR       = 18,
	SLOT_H        = 18,
	GRP_H         = 108,      -- GRP_HDR(18) + SLOTS(5)*SLOT_H(18)
	LEFT_X        = 10,
	LEFT_W        = 155,
	RIGHT_X       = 175,      -- LEFT_X(10) + LEFT_W(155) + 10
	COL_W         = 125,
	SEP_Y         = -18,      -- s\195\169parateur juste sous la barre titre
	INFO_Y        = -28,      -- ligne RL/Ass/Fil sous le s\195\169parateur
	COL_LABEL_Y   = -44,      -- labels "Inscrits" / "Groupes de Raid"
	ROW1_Y        = -66,
	ROW2_Y        = -182,     -- ROW1_Y(-66) - GRP_H(108) - ROW_GAP(8)
	CONTENT_BOT_Y = -294,     -- ROW2_Y(-182) - GRP_H(108) - 4
	SR_Y          = -316,     -- ligne SR (raidres URL)
	RF_Y          = -336,     -- ligne RF sous SR
	RH_Y          = -356,     -- ligne RH Plan sous RF
	STATUS_Y      = -394,    -- d\195\169cal\195\169 pour SR + RF + RH
}

local popup = nil
local event_id = nil
local selected = nil
local sync_state = "idle"
local sync_message = ""
local last_sync_by = nil
local last_sync_at = nil
local last_sync_ok = nil
local last_sync_rh = nil
local update_group_thread_ui

local function get_storage()
	m.db = m.db or {}
	m.db.popup_group = m.db.popup_group or {}
	return m.db.popup_group
end

local function get_group_plan_store()
	m.db = m.db or {}
	m.db.group_plans = m.db.group_plans or {}
	return m.db.group_plans
end
local function get_group_thread_store()
	m.db = m.db or {}
	m.db.group_thread_contexts = m.db.group_thread_contexts or {}
	return m.db.group_thread_contexts
end

local function get_current_user_id()
	return m.db and m.db.user_settings and m.db.user_settings.discord_id or ""
end

local function get_current_context()
	local store = get_group_thread_store()
	local ctxs = store[event_id]
	local my_id = get_current_user_id()
	if not ctxs then return nil end
	for _, ctx in pairs(ctxs) do
		if ctx and (ctx.managerDiscordUserId == my_id or ctx.assistantDiscordUserId == my_id) then
			return ctx
		end
	end
	for _, ctx in pairs(ctxs) do return ctx end
	return nil
end

local function get_event_meta()
	local ev = m.db and m.db.events and m.db.events[event_id]
	if not ev then return "", 0 end
	return ev.title or "", tonumber(ev.startTime) or 0
end


local function save_position(self)
	if not self or not self.GetPoint then return end
	local point, _, rp, x, y = self:GetPoint()
	get_storage().position = { point = point, relative_point = rp, x = x, y = y }
end

local function apply_position(f)
	if not f then return end
	local storage = get_storage()
	local pos = storage.position

	if not pos then
		local candidates = {
			m.event_popup and m.event_popup.get_frame and m.event_popup.get_frame(),
			m.LocalEventPopup and m.LocalEventPopup.get_frame and m.LocalEventPopup.get_frame(),
			m.EventManagePopup and m.EventManagePopup.get_frame and m.EventManagePopup.get_frame(),
		}
		for i = 1, table.getn(candidates) do
			local cf = candidates[i]
			if cf and cf.IsVisible and cf:IsVisible() and cf.GetPoint then
				local pt, _, rp, x, y = cf:GetPoint()
				if pt then
					pos = { point = pt, relative_point = rp, x = x, y = y }
					break
				end
			end
		end
	end

	f:ClearAllPoints()
	if pos and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relative_point or pos.point, pos.x or 0, pos.y or 0)
		f:SetFrameStrata("DIALOG")
	elseif m.calendar_popup and m.calendar_popup.frame and m.calendar_popup.frame:IsVisible() then
		f:SetPoint("CENTER", m.calendar_popup.frame, "CENTER", 0, 0)
		f:SetFrameStrata("DIALOG")
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 60, 0)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
	end
	f:SetToplevel(true)
	f:Raise()
end

local function get_plan()
	local store = get_group_plan_store()
	store[event_id] = store[event_id] or {}
	return store[event_id]
end

local function clear_plan_local()
	local store = get_group_plan_store()
	store[event_id] = {}
end

local function plan_place(name, g, s)
	local p = get_plan()
	for gi = 1, GROUPS do
		for si = 1, SLOTS do
			if p[gi] and p[gi][si] == name then
				p[gi][si] = nil
			end
		end
	end
	if name and g and s then
		p[g] = p[g] or {}
		p[g][s] = name
	end
end

local function plan_find(name)
	local p = get_plan()
	for g = 1, GROUPS do
		for s = 1, SLOTS do
			if p[g] and p[g][s] == name then
				return g, s
			end
		end
	end
	return nil, nil
end

local function plan_occupant(g, s)
	local p = get_plan()
	return p[g] and p[g][s] or nil
end

local function format_sync_time(ts)
	if not ts or ts == "" then return "" end
	local num = tonumber(ts)
	if not num then return "" end
	return date("%H:%M:%S", num)
end

local function update_status_label()
	if not popup or not popup.lbl_status then return end

	local state_text = ""
	if sync_state == "saving" then
		state_text = T("group_popup.status_saving") or "Raid-Helper synchronization..."
	elseif sync_state == "reloading" then
		state_text = T("group_popup.status_reloading") or "Reloading from Raid-Helper..."
	elseif sync_state == "clearing" then
		state_text = T("group_popup.status_clearing") or "Clearing Raid-Helper..."
	else
		if sync_message and sync_message ~= "" then
			state_text = sync_message
		else
			state_text = T("group_popup.status_idle") or "Idle."
		end
	end

	local meta = ""
	if last_sync_by and last_sync_by ~= "" then
		meta = string.format(T("group_popup.status_last_sync") or " Last sync: %s at %s.", last_sync_by, format_sync_time(last_sync_at))
	end
	local rh_meta = ""
	if last_sync_rh and last_sync_rh ~= "" then
		rh_meta = string.format(" | %s %s", T("group_popup.rh_label") or "Raid-Helper:", last_sync_rh)
	end

	popup.lbl_status:SetText(state_text .. meta .. rh_meta)
	if last_sync_ok == false then
		popup.lbl_status:SetTextColor(1, 0.35, 0.35, 1)
	elseif sync_state == "saving" or sync_state == "reloading" or sync_state == "clearing" then
		popup.lbl_status:SetTextColor(1, 0.82, 0, 1)
	else
		popup.lbl_status:SetTextColor(0.75, 0.75, 0.75, 1)
	end
end

local function set_sync_state(state, message, ok, by, ts, rh_status)
	sync_state = state or "idle"
	sync_message = message or ""
	if ok ~= nil then last_sync_ok = ok end
	if by ~= nil then last_sync_by = by end
	if ts ~= nil then last_sync_at = ts end
	if rh_status ~= nil then last_sync_rh = rh_status end
	update_status_label()
	update_group_thread_ui()
end

local reload_timer_id = nil
local watch_timer_id = nil

local function send_watch_state(active)
	if not event_id or not m.msg or not m.msg.group_plan_watch then return end
	m.msg.group_plan_watch(event_id, (m.db and m.db.user_settings and m.db.user_settings.discord_id) or "", active and true or false)
end

local function start_watch_timer()
	if not m.ace_timer then return end
	if watch_timer_id then
		m.ace_timer.CancelTimer(m, watch_timer_id)
		watch_timer_id = nil
	end
	watch_timer_id = m.ace_timer.ScheduleRepeatingTimer(m, function()
		if popup and popup:IsVisible() and event_id then
			send_watch_state(true)
		else
			if watch_timer_id then
				m.ace_timer.CancelTimer(m, watch_timer_id)
				watch_timer_id = nil
			end
		end
	end, 45)
end

local function stop_watch_timer()
	if watch_timer_id and m.ace_timer then
		m.ace_timer.CancelTimer(m, watch_timer_id)
		watch_timer_id = nil
	end
end

local function request_reload()
	if not event_id or not m.msg or not m.msg.group_plan_get then return end
	set_sync_state("reloading", T("group_popup.status_reloading") or "Reloading from Raid-Helper...", nil, nil, nil, nil)
	m.msg.group_plan_get(event_id, (m.db and m.db.user_settings and m.db.user_settings.discord_id) or "")
	-- If no response after 8 seconds, show bot unreachable message
	if reload_timer_id and m.ace_timer then
		m.ace_timer.CancelTimer(m, reload_timer_id)
		reload_timer_id = nil
	end
	if m.ace_timer then
		reload_timer_id = m.ace_timer.ScheduleTimer(m, function()
			reload_timer_id = nil
			if sync_state == "reloading" then
				set_sync_state("idle",
					T("group_popup.status_bot_unreachable") or "Bot unreachable. Check that the bot is online.",
					false, nil, nil, nil)
			end
		end, 8)
	end
end

local function save_remote()
	if not event_id or not m.msg or not m.msg.group_plan_save then return end
	set_sync_state("saving", T("group_popup.status_saving") or "Raid-Helper synchronization...", nil, nil, nil, nil)
	m.msg.group_plan_save(event_id, (m.db and m.db.user_settings and m.db.user_settings.discord_id) or "", get_plan())
end

local function clear_remote()
	if not event_id or not m.msg or not m.msg.group_plan_clear then return end
	set_sync_state("clearing", T("group_popup.status_clearing") or "Clearing Raid-Helper...", nil, nil, nil, nil)
	m.msg.group_plan_clear(event_id, (m.db and m.db.user_settings and m.db.user_settings.discord_id) or "")
end

local function normalize_signup_text( value )
	if not value then return "" end
	value = tostring( value )
	value = string.gsub( value, "^%s+", "" )
	value = string.gsub( value, "%s+$", "" )
	value = string.lower( value )
	return value
end

local function signup_bucket( signup )
	local status = normalize_signup_text( signup and signup.status )
	local class_name = normalize_signup_text( signup and signup.className )
	local role_name = normalize_signup_text( signup and signup.roleName )
	local value = status
	if value == "" then value = class_name end
	if value == "" then value = role_name end

	if value == "bench" or value == "remplaçant" or value == "remplacant"
		or value == "late" or value == "retard" then
		return "secondary"
	end

	if value == "absence" or value == "absent"
		or value == "tentative" or value == "incertain" or value == "uncertain" then
		return "hidden"
	end

	if value == "signup" or value == "inscription" or value == "confirmé" or value == "confirme"
		or value == "confirmed" then
		return "primary"
	end

	if class_name ~= "" and class_name ~= "bench" and class_name ~= "remplaçant" and class_name ~= "remplacant"
		and class_name ~= "late" and class_name ~= "retard"
		and class_name ~= "absence" and class_name ~= "absent"
		and class_name ~= "tentative" and class_name ~= "incertain" and class_name ~= "uncertain" then
		return "primary"
	end

	return "hidden"
end

local function is_primary_signup_status( signup )
	return signup_bucket( signup ) == "primary"
end

local function is_secondary_signup_status( signup )
	return signup_bucket( signup ) == "secondary"
end

local function build()
	local gui = m.GuiElements

	local f = m.FrameBuilder.new()
		:name("RaidCalendarGroupPopup")
		:title("RaidCalendar")
		:frame_style("TOOLTIP")
		:backdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		:backdrop_color(0.10, 0.08, 0.02, 1)
		:close_button()
		:frame_level(130)
		:width(K.POP_W)
		:height(K.POP_H)
		:movable()
		:esc()
		:on_hide(function()
			stop_watch_timer()
			send_watch_state(false)
			selected = nil
			save_position(popup)
		end)
		:build()

	f:SetBackdrop({
		bgFile   = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile     = false, tileSize = 0, edgeSize = 16,
		insets   = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0.12, 0.10, 0.03, 1)
	f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	f:SetClampedToScreen(true)
	f:Hide()
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		save_position(this)
	end)

	-- Titlebar = "Nom du raid — Plan de raid" (mis à jour dans refresh)
	f.titlebar.title:SetText(T("group_popup.title") or "Group Plan")

	-- RL + Ass (optionnel) + Fil (optionnel) : centré sous la barre titre
	f.lbl_raid_info = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_raid_info:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, K.INFO_Y)
	f.lbl_raid_info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, K.INFO_Y)
	f.lbl_raid_info:SetJustifyH("CENTER")
	f.lbl_raid_info:SetTextColor(0.75, 0.75, 0.75, 1)
	f.lbl_raid_info:SetText("")

	local LEFT_TOP_LABEL_Y = K.COL_LABEL_Y
	local LEFT_TOP_TOP_Y = K.ROW1_Y
	local LEFT_TOP_BOTTOM_Y = -188
	local LEFT_BOTTOM_LABEL_Y = -198
	local LEFT_BOTTOM_TOP_Y = -220
	local LEFT_BOTTOM_BOTTOM_Y = K.CONTENT_BOT_Y

	lbl(f, T("group_popup.available_primary") or T("group_popup.available") or "Signups", K.LEFT_X, LEFT_TOP_LABEL_Y)
	lbl(f, T("group_popup.available_secondary") or "Bench / Late", K.LEFT_X, LEFT_BOTTOM_LABEL_Y)
	lbl(f, T("group_popup.groups_title") or "Raid Groups", K.RIGHT_X, K.COL_LABEL_Y)

	local function create_player_list(name_prefix, top_y, bottom_y)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\Buttons\\WHITE8x8")
		bg:SetVertexColor(0.04, 0.04, 0.04, 1)
		bg:SetPoint("TOPLEFT", f, "TOPLEFT", K.LEFT_X, top_y)
		bg:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W, bottom_y)

		local scroll = CreateFrame("ScrollFrame", name_prefix .. "Scroll", f)
		scroll:SetPoint("TOPLEFT", f, "TOPLEFT", K.LEFT_X, top_y)
		scroll:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W - 14, bottom_y)

		local sc = CreateFrame("Frame", nil, scroll)
		sc:SetWidth(K.LEFT_W - 20)
		sc:SetHeight(400)
		scroll:SetScrollChild(sc)

		local track = f:CreateTexture(nil, "BACKGROUND")
		track:SetTexture("Interface\\Buttons\\WHITE8x8")
		track:SetVertexColor(0.1, 0.08, 0.01, 1)
		track:SetPoint("TOPLEFT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W - 13, top_y)
		track:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W, bottom_y)

		local slider = CreateFrame("Slider", name_prefix .. "Slider", f)
		slider:SetWidth(11)
		slider:SetPoint("TOPLEFT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W - 12, top_y)
		slider:SetPoint("BOTTOMLEFT", f, "TOPLEFT", K.LEFT_X + K.LEFT_W - 12, bottom_y)
		slider:SetOrientation("VERTICAL")
		slider:SetMinMaxValues(0, 0)
		slider:SetValue(0)
		slider:SetValueStep(20)
		slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
		if slider:GetThumbTexture() then
			slider:GetThumbTexture():SetVertexColor(1, 0.82, 0, 0.85)
			slider:GetThumbTexture():SetHeight(28)
		end

		slider:SetScript("OnValueChanged", function()
			scroll:SetVerticalScroll(slider:GetValue())
		end)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function()
			local mn, mx = slider:GetMinMaxValues()
			local nv = slider:GetValue() - arg1 * 40
			if nv < mn then nv = mn elseif nv > mx then nv = mx end
			slider:SetValue(nv)
		end)

		return { scroll = scroll, content = sc, slider = slider, buttons = {} }
	end

	f.primary_list = create_player_list("RCGroupPrimary", LEFT_TOP_TOP_Y, LEFT_TOP_BOTTOM_Y)
	f.secondary_list = create_player_list("RCGroupSecondary", LEFT_BOTTOM_TOP_Y, LEFT_BOTTOM_BOTTOM_Y)
	f.slots = {}
	for g = 1, GROUPS do f.slots[g] = {} end

	local function make_group(g, bx, by)
		local hbg = f:CreateTexture(nil, "BACKGROUND")
		hbg:SetTexture("Interface\\Buttons\\WHITE8x8")
		hbg:SetVertexColor(0.08, 0.065, 0.01, 1)
		hbg:SetPoint("TOPLEFT", f, "TOPLEFT", bx, by)
		hbg:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", bx + K.COL_W - 2, by - K.GRP_HDR)

		local hl = f:CreateTexture(nil, "ARTWORK")
		hl:SetTexture("Interface\\Buttons\\WHITE8x8")
		hl:SetVertexColor(1, 0.82, 0, 0.55)
		hl:SetPoint("TOPLEFT", f, "TOPLEFT", bx, by - K.GRP_HDR)
		hl:SetPoint("TOPRIGHT", f, "TOPLEFT", bx + K.COL_W - 2, by - K.GRP_HDR)
		hl:SetHeight(1)

		local gl = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
		gl:SetPoint("TOPLEFT", f, "TOPLEFT", bx + 3, by - 2)
		gl:SetTextColor(1, 0.82, 0, 1)
		gl:SetText(string.format(T("group_popup.group_n") or "Gr %d", g))

		for s = 1, SLOTS do
			local sy = by - K.GRP_HDR - (s - 1) * K.SLOT_H
			local slot = CreateFrame("Button", nil, f)
			slot:SetWidth(K.COL_W - 2)
			slot:SetHeight(K.SLOT_H)
			slot:SetPoint("TOPLEFT", f, "TOPLEFT", bx, sy)

			local sbg = slot:CreateTexture(nil, "BACKGROUND")
			sbg:SetAllPoints(slot)
			sbg:SetTexture("Interface\\Buttons\\WHITE8x8")
			sbg:SetVertexColor(0.04, 0.04, 0.04, 1)
			slot.bg = sbg

			local sln = slot:CreateTexture(nil, "BORDER")
			sln:SetTexture("Interface\\Buttons\\WHITE8x8")
			sln:SetVertexColor(0.12, 0.12, 0.12, 1)
			sln:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
			sln:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
			sln:SetHeight(1)
			slot.sln = sln

			local sfs = slot:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
			sfs:SetAllPoints(slot)
			sfs:SetJustifyH("CENTER")
			slot.name_fs = sfs

			slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			slot.group_idx = g
			slot.slot_idx = s

			slot:SetScript("OnClick", function()
				local sg, ss = this.group_idx, this.slot_idx
				local occ = plan_occupant(sg, ss)
				if selected then
					if occ then
						local og, os = plan_find(selected)
						if og then
							plan_place(occ, og, os)
						else
							local p2 = get_plan()
							for gi = 1, GROUPS do
								for si = 1, SLOTS do
									if p2[gi] and p2[gi][si] == occ then
										p2[gi][si] = nil
									end
								end
							end
						end
					end
					plan_place(selected, sg, ss)
					selected = nil
					M.update()
					save_remote()
				elseif occ then
					selected = occ
				end
				M.update()
			end)
			slot:SetScript("OnEnter", function()
				if selected or plan_occupant(this.group_idx, this.slot_idx) then
					this.sln:SetVertexColor(1, 0.82, 0, 0.8)
				end
			end)
			slot:SetScript("OnLeave", function()
				this.sln:SetVertexColor(0.12, 0.12, 0.12, 1)
			end)

			f.slots[g][s] = slot
		end
	end

	for i = 1, 4 do make_group(i, K.RIGHT_X + (i - 1) * K.COL_W, K.ROW1_Y) end
	for i = 5, 8 do make_group(i, K.RIGHT_X + (i - 5) * K.COL_W, K.ROW2_Y) end

	sep(f, -306)

	f.lbl_sr = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_sr:SetPoint("TOPLEFT", f, "TOPLEFT", 14, K.SR_Y)
	f.lbl_sr:SetTextColor(1, 0.82, 0, 1)
	f.lbl_sr:SetText(T("ui.sr_link") or "SR:")
	f.lbl_sr:Hide()

	local sr_box = CreateFrame("EditBox", nil, f)
	sr_box:SetAutoFocus(false)
	sr_box:SetMultiLine(false)
	sr_box:SetFontObject(GameFontHighlightSmall)
	sr_box:SetHeight(16)
	sr_box:SetPoint("TOPLEFT",  f, "TOPLEFT",  50, K.SR_Y)
	sr_box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, K.SR_Y)
	sr_box:SetBackdrop({
		bgFile   = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	sr_box:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
	sr_box:SetBackdropBorderColor(0.35, 0.28, 0.08, 0.95)
	sr_box:SetTextInsets(6, 4, 0, 0)
	sr_box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	sr_box:SetScript("OnEditFocusGained", function() this:HighlightText() end)
	sr_box:Hide()
	f.sr_box = sr_box

	f.lbl_rf = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_rf:SetPoint("TOPLEFT", f, "TOPLEFT", 14, K.RF_Y)
	f.lbl_rf:SetTextColor(1, 0.82, 0, 1)
	f.lbl_rf:SetText(T("group_popup.rf_label"))
	f.lbl_rf:Hide()

	local rf_box = CreateFrame("EditBox", nil, f)
	rf_box:SetAutoFocus(false)
	rf_box:SetMultiLine(false)
	rf_box:SetFontObject(GameFontHighlightSmall)
	rf_box:SetHeight(16)
	rf_box:SetPoint("TOPLEFT",  f, "TOPLEFT",  50, K.RF_Y)
	rf_box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, K.RF_Y)
	rf_box:SetBackdrop({
		bgFile   = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	rf_box:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
	rf_box:SetBackdropBorderColor(0.35, 0.28, 0.08, 0.95)
	rf_box:SetTextInsets(6, 4, 0, 0)
	rf_box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	rf_box:SetScript("OnEditFocusGained", function() this:HighlightText() end)
	rf_box:Hide()
	f.rf_box = rf_box

	f.lbl_rh = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_rh:SetPoint("TOPLEFT", f, "TOPLEFT", 14, K.RH_Y)
	f.lbl_rh:SetTextColor(1, 0.82, 0, 1)
	f.lbl_rh:SetText(T("group_popup.web_label"))
	f.lbl_rh:Hide()

	local rh_box = CreateFrame("EditBox", nil, f)
	rh_box:SetAutoFocus(false)
	rh_box:SetMultiLine(false)
	rh_box:SetFontObject(GameFontHighlightSmall)
	rh_box:SetHeight(16)
	rh_box:SetPoint("TOPLEFT",  f, "TOPLEFT",  50, K.RH_Y)
	rh_box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, K.RH_Y)
	rh_box:SetBackdrop({
		bgFile   = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	rh_box:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
	rh_box:SetBackdropBorderColor(0.35, 0.28, 0.08, 0.95)
	rh_box:SetTextInsets(6, 4, 0, 0)
	rh_box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	rh_box:SetScript("OnEditFocusGained", function() this:HighlightText() end)
	rh_box:Hide()
	f.rh_box = rh_box

	f.lbl_status = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_status:SetPoint("TOPLEFT", f, "TOPLEFT", 14, K.STATUS_Y)
	f.lbl_status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, K.STATUS_Y)
	f.lbl_status:SetJustifyH("LEFT")
	f.lbl_status:SetText("")


	f.btn_clear = gui.create_button(f, T("group_popup.clear") or "Clear plan", 90, function()
		clear_plan_local()
		selected = nil
		set_sync_state("idle", T("group_popup.status_local_only") or "Local plan changed \226\128\148 synchronization in progress...", nil, nil, nil, nil)
		M.update()
		save_remote()
	end)
	f.btn_clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)

	f.btn_auto = gui.create_button(f, T("group_popup.auto") or "Auto-fill", 95, function()
		if not event_id then return end
		local ev = m.db and m.db.events and m.db.events[event_id]
		if not ev then return end
		clear_plan_local()
		local g, s = 1, 1
		for _, su in pairs(ev.signUps or {}) do
			if su.name and is_primary_signup_status( su ) then
				get_group_plan_store()[event_id][g] = get_group_plan_store()[event_id][g] or {}
				get_group_plan_store()[event_id][g][s] = su.name
				s = s + 1
				if s > SLOTS then s = 1; g = g + 1 end
				if g > GROUPS then break end
			end
		end
		selected = nil
		set_sync_state("idle", T("group_popup.status_saving") or "Raid-Helper synchronization...", nil, nil, nil, nil)
		M.update()
		save_remote()
	end)
	f.btn_auto:SetPoint("LEFT", f.btn_clear, "RIGHT", 8, 0)

	f.btn_announce = gui.create_button(f, T("group_popup.announce") or "Announce", 95, function()
		if not event_id then return end
		local p = get_plan()
		local lines = {}
		for g = 1, GROUPS do
			local names = {}
			for s = 1, SLOTS do
				if p[g] and p[g][s] then
					table.insert(names, p[g][s])
				end
			end
			if table.getn(names) > 0 then
				table.insert(lines, string.format("Gr %d: %s", g, table.concat(names, ", ")))
			end
		end
		if table.getn(lines) == 0 then return end
		if not (m.msg and m.msg.group_thread_announce) then return end
		local title, start_time = get_event_meta()
		m.msg.group_thread_announce(event_id, get_current_user_id(), title, start_time, lines)
		set_sync_state("idle", T("group_popup.status_announce_sent") or "Announcement sent to the bot...", nil, nil, nil, nil)
	end)
	f.btn_announce:SetPoint("LEFT", f.btn_auto, "RIGHT", 8, 0)

	f.btn_assistant = gui.create_button(f, T("group_popup.thread_assistant") or "Thread assistant", 110, function()
		if not event_id or not selected or not (m.msg and m.msg.group_thread_set_assistant) then return end
		m.msg.group_thread_set_assistant(event_id, get_current_user_id(), selected)
		set_sync_state("idle", T("group_popup.status_assistant_sent") or "Thread assistant update sent to the bot...", nil, nil, nil, nil)
	end)
	f.btn_assistant:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)

	f.btn_take_lead = gui.create_button(f, T("group_popup.take_thread") or "Manage thread", 110, function()
		if not event_id or not (m.msg and m.msg.group_thread_take_lead) then return end
		local title, start_time = get_event_meta()
		-- Vérifier si selected est le manager d'un autre fil pour cet event
		local take_over_from = nil
		if selected then
			local store = m.db and m.db.group_thread_contexts
			local ctxs = store and store[event_id]
			if ctxs then
				local my_id = get_current_user_id()
				local k, ctx
				for k, ctx in pairs(ctxs) do
					if ctx and ctx.managerPlayer == selected
						and ctx.managerDiscordUserId ~= my_id
						and ctx.threadId and ctx.threadId ~= "" then
						take_over_from = selected
						break
					end
				end
			end
		end
		m.msg.group_thread_take_lead(event_id, get_current_user_id(), title, start_time, take_over_from)
		local status_key = take_over_from and "group_popup.status_thread_taken_over" or "group_popup.status_thread_taken"
		local default_msg = take_over_from and ("Taking over thread from " .. take_over_from .. "...") or "Thread control sent to the bot..."
		set_sync_state("idle", T(status_key) or default_msg, nil, nil, nil, nil)
	end)
	f.btn_take_lead:SetPoint("RIGHT", f.btn_assistant, "LEFT", -8, 0)

	f.lbl_group_thread = f:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
	f.lbl_group_thread:SetPoint("TOPLEFT", f.btn_take_lead, "BOTTOMLEFT", 2, -4)
	f.lbl_group_thread:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -372)
	f.lbl_group_thread:SetJustifyH("LEFT")
	f.lbl_group_thread:SetTextColor(0.85, 0.85, 0.85, 1)
	f.lbl_group_thread:SetText("")


	if gui.pfui_skin then gui.pfui_skin(f) end

	update_status_label()

	return f
end

update_group_thread_ui = function()
	if not popup then return end
	local ctx = get_current_context()

	-- RL + Ass (optionnel) + Fil (optionnel) sur une seule ligne à droite
	if popup.lbl_raid_info then
		if ctx then
			local txt = string.format("%s: %s", T("group_popup.raid_lead") or "Raid Lead", ctx.managerPlayer or "?")
			if ctx.assistantPlayer and ctx.assistantPlayer ~= "" then
				txt = txt .. string.format("  |  %s: %s", T("group_popup.assistant_label") or "Assistant", ctx.assistantPlayer)
			end
			if ctx.threadTitle and ctx.threadTitle ~= "" then
				txt = txt .. string.format("  |  %s: %s", T("group_popup.thread_label") or "Thread", ctx.threadTitle)
			end
			popup.lbl_raid_info:SetText(txt)
			popup.lbl_raid_info:SetTextColor(0.85, 0.85, 0.85, 1)
		else
			popup.lbl_raid_info:SetText((T("group_popup.raid_lead") or "RL") .. ": " .. (T("group_popup.raid_lead_unknown") or "not set"))
			popup.lbl_raid_info:SetTextColor(0.55, 0.55, 0.55, 1)
		end
	end

	-- lbl_group_thread masqué (info fusionnée dans lbl_raid_info)
	if popup.lbl_group_thread then
		popup.lbl_group_thread:SetText("")
	end
	local is_manager = m.db and m.db.user_settings and m.db.user_settings.has_manager_role == true
	if popup.btn_take_lead then
		if is_manager then
			popup.btn_take_lead:Show()
			popup.btn_take_lead:Enable()
		else
			popup.btn_take_lead:Hide()
		end
	end
	if popup.btn_assistant then
		if is_manager then
			popup.btn_assistant:Show()
			if selected and selected ~= "" then popup.btn_assistant:Enable() else popup.btn_assistant:Disable() end
		else
			popup.btn_assistant:Hide()
		end
	end
end

local function on_player_button_click()
	local cap = this and this.player_name
	selected = (selected == cap) and nil or cap
	M.update()
end

local function update_player_list( list_frame, entries )
	if not list_frame then return end
	for _, btn in ipairs( list_frame.buttons or {} ) do btn:Hide() end

	local sc = list_frame.content
	local pool = list_frame.buttons
	local yo = 0

	for i = 1, getn( entries ) do
		local su = entries[ i ]
		local btn = pool[ i ]
		if not btn then
			btn = CreateFrame("Button", nil, sc)
			btn:SetHeight(20)
			btn:SetWidth(K.LEFT_W - 22)
			local bbg = btn:CreateTexture(nil, "BACKGROUND")
			bbg:SetAllPoints(btn)
			bbg:SetTexture("Interface\\Buttons\\WHITE8x8")
			btn.bg = bbg
			local bfs = btn:CreateFontString(nil, "OVERLAY", "RCFontNormalSmall")
			bfs:SetPoint("LEFT", btn, "LEFT", 4, 0)
			bfs:SetWidth(K.LEFT_W - 30)
			bfs:SetJustifyH("LEFT")
			btn.name_fs = bfs
			btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			pool[ i ] = btn
		end
		btn:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -yo)
		local r, g, b = cc(su.className)
		btn.name_fs:SetText(su.name or "?")
		btn.name_fs:SetTextColor(r, g, b)
		if selected == su.name then
			btn.bg:SetVertexColor(0.25, 0.20, 0.02, 1)
		elseif math.mod(i, 2) == 0 then
			btn.bg:SetVertexColor(0.07, 0.07, 0.07, 1)
		else
			btn.bg:SetVertexColor(0.03, 0.03, 0.03, 1)
		end
		btn.player_name = su.name
		btn:SetScript("OnClick", on_player_button_click)
		btn:Show()
		yo = yo + 20
	end

	local sh = list_frame.scroll:GetHeight()
	sc:SetHeight(math.max(yo, sh))
	local mx = math.max(0, yo - sh)
	list_frame.slider:SetMinMaxValues(0, mx)
	if list_frame.slider:GetValue() > mx then list_frame.slider:SetValue(mx) end
end

local function refresh()
	if not popup or not event_id then return end
	local ev = m.db and m.db.events and m.db.events[event_id]
	if not ev then
		if popup.titlebar and popup.titlebar.title then
			popup.titlebar.title:SetText(T("group_popup.title") or "Group Plan")
		end
		update_status_label()
		return
	end

	local ev_title = ev.title or ""
	-- Ligne RF : extraire l'url et demander la data au bot
	-- Détecter si event RaidRes via srId (persistant) ou fallback description
	local sr_id = ev.srId
	local sr_url = (sr_id and sr_id ~= "") and ("https://raidres.top/res/" .. sr_id)
	              or extract_tagged_link(ev.description or "", "SR")
	local rf_url = extract_tagged_link(ev.description or "", "RF")
	-- RF url par convention depuis srId si pas dans description
	if (not rf_url or rf_url == "") and sr_id and sr_id ~= "" then
		rf_url = "https://raidres.top/api/events/" .. sr_id .. "/rollfor"
	end
	local is_raidres = sr_url and sr_url ~= ""
	if is_raidres then
		-- SR
		popup.lbl_sr:Show()
		popup.sr_box:SetText(sr_url)
		popup.sr_box:Show()
		-- RF
		popup.lbl_rf:Show()
		popup.rf_box:SetText("...")
		popup.rf_box:Show()
		if rf_url and rf_url ~= "" and m.msg and m.msg.rf_data_request then
			m.msg.rf_data_request(rf_url)
		end
		-- RH Plan
		popup.lbl_rh:Show()
		popup.rh_box:SetText("https://raid-helper.xyz/raidplan/" .. (event_id or ""))
		popup.rh_box:Show()
	else
		popup.lbl_sr:Hide()
		popup.sr_box:SetText("")
		popup.sr_box:Hide()
		popup.lbl_rf:Hide()
		popup.rf_box:SetText("")
		popup.rf_box:Hide()
		popup.lbl_rh:Hide()
		popup.rh_box:SetText("")
		popup.rh_box:Hide()
	end
	-- Titlebar = "Molten Core — Plan de raid"
	if popup.titlebar and popup.titlebar.title then
		local subtitle_fmt = T("group_popup.raid_plan_subtitle") or "%s \226\128\148 Raid Plan"
		popup.titlebar.title:SetText(string.format(subtitle_fmt, ev_title))
	end

	local placed = {}
	local p = get_plan()
	for g = 1, GROUPS do
		for s = 1, SLOTS do
			if p[g] and p[g][s] then
				placed[p[g][s]] = true
			end
		end
	end

	local name_class = {}
	for _, su in pairs(ev.signUps or {}) do
		if su.name then
			name_class[su.name] = su.className
		end
	end

	local available_primary = {}
	local available_secondary = {}
	for _, su in pairs(ev.signUps or {}) do
		if su.name and not placed[su.name] then
			if is_primary_signup_status( su ) then
				table.insert( available_primary, su )
			elseif is_secondary_signup_status( su ) then
				table.insert( available_secondary, su )
			end
		end
	end

	local function sort_available(a, b)
		if (a.className or "") ~= (b.className or "") then
			return (a.className or "") < (b.className or "")
		end
		return (a.name or "") < (b.name or "")
	end
	table.sort( available_primary, sort_available )
	table.sort( available_secondary, sort_available )

	update_player_list( popup.primary_list, available_primary )
	update_player_list( popup.secondary_list, available_secondary )

	for g = 1, GROUPS do
		for s = 1, SLOTS do
			local slot = popup.slots[g][s]
			local occ = plan_occupant(g, s)
			if occ then
				local r, gg, b = cc(name_class[occ])
				slot.name_fs:SetText(occ)
				slot.name_fs:SetTextColor(r, gg, b)
				slot.bg:SetVertexColor(selected == occ and 0.25 or 0.07, selected == occ and 0.20 or 0.05, selected == occ and 0.02 or 0.01, 1)
			else
				slot.name_fs:SetText("")
				slot.bg:SetVertexColor(selected and 0.02 or 0.04, selected and 0.07 or 0.04, selected and 0.02 or 0.04, 1)
			end
		end
	end

	update_status_label()
	update_group_thread_ui()
end

function M.show(eid)
	if not popup then popup = build() end
	M.popup = popup
	if m.close_all_popups then m.close_all_popups() end
	event_id = eid
	selected = nil
	apply_position(popup)
	popup:Show()
	send_watch_state(true)
	start_watch_timer()
	set_sync_state("reloading", T("group_popup.status_reloading") or "Reloading from Raid-Helper...", nil, nil, nil, nil)
	refresh()
	request_reload()
end

function M.hide()
	M.popup = popup
	stop_watch_timer()
	send_watch_state(false)
	if popup then
		save_position(popup)
		popup:Hide()
	end
	selected = nil
end

function M.toggle(eid)
	if popup and popup:IsVisible() and event_id == eid then
		M.hide()
	else
		M.show(eid)
	end
end

function M.update(eid)
	if popup and popup:IsVisible() then
		if eid and event_id ~= eid then
			return
		end
		refresh()
	end
end

function M.on_group_thread_result(data)
	if not data or not data.eventId then return end
	if data.eventId == event_id then
		set_sync_state("idle", data.status or "", data.success == true, nil, nil, nil)
		refresh()
	end
end

function M.on_remote_result(data)
	if not data or not data.eventId then return end
	-- Cancel the unreachable timeout since we got a response
	if reload_timer_id and m.ace_timer then
		m.ace_timer.CancelTimer(m, reload_timer_id)
		reload_timer_id = nil
	end

	local store = get_group_plan_store()
	store[data.eventId] = data.plan or {}

	if data.eventId == event_id then
		selected = nil
		local msg = data.status or ""
		local ok = data.success == true
		local rh_status = data.raidHelperStatus
		set_sync_state("idle", msg, ok, data.updatedBy or data.player, data.updatedAt, rh_status)
		refresh()
	end
end

function M.on_rf_data_result( success, rf_data, status )
	if not popup then return end
	if not popup.rf_box then return end
	if success and rf_data and rf_data ~= "" then
		popup.rf_box:SetText(rf_data)
	else
		popup.rf_box:SetText(status or T("event_manage.status_failed") or "Error")
	end
end

m.GroupPopup = M
return M
