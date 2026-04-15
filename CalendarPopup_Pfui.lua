RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.CalendarPopupPfui then return end

---@class CalendarPopup
---@field show fun()
---@field hide fun()
---@field toggle fun()
---@field is_visible fun(): boolean
---@field unselect fun()
---@field discord_response fun( success: boolean, user_id: string )
---@field update fun()

local M = {}

---@type ScrollDropdown
local scroll_drop = LibStub:GetLibrary( "LibScrollDrop-1.3", true )

function M.new()
	local popup
	local pending_ui_theme
	local pending_locale_flag
	local pending_time_format
	local selected_day
	local selected_event_key
	local events
	local events_by_day = {}
	local day_cells = {}
	local detail_items = {}
	local local_events_requested = false
	local current_month_time
	local gui = m.GuiElements

	local days_per_week = 7
	local weeks = 6
	local max_cell_events = 3
	-- Palette dorée pfui — bords plus nets, contraste amélioré
	local PFUI_CELL_BORDER              = { r = 0.50, g = 0.38, b = 0.12, a = 1.00 }
	local PFUI_CELL_BORDER_DIM          = { r = 0.22, g = 0.16, b = 0.06, a = 0.72 }
	local PFUI_CELL_BORDER_TODAY        = { r = 1.00, g = 0.80, b = 0.18, a = 1.00 }
	local PFUI_CELL_BORDER_SELECTED     = { r = 0.36, g = 0.62, b = 1.00, a = 1.00 }
	local PFUI_CELL_INNER_HIGHLIGHT     = { r = 1.00, g = 0.88, b = 0.42, a = 0.32 }
	local PFUI_CELL_INNER_HIGHLIGHT_DIM = { r = 0.42, g = 0.32, b = 0.10, a = 0.14 }
	local PFUI_CELL_INNER_HIGHLIGHT_TODAY = { r = 1.00, g = 0.94, b = 0.55, a = 0.50 }
	local PFUI_CELL_INNER_SHADOW        = { r = 0.06, g = 0.04, b = 0.01, a = 0.95 }
	local PFUI_CELL_INNER_SHADOW_DIM    = { r = 0.03, g = 0.02, b = 0.01, a = 0.80 }
	local PFUI_CELL_INNER_SHADOW_TODAY  = { r = 0.12, g = 0.08, b = 0.01, a = 0.95 }
	local PFUI_GOLD = { r = 1.00, g = 0.82, b = 0.20 }  -- couleur dorée globale

	local function set_shown( frame, visible )
		if not frame then
			return
		end
		if visible then
			frame:Show()
		else
			frame:Hide()
		end
	end

	local function normalize_day( timestamp )
		local info = date( "*t", timestamp )
		info.hour = 12
		info.min = 0
		info.sec = 0
		return time( info )
	end

	local function save_position( self )
		local point, _, relative_point, x, y = self:GetPoint()

		m.db.popup_calendar.position = {
			point = point,
			relative_point = relative_point,
			x = x,
			y = y
		}
	end

	local function get_today()
		return normalize_day( time( date( "*t" ) ) )
	end

	local function get_day_key( timestamp )
		return tostring( normalize_day( timestamp ) )
	end

	local function truncate_cell_label( text, max_len )
		if not text then
			return ""
		end
		if string.len( text ) <= max_len then
			return text
		end
		return string.sub( text, 1, max_len - 3 ) .. "..."
	end

	local function get_month_info( timestamp )
		local info = date( "*t", timestamp )
		info.day = 1
		info.hour = 12
		info.min = 0
		info.sec = 0
		return info, time( info )
	end

	local function shift_month( timestamp, amount )
		local info = date( "*t", timestamp )
		local month = info.month + amount
		local year = info.year

		while month < 1 do
			month = month + 12
			year = year - 1
		end
		while month > 12 do
			month = month - 12
			year = year + 1
		end

		return time( {
			year = year,
			month = month,
			day = 1,
			hour = 12,
			min = 0,
			sec = 0
		} )
	end

	local function get_month_grid_start( timestamp )
		local month_info, month_time = get_month_info( timestamp )
		local weekday = tonumber( date( "%w", month_time ) ) or 0
		local monday_offset = mod( weekday + 6, 7 )
		month_info.day = 1 - monday_offset
		return normalize_day( time( month_info ) )
	end

	local function add_days_safe( timestamp, day_offset )
		local info = date( "*t", timestamp )
		info.day = info.day + day_offset
		info.hour = 12
		info.min = 0
		info.sec = 0
		return normalize_day( time( info ) )
	end

	local function build_event_cache()
		events_by_day = {}

		if not events then
			return
		end

		for _, item in ipairs( events ) do
			local event_data
			if item.source == "local" then
				event_data = m.db.local_events and m.db.local_events[ item.key ]
			else
				event_data = m.db.events[ item.key ]
			end
			if event_data and event_data.startTime then
				local day_key = get_day_key( event_data.startTime )
				events_by_day[ day_key ] = events_by_day[ day_key ] or {}
				table.insert( events_by_day[ day_key ], item )
			end
		end
	end

	local function refresh_data( force )
		if not events or force then
			events = {}
			for key, value in pairs( m.db.events ) do
				table.insert( events, { key = key, value = value.startTime, source = "raidhelper" } )
			end
			-- Inclure les evenements locaux (in-game)
			for key, value in pairs( m.db.local_events or {} ) do
				table.insert( events, { key = key, value = value.startTime, source = "local" } )
			end

			table.sort( events, function( a, b )
				return a.value < b.value
			end )

			build_event_cache()

			if getn( events ) == 0 then
				m.msg.request_events()
			end
		end
	end

	local function get_selected_day_events()
		if not selected_day then
			return nil
		end
		return events_by_day[ tostring( selected_day ) ] or {}
	end

	local function request_local_events_once( force )
		if not m.msg or not m.msg.request_local_events then
			return
		end
		if force then
			local_events_requested = false
		end
		if not local_events_requested then
			local_events_requested = true
			m.msg.request_local_events()
		end
	end

	local function ensure_selected_day()
		if selected_day and events_by_day[ tostring( selected_day ) ] then
			return
		end

		local today = get_today()
		if events_by_day[ tostring( today ) ] then
			selected_day = today
			return
		end

		if events and events[ 1 ] then
			selected_day = normalize_day( events[ 1 ].value )
			return
		end

		selected_day = get_today()
	end

	local function center_checkbox_with_text( parent, checkbox, anchor_y )
		if not parent or not checkbox then
			return
		end

		local label = getglobal( checkbox:GetName() .. "Text" )
		if not label then
			return
		end

		label:ClearAllPoints()
		label:SetPoint( "LEFT", checkbox, "RIGHT", 2, 1 )
		label:SetJustifyH( "LEFT" )

		local spacing = 2
		local total_width = checkbox:GetWidth() + spacing + label:GetStringWidth()

		checkbox:ClearAllPoints()
		checkbox:SetPoint( "TOPLEFT", parent, "TOP", -(total_width / 2), anchor_y )
	end

	local function refresh_settings_labels()
		if not popup or not popup.settings then return end
		popup.btn_today:SetText( m.L( "actions.today" ) )
		popup.detail_panel.header:SetText( m.L( "ui.month_events" ) )
		popup.detail_panel.empty:SetText( m.L( "ui.no_events_month" ) )
		popup.empty_state:SetText( m.L( "ui.no_events_loaded" ) )
		popup.settings.label_timeformat:SetText( m.L( "ui.time_format" ) )
		popup.settings.label_locale:SetText( m.L( "ui.language" ) )
		if popup.settings.lbl_theme then popup.settings.lbl_theme:SetText( m.L( "ui.ui_theme" ) ) end
		popup.settings.btn_save:SetText( m.L( "actions.save" ) )
		popup.settings.btn_welcome:SetText( m.L( "actions.welcome_popup" ) )
		popup.settings.btn_disconnect:SetText( m.L( "actions.disconnect" ) )
		if popup.settings.show_raid_resets then
			getglobal( popup.settings.show_raid_resets:GetName() .. "Text" ):SetText( m.L( "ui.show_raid_resets" ) )
		end
		if popup.settings.lbl_utc_offset then
			popup.settings.lbl_utc_offset:SetText( m.L( "ui.wow_utc_offset" ) or "WoW UTC offset (s)" )
		end
		popup.settings.time_format:SetItems( {
			{ value = "24", text = m.L( "options.time_format_24" ) },
			{ value = "12", text = m.L( "options.time_format_12" ) }
		} )
		popup.settings.locale_flag:SetItems( (m.get_available_locales and m.get_available_locales()) or {
			{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
			{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Fran\195\167ais" }
		} )
	end

	local function on_save_settings()
		if not popup then
			return
		end

		local selected_locale_flag = pending_locale_flag or (popup.settings.locale_flag and popup.settings.locale_flag.selected) or m.db.user_settings.locale_flag or "enUS"
		local selected_time_format = pending_time_format or (popup.settings.time_format and popup.settings.time_format.selected) or m.db.user_settings.time_format
		local theme_to_apply = pending_ui_theme or (popup.settings.dd_theme and popup.settings.dd_theme.selected) or m.db.user_settings.ui_theme or "Original"
		local previous_theme = m.db.user_settings.ui_theme or "Original"
		local previous_locale_flag = m.db.user_settings.locale_flag or "enUS"
		local previous_time_format = m.db.user_settings.time_format
		local locale_changed = selected_locale_flag ~= previous_locale_flag
		local tf_manually_changed = selected_time_format ~= previous_time_format
		local selected_reset_icons = (popup.settings.show_raid_resets and popup.settings.show_raid_resets:GetChecked() == 1) and 1 or 0
		if popup.settings.eb_utc_offset then
			local off = tonumber( popup.settings.eb_utc_offset:GetText() )
			m.db.user_settings.wow_utc_offset = off or 0
		end

		-- use_character_name est force a 1 (case a cocher supprimee)
		m.db.user_settings.use_character_name = 1
		m.db.user_settings.show_raid_reset_icons = selected_reset_icons
		m.db.user_settings.time_format = selected_time_format
		m.db.user_settings.locale_flag = selected_locale_flag
		m.db.user_settings.ui_theme = theme_to_apply
		m.time_format = m.db.user_settings.time_format == "24" and "%H:%M" or "%I:%M %p"
		m.set_locale( m.db.user_settings.locale_flag )

		if locale_changed and not tf_manually_changed then
			local auto_tf = (m.db.user_settings.locale_flag == "frFR") and "24" or "12"
			m.db.user_settings.time_format = auto_tf
			m.time_format = auto_tf == "24" and "%H:%M" or "%I:%M %p"
			popup.settings.time_format:SetSelected( auto_tf )
		end

		refresh_settings_labels()

		popup.settings.time_format:SetSelected( m.db.user_settings.time_format )
		popup.settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
		pending_time_format = nil
		pending_locale_flag = nil
		popup.settings:Hide()
		popup.btn_settings.active = false

		if m.pfui_skin_enabled then
			popup.btn_settings:SetBackdropBorderColor( 0.2, 0.2, 0.2, 1 )
		end

		if theme_to_apply ~= previous_theme then
			if m.calendar_popup then
				m.calendar_popup.hide()
			end

			m.calendar_popup_instances = m.calendar_popup_instances or {}
			if not m.calendar_popup_instances[ theme_to_apply ] then
				local mod = m[ "CalendarPopup" .. theme_to_apply ] or m.CalendarPopupOriginal
				m.calendar_popup_instances[ theme_to_apply ] = mod.new()
			end

			m.calendar_popup = m.calendar_popup_instances[ theme_to_apply ]
			if m.calendar_popup.sync_settings then
				m.calendar_popup.sync_settings()
			end
			m.calendar_popup.show()
			return
		end

		if m.event_popup and m.event_popup.update then
			m.event_popup.update()
		end
		if m.sr_popup and m.sr_popup.update then
			m.sr_popup.update()
		end

		popup.refresh()
	end

	local function set_selected_day( day_timestamp, event_key )
		selected_day = normalize_day( day_timestamp )
		selected_event_key = event_key

		local _, month_time = get_month_info( selected_day )
		current_month_time = month_time
	end

	local function get_current_month_events()
		local month_events = {}
		local month_info, month_time = get_month_info( current_month_time or selected_day or get_today() )

		if not events then
			return month_events
		end

		for _, item in ipairs( events ) do
			local ev
			if item.source == "local" then
				ev = m.db.local_events and m.db.local_events[ item.key ]
			else
				ev = m.db.events[ item.key ]
			end
			if ev and ev.startTime then
				local event_info = date( "*t", m.ts( ev.startTime ) )
				if event_info.month == month_info.month and event_info.year == month_info.year then
					table.insert( month_events, item )
				end
			end
		end

		return month_events, month_time
	end

	local function update_day_detail_items()
		local month_events, month_time = get_current_month_events()
		local panel = popup.detail_panel

		panel.empty:Hide()
		panel.subheader:SetText( m.format_local_date( month_time, "month_year" ) )
		panel.header_count:SetText( m.L( getn( month_events ) == 1 and "ui.event_count_one" or "ui.event_count_many", { count = getn( month_events ) } ) )

		for i = 1, getn( detail_items ) do
			detail_items[ i ]:Hide()
		end

		if getn( month_events ) == 0 then
			panel.empty:Show()
			return
		end

		for i, item in ipairs( month_events ) do
			local is_local = (item.source == "local")
			local event
			if is_local then
				event = m.db.local_events and m.db.local_events[ item.key ]
			else
				event = m.db.events[ item.key ]
			end
			if not event then break end
			local frame = detail_items[ i ]

			if not frame then
				frame = CreateFrame( "Button", nil, panel )
				frame:SetWidth( 228 )
				frame:SetHeight( 54 )
				frame:SetHighlightTexture( "Interface\\QuestFrame\\UI-QuestTitleHighlight" )

				frame.bg = frame:CreateTexture( nil, "BACKGROUND" )
				frame.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
				frame.bg:SetAllPoints( frame )
				frame.bg:SetVertexColor( 0.07, 0.07, 0.10, 0.97 )

				-- Séparateur bas de l'item
				frame.divider = frame:CreateTexture( nil, "ARTWORK" )
				frame.divider:SetTexture( "Interface\\Buttons\\WHITE8x8" )
				frame.divider:SetPoint( "BottomLeft", frame, "BottomLeft", 5, 0 )
				frame.divider:SetPoint( "BottomRight", frame, "BottomRight", -5, 0 )
				frame.divider:SetHeight( 1 )
				frame.divider:SetVertexColor( 0.26, 0.22, 0.10, 0.45 )

				-- Barre de couleur latérale (5px) + fade (1px)
				frame.border = frame:CreateTexture( nil, "ARTWORK" )
				frame.border:SetTexture( "Interface\\Buttons\\WHITE8x8" )
				frame.border:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )
				frame.border:SetPoint( "BottomLeft", frame, "BottomLeft", 0, 0 )
				frame.border:SetWidth( 5 )

				frame.border_fade = frame:CreateTexture( nil, "ARTWORK" )
				frame.border_fade:SetTexture( "Interface\\Buttons\\WHITE8x8" )
				frame.border_fade:SetPoint( "TopLeft", frame, "TopLeft", 5, 0 )
				frame.border_fade:SetPoint( "BottomLeft", frame, "BottomLeft", 5, 0 )
				frame.border_fade:SetWidth( 1 )

				frame.time = frame:CreateFontString( nil, "ARTWORK", "RCFontHighlightSmall" )
				frame.time:SetPoint( "TopLeft", frame, "TopLeft", 12, -5 )
				frame.time:SetJustifyH( "Left" )

				frame.title = frame:CreateFontString( nil, "ARTWORK", "RCFontNormalBold" )
				frame.title:SetPoint( "TopLeft", frame.time, "BottomLeft", 0, -2 )
				frame.title:SetPoint( "Right", frame, "Right", -8, 0 )
				frame.title:SetJustifyH( "Left" )

				frame.meta = frame:CreateFontString( nil, "ARTWORK", "RCFontNormalSmall" )
				frame.meta:SetPoint( "TopLeft", frame.title, "BottomLeft", 0, -2 )
				frame.meta:SetPoint( "Right", frame, "Right", -8, 0 )
				frame.meta:SetJustifyH( "Left" )
				frame.meta:SetTextColor( 0.66, 0.68, 0.78 )

				frame.selected = frame:CreateTexture( nil, "ARTWORK" )
				frame.selected:SetTexture( "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" )
				frame.selected:SetAllPoints( frame )
				frame.selected:SetVertexColor( 0.18, 0.40, 0.90, 0.30 )
				frame.selected:Hide()

				frame:SetScript( "OnClick", function()
					if not frame.event_key then
						return
					end

					if frame.event_source == "local" then
						local local_event = m.db.local_events and m.db.local_events[ frame.event_key ]
						selected_event_key = frame.event_key
						if local_event and local_event.startTime then
							selected_day = normalize_day( local_event.startTime )
						end
						if m.LocalEventPopup then
							m.LocalEventPopup.show( frame.event_key )
						end
						popup.refresh()
						return
					end

					if m.api.IsShiftKeyDown() then
						local event_data = m.db.events[ frame.event_key ]
						if event_data then
							local raid_link = "|cffffffff|Hraidcal:event:" .. frame.event_key .. "|h[" .. event_data.title .. "]|h|r"
							m.api.ChatFrameEditBox:Insert( raid_link )
						end
						return
					end

					local event_data = m.db.events[ frame.event_key ]
					selected_event_key = frame.event_key
					if event_data and event_data.startTime then
						selected_day = normalize_day( event_data.startTime )
					end
					if m.event_popup then
						m.event_popup.show( frame.event_key )
					end
					popup.refresh()
				end )

				table.insert( detail_items, frame )
			end

			local color
			if is_local then
				color = { r=0.6, g=0.4, b=1, a=1 }
			else
				local _c = m.get_event_color( event )
				color = { r=_c[1], g=_c[2], b=_c[3], a=1 }
			end

			frame.border:SetVertexColor( color.r, color.g, color.b, color.a )
			if frame.border_fade then
				frame.border_fade:SetVertexColor( color.r, color.g, color.b, 0.25 )
			end
			frame:ClearAllPoints()

			if i == 1 then
				frame:SetPoint( "TopLeft", panel.header_count, "BottomLeft", 0, -12 )
			else
				frame:SetPoint( "TopLeft", detail_items[ i - 1 ], "BottomLeft", 0, -4 )
			end

			frame.time:SetText( date( "%d/%m ", m.ts( event.startTime ) ) .. date( m.time_format, m.ts( event.startTime ) ) )
			frame.title:SetText( event.title )

			local signup_text = ""
			if not is_local then
				if event.signUps then
					local count = 0
					for _, signup in ipairs( event.signUps ) do
						if signup.className ~= "Absence" then count = count + 1 end
					end
					signup_text = m.L( "ui.signups", { count = count } )
				elseif event.signUpCount then
					signup_text = m.L( "ui.signups", { count = event.signUpCount } )
				else
					signup_text = m.L( "ui.no_signup_data" )
				end
			end

			frame.meta:SetText( signup_text )
			frame.event_key  = item.key
			frame.event_source = item.source

			if selected_event_key and selected_event_key == item.key then
				frame.selected:Show()
			else
				frame.selected:Hide()
			end

			frame:Show()
		end
	end

	local hide_reset_icon_slots, ensure_reset_icon_slot, render_reset_icons

	local function refresh_day_cells()
		local month_info, month_time = get_month_info( current_month_time or get_today() )
		local grid_start = get_month_grid_start( month_time )
		local today = get_today()

		popup.month_label:SetText( m.format_local_date( month_time, "month_year" ) )

		for i = 1, getn( day_cells ) do
			local cell = day_cells[ i ]
			local day_time = add_days_safe( grid_start, i - 1 )
			local day_info = date( "*t", day_time )
			local day_events = events_by_day[ tostring( day_time ) ] or {}
			local is_current_month = day_info.month == month_info.month and day_info.year == month_info.year
			local is_today = day_time == today
			local is_selected = selected_day and selected_day == day_time

			cell.day_time = day_time
			cell.raid_resets = m.get_raid_resets_for_day( day_time )
			cell.day_number:SetText( tostring( day_info.day ) )
			local column = mod( i - 1, days_per_week ) + 1
			if is_current_month then
				if column == 6 then
					cell.day_number:SetTextColor( 1.00, 0.52, 0.10 )   -- Samedi orange
				elseif column == 7 then
					cell.day_number:SetTextColor( 1.00, 0.22, 0.22 )   -- Dimanche rouge
				else
					cell.day_number:SetTextColor( 1.00, 0.84, 0.10 )   -- Semaine doré
				end
			else
				cell.day_number:SetTextColor( 0.36, 0.36, 0.40 )      -- Hors mois gris
			end
			if is_today then
				cell.bg:SetVertexColor( 0.10, 0.09, 0.04, 1 )
			elseif is_selected then
				cell.bg:SetVertexColor( 0.06, 0.07, 0.14, 1 )
			elseif is_current_month then
				cell.bg:SetVertexColor( 0.07, 0.07, 0.09, 0.97 )
			else
				cell.bg:SetVertexColor( 0.025, 0.025, 0.035, 0.97 )
			end
			local border = PFUI_CELL_BORDER
			local inner_highlight = PFUI_CELL_INNER_HIGHLIGHT
			local inner_shadow = PFUI_CELL_INNER_SHADOW
			if is_today then
				border = PFUI_CELL_BORDER_TODAY
				inner_highlight = PFUI_CELL_INNER_HIGHLIGHT_TODAY
				inner_shadow = PFUI_CELL_INNER_SHADOW_TODAY
			elseif not is_current_month then
				border = PFUI_CELL_BORDER_DIM
				inner_highlight = PFUI_CELL_INNER_HIGHLIGHT_DIM
				inner_shadow = PFUI_CELL_INNER_SHADOW_DIM
			end
			cell.border_top:SetVertexColor( border.r, border.g, border.b, border.a )
			cell.border_left:SetVertexColor( border.r, border.g, border.b, border.a )
			cell.border_right:SetVertexColor( border.r, border.g, border.b, border.a )
			cell.border_bottom:SetVertexColor( border.r, border.g, border.b, border.a )
			cell.inner_top:SetVertexColor( inner_highlight.r, inner_highlight.g, inner_highlight.b, inner_highlight.a )
			cell.inner_left:SetVertexColor( inner_highlight.r, inner_highlight.g, inner_highlight.b, inner_highlight.a )
			cell.inner_right:SetVertexColor( inner_shadow.r, inner_shadow.g, inner_shadow.b, inner_shadow.a )
			cell.inner_bottom:SetVertexColor( inner_shadow.r, inner_shadow.g, inner_shadow.b, inner_shadow.a )

			if (not m.should_show_raid_reset_icons or m.should_show_raid_reset_icons()) and cell.raid_resets and getn( cell.raid_resets ) > 0 then
				local visuals = m.get_raid_reset_day_visuals and m.get_raid_reset_day_visuals( cell.raid_resets ) or nil
				render_reset_icons( cell, visuals, is_current_month )
			else
				hide_reset_icon_slots( cell )
			end
			cell.reset_bg:Hide()
			cell.reset_dim:Hide()
			cell.reset_ribbon:Hide()
			cell.reset_border_top:Hide()
			cell.reset_border_left:Hide()
			set_shown( cell.today_glow_top, is_today )
			set_shown( cell.today_glow_left, is_today )
			set_shown( cell.selected_top, is_selected )
			set_shown( cell.selected_left, is_selected )
			set_shown( cell.selected_right, is_selected )
			set_shown( cell.selected_bottom, is_selected )
			if is_selected then
				local b = PFUI_CELL_BORDER_SELECTED
				cell.selected_top:SetVertexColor( b.r, b.g, b.b, 0.95 )
				cell.selected_bottom:SetVertexColor( b.r, b.g, b.b, 0.85 )
				cell.selected_left:SetVertexColor( b.r, b.g, b.b, 0.90 )
				cell.selected_right:SetVertexColor( b.r * 0.4, b.g * 0.4, b.b * 0.4, 0.60 )
			end

			cell.event_count:SetText( "" )

			for j = 1, max_cell_events do
				cell.events[ j ]:Hide()
			end
			cell.more_label:Hide()

			for j = 1, math.min( getn( day_events ), max_cell_events ) do
				local item = day_events[ j ]
				local is_local = (item.source == "local")
				local event_data
				if is_local then
					event_data = m.db.local_events and m.db.local_events[ item.key ]
				else
					event_data = m.db.events[ item.key ]
				end
				local chip = cell.events[ j ]
				local icon_offset = (cell.reset_icon_rows and cell.reset_icon_rows > 0) and (cell.reset_icon_rows * 15) or 0
				chip:ClearAllPoints()
				chip:SetPoint( "TopLeft", cell, "TopLeft", 4, -(22 + icon_offset + ((j - 1) * 11)) )
				if event_data then
					local color
					-- Couleur violette pour les events locaux, sinon cache RGB de l'event
					if is_local then
						color = { r=0.6, g=0.4, b=1, a=1 }
					else
						local _c = m.get_event_color( event_data )
						color = { r=_c[1], g=_c[2], b=_c[3], a=1 }
					end
					local title = truncate_cell_label( event_data.title or "", 11 )
					local label = date( m.time_format, m.ts( event_data.startTime ) ) .. " " .. title
					chip.event_key   = item.key
					chip.event_source = item.source
					chip.color_bar:SetVertexColor( color.r, color.g, color.b, color.a )
					if chip.color_glow then
						chip.color_glow:SetVertexColor( color.r, color.g, color.b, 0.28 )
					end
					chip.text:SetText( label )
					chip:Show()
				end
			end

			if getn( day_events ) > max_cell_events then
				local icon_offset = (cell.reset_icon_rows and cell.reset_icon_rows > 0) and (cell.reset_icon_rows * 15) or 0
				cell.more_label:ClearAllPoints()
				cell.more_label:SetPoint( "TopRight", cell, "TopRight", -5, -(18 + icon_offset) )
				cell.more_label:SetText( "+" .. tostring( getn( day_events ) - max_cell_events ) )
				cell.more_label:Show()
			end
		end
	end

	local function refresh_calendar()
		if popup.online_indicator and popup.online_indicator.update then
			popup.online_indicator.update()
		end

		if m.debug_enabled then
			popup.btn_refresh:Enable()
		end

		if popup.week_day_labels then
			for i = 1, days_per_week do
				popup.week_day_labels[ i ]:SetText( m.get_day_name( mod( i, 7 ) + 1, true ) )
				if i == 6 then
					popup.week_day_labels[ i ]:SetTextColor( 1, 0.55, 0 )
				elseif i == 7 then
					popup.week_day_labels[ i ]:SetTextColor( 1, 0.2, 0.2 )
				else
					popup.week_day_labels[ i ]:SetTextColor( 0.92, 0.82, 0.35 )
				end
			end
		end

		popup.settings.time_format:SetSelected( (popup.settings:IsVisible() and pending_time_format) or m.db.user_settings.time_format )
		popup.settings.locale_flag:SetSelected( (popup.settings:IsVisible() and pending_locale_flag) or (m.db.user_settings.locale_flag or "enUS") )
		if popup.settings.show_raid_resets then
			popup.settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 and 1 or nil )
		end


		refresh_data()
		if getn( m.db.local_events or {} ) == 0 then
			request_local_events_once( false )
		end
		ensure_selected_day()
		refresh_day_cells()
		update_day_detail_items()
		set_shown( popup.empty_state, not events or getn( events ) == 0 )
	end

	local function create_chip( parent, width )
		local chip = CreateFrame( "Button", nil, parent )
		chip:SetWidth( width )
		chip:SetHeight( 13 )
		chip:SetHighlightTexture( "Interface\\QuestFrame\\UI-QuestTitleHighlight" )

		chip.bg = chip:CreateTexture( nil, "BACKGROUND" )
		chip.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		chip.bg:SetAllPoints( chip )
		chip.bg:SetVertexColor( 0.06, 0.06, 0.08, 0.98 )

		-- Barre de couleur latérale (3px) + highlight interne (1px)
		chip.color_bar = chip:CreateTexture( nil, "ARTWORK" )
		chip.color_bar:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		chip.color_bar:SetPoint( "TopLeft", chip, "TopLeft", 0, 0 )
		chip.color_bar:SetPoint( "BottomLeft", chip, "BottomLeft", 0, 0 )
		chip.color_bar:SetWidth( 3 )

		chip.color_glow = chip:CreateTexture( nil, "ARTWORK" )
		chip.color_glow:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		chip.color_glow:SetPoint( "TopLeft", chip, "TopLeft", 3, 0 )
		chip.color_glow:SetPoint( "BottomLeft", chip, "BottomLeft", 3, 0 )
		chip.color_glow:SetWidth( 1 )

		chip.text = chip:CreateFontString( nil, "ARTWORK", "RCFontNormalSmall" )
		chip.text:SetPoint( "TopLeft", chip, "TopLeft", 6, -1 )
		chip.text:SetPoint( "Right", chip, "Right", -2, 0 )
		chip.text:SetJustifyH( "Left" )
		chip.text:SetTextColor( 0.96, 0.96, 0.96 )

		chip:SetScript( "OnClick", function()
			if not chip.event_key then
				return
			end

			if chip.event_source == "local" then
				local local_event = m.db.local_events and m.db.local_events[ chip.event_key ]
				selected_event_key = chip.event_key
				if local_event and local_event.startTime then
					selected_day = normalize_day( local_event.startTime )
				end
				if m.LocalEventPopup then
					m.LocalEventPopup.show( chip.event_key )
				end
				popup.refresh()
				return
			end

			if m.api.IsShiftKeyDown() then
				local event_data = m.db.events[ chip.event_key ]
				if event_data then
					local raid_link = "|cffffffff|Hraidcal:event:" .. chip.event_key .. "|h[" .. event_data.title .. "]|h|r"
					m.api.ChatFrameEditBox:Insert( raid_link )
				end
				return
			end

			local event_data = m.db.events[ chip.event_key ]
			selected_event_key = chip.event_key
			if event_data and event_data.startTime then
				selected_day = normalize_day( event_data.startTime )
			end
			if m.event_popup then
				m.event_popup.show( chip.event_key )
			end
			popup.refresh()
		end )

		return chip
	end

	local function create_day_cell( parent, width, height )
		local cell = CreateFrame( "Button", nil, parent )
		cell:SetWidth( width )
		cell:SetHeight( height )
		cell:SetHighlightTexture( "Interface\\QuestFrame\\UI-QuestTitleHighlight" )

		cell.bg = cell:CreateTexture( nil, "BACKGROUND" )
		cell.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.bg:SetAllPoints( cell )

		cell.border_top = cell:CreateTexture( nil, "ARTWORK" )
		cell.border_top:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.border_top:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
		cell.border_top:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
		cell.border_top:SetHeight( 1 )
		cell.border_top:SetVertexColor( PFUI_CELL_BORDER.r, PFUI_CELL_BORDER.g, PFUI_CELL_BORDER.b, PFUI_CELL_BORDER.a )

		cell.border_left = cell:CreateTexture( nil, "ARTWORK" )
		cell.border_left:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.border_left:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
		cell.border_left:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
		cell.border_left:SetWidth( 1 )
		cell.border_left:SetVertexColor( PFUI_CELL_BORDER.r, PFUI_CELL_BORDER.g, PFUI_CELL_BORDER.b, PFUI_CELL_BORDER.a )

		cell.border_right = cell:CreateTexture( nil, "ARTWORK" )
		cell.border_right:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.border_right:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
		cell.border_right:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
		cell.border_right:SetWidth( 1 )
		cell.border_right:SetVertexColor( PFUI_CELL_BORDER.r, PFUI_CELL_BORDER.g, PFUI_CELL_BORDER.b, PFUI_CELL_BORDER.a )

		cell.border_bottom = cell:CreateTexture( nil, "ARTWORK" )
		cell.border_bottom:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.border_bottom:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
		cell.border_bottom:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
		cell.border_bottom:SetHeight( 1 )
		cell.border_bottom:SetVertexColor( PFUI_CELL_BORDER.r, PFUI_CELL_BORDER.g, PFUI_CELL_BORDER.b, PFUI_CELL_BORDER.a )

		cell.inner_top = cell:CreateTexture( nil, "ARTWORK" )
		cell.inner_top:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.inner_top:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.inner_top:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.inner_top:SetHeight( 1 )
		cell.inner_top:SetVertexColor( PFUI_CELL_INNER_HIGHLIGHT.r, PFUI_CELL_INNER_HIGHLIGHT.g, PFUI_CELL_INNER_HIGHLIGHT.b, PFUI_CELL_INNER_HIGHLIGHT.a )

		cell.inner_left = cell:CreateTexture( nil, "ARTWORK" )
		cell.inner_left:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.inner_left:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.inner_left:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.inner_left:SetWidth( 1 )
		cell.inner_left:SetVertexColor( PFUI_CELL_INNER_HIGHLIGHT.r, PFUI_CELL_INNER_HIGHLIGHT.g, PFUI_CELL_INNER_HIGHLIGHT.b, PFUI_CELL_INNER_HIGHLIGHT.a )

		cell.inner_right = cell:CreateTexture( nil, "ARTWORK" )
		cell.inner_right:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.inner_right:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.inner_right:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.inner_right:SetWidth( 1 )
		cell.inner_right:SetVertexColor( PFUI_CELL_INNER_SHADOW.r, PFUI_CELL_INNER_SHADOW.g, PFUI_CELL_INNER_SHADOW.b, PFUI_CELL_INNER_SHADOW.a )

		cell.inner_bottom = cell:CreateTexture( nil, "ARTWORK" )
		cell.inner_bottom:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.inner_bottom:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.inner_bottom:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.inner_bottom:SetHeight( 1 )
		cell.inner_bottom:SetVertexColor( PFUI_CELL_INNER_SHADOW.r, PFUI_CELL_INNER_SHADOW.g, PFUI_CELL_INNER_SHADOW.b, PFUI_CELL_INNER_SHADOW.a )

		cell.day_number = cell:CreateFontString( nil, "ARTWORK", "RCFontHighlight" )
		cell.day_number:SetPoint( "TopLeft", cell, "TopLeft", 5, -4 )
		cell.day_number:SetJustifyH( "Left" )

		cell.event_count = cell:CreateFontString( nil, "ARTWORK", "RCFontNormalSmall" )
		cell.event_count:SetPoint( "TopRight", cell, "TopRight", -5, -5 )
		cell.event_count:SetJustifyH( "Right" )
		cell.event_count:SetTextColor( 0.68, 0.72, 0.82 )

		cell.today_glow_top = cell:CreateTexture( nil, "OVERLAY" )
		cell.today_glow_top:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.today_glow_top:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.today_glow_top:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.today_glow_top:SetHeight( 2 )
		cell.today_glow_top:SetVertexColor( 1.00, 0.86, 0.20, 0.95 )
		cell.today_glow_top:Hide()

		cell.today_glow_left = cell:CreateTexture( nil, "OVERLAY" )
		cell.today_glow_left:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.today_glow_left:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.today_glow_left:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.today_glow_left:SetWidth( 2 )
		cell.today_glow_left:SetVertexColor( 1.00, 0.86, 0.20, 0.75 )
		cell.today_glow_left:Hide()

		cell.selected_top = cell:CreateTexture( nil, "OVERLAY" )
		cell.selected_top:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.selected_top:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.selected_top:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.selected_top:SetHeight( 1 )
		cell.selected_top:SetVertexColor( 0.95, 0.78, 0.22, 0.95 )
		cell.selected_top:Hide()

		cell.selected_left = cell:CreateTexture( nil, "OVERLAY" )
		cell.selected_left:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.selected_left:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.selected_left:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.selected_left:SetWidth( 1 )
		cell.selected_left:SetVertexColor( 0.95, 0.78, 0.22, 0.78 )
		cell.selected_left:Hide()

		cell.selected_right = cell:CreateTexture( nil, "OVERLAY" )
		cell.selected_right:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.selected_right:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.selected_right:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.selected_right:SetWidth( 1 )
		cell.selected_right:SetVertexColor( 0.45, 0.28, 0.05, 0.55 )
		cell.selected_right:Hide()

		cell.selected_bottom = cell:CreateTexture( nil, "OVERLAY" )
		cell.selected_bottom:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.selected_bottom:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.selected_bottom:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.selected_bottom:SetHeight( 1 )
		cell.selected_bottom:SetVertexColor( 0.45, 0.28, 0.05, 0.7 )
		cell.selected_bottom:Hide()

		cell.events = {}
		for i = 1, max_cell_events do
			local chip = create_chip( cell, width - 8 )
			chip:SetPoint( "TopLeft", cell, "TopLeft", 4, -22 - ((i - 1) * 11) )
			table.insert( cell.events, chip )
		end

		cell.more_label = cell:CreateFontString( nil, "ARTWORK", "RCFontNormalSmall" )
		cell.more_label:SetPoint( "TopRight", cell, "TopRight", -5, -18 )
		cell.more_label:SetJustifyH( "Right" )
		cell.more_label:SetTextColor( 0.96, 0.76, 0.20 )
		cell.more_label:Hide()

		cell.reset_bg = cell:CreateTexture( nil, "ARTWORK" )
		cell.reset_bg:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.reset_bg:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.reset_bg:SetTexCoord( 0.08, 0.92, 0.08, 0.92 )
		cell.reset_bg:Hide()

		cell.reset_dim = cell:CreateTexture( nil, "ARTWORK" )
		cell.reset_dim:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.reset_dim:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.reset_dim:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
		cell.reset_dim:SetVertexColor( 0, 0, 0, 0.5 )
		cell.reset_dim:Hide()

		cell.reset_ribbon = cell:CreateTexture( nil, "ARTWORK" )
		cell.reset_ribbon:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.reset_ribbon:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.reset_ribbon:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.reset_ribbon:SetHeight( 5 )
		cell.reset_ribbon:Hide()

		cell.reset_border_top = cell:CreateTexture( nil, "OVERLAY" )
		cell.reset_border_top:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.reset_border_top:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.reset_border_top:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
		cell.reset_border_top:SetHeight( 1 )
		cell.reset_border_top:SetVertexColor( 1, 0.82, 0, 0.22 )
		cell.reset_border_top:Hide()

		cell.reset_border_left = cell:CreateTexture( nil, "OVERLAY" )
		cell.reset_border_left:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cell.reset_border_left:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
		cell.reset_border_left:SetPoint( "BottomLeft", cell, "BottomLeft", 1, 1 )
		cell.reset_border_left:SetWidth( 1 )
		cell.reset_border_left:SetVertexColor( 1, 0.82, 0, 0.18 )
		cell.reset_border_left:Hide()
		cell.reset_icons = {}

		cell:SetScript( "OnEnter", function()
			if (not m.should_show_raid_reset_icons or m.should_show_raid_reset_icons()) and cell.raid_resets and getn( cell.raid_resets ) > 0 then
				m.show_raid_reset_tooltip( cell, cell.raid_resets, cell.day_time )
			end
		end )

		cell:SetScript( "OnLeave", function()
			if GameTooltip and GameTooltip:IsOwned( cell ) then
				GameTooltip:Hide()
			end
		end )

		cell:SetScript( "OnClick", function()
			if not cell.day_time then
				return
			end
			set_selected_day( cell.day_time )
			popup.refresh()
		end )

		return cell
	end

	hide_reset_icon_slots = function( cell )
		if not cell or not cell.reset_icons then
			return
		end
		cell.reset_icon_rows = 0
		for i = 1, getn( cell.reset_icons ) do
			cell.reset_icons[ i ].bg:Hide()
			cell.reset_icons[ i ].icon:Hide()
		end
	end

	ensure_reset_icon_slot = function( cell, index )
		if not cell.reset_icons then
			cell.reset_icons = {}
		end
		if cell.reset_icons[ index ] then
			return cell.reset_icons[ index ]
		end

		local slot = {}
		slot.bg = cell:CreateTexture( nil, "ARTWORK" )
		slot.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		slot.bg:SetVertexColor( 0, 0, 0, 0.44 )
		slot.bg:SetWidth( 15 )
		slot.bg:SetHeight( 15 )
		slot.bg:Hide()

		slot.icon = cell:CreateTexture( nil, "OVERLAY" )
		slot.icon:SetWidth( 13 )
		slot.icon:SetHeight( 13 )
		slot.icon:SetTexCoord( 0.08, 0.92, 0.08, 0.92 )
		slot.icon:Hide()

		cell.reset_icons[ index ] = slot
		return slot
	end

	render_reset_icons = function( cell, visuals, is_current )
		hide_reset_icon_slots( cell )
		if type( visuals ) ~= "table" or getn( visuals ) == 0 then
			return
		end

		local icons_per_row = 5
		local max_icons = math.min( getn( visuals ), 10 )
		local row_count = math.ceil( max_icons / icons_per_row )
		cell.reset_icon_rows = row_count
		local start_x = 4
		local start_y = (row_count > 1) and -14 or -17
		local step_x = 14
		local step_y = 15

		for i = 1, max_icons do
			local visual = visuals[ i ]
			local slot = ensure_reset_icon_slot( cell, i )
			local row = math.floor( (i - 1) / icons_per_row )
			local col = math.mod( i - 1, icons_per_row )
			local x = start_x + (col * step_x)
			local y = start_y - (row * step_y)

			slot.bg:ClearAllPoints()
			slot.bg:SetPoint( "TopLeft", cell, "TopLeft", x, y )
			slot.bg:SetVertexColor( 0, 0, 0, is_current and 0.44 or 0.56 )
			slot.bg:Show()

			slot.icon:ClearAllPoints()
			slot.icon:SetPoint( "CENTER", slot.bg, "CENTER", 0, 0 )
			slot.icon:SetTexture( visual.texture )
			slot.icon:SetVertexColor( 1, 1, 1, visual.alpha or 0.92 )
			slot.icon:Show()
		end
	end

	local function create_frame()
		---@class CalendarFrame: BuilderFrame
		local frame = m.FrameBuilder.new()
			:name( "RaidCalendarPopupPfui" )
			:title( string.format( "Gaulois Raid Calendar v%s", m.version ) )
			:frame_style( "TOOLTIP" )
			:frame_level( 80 )
			:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
			:backdrop_color( 0.02, 0.02, 0.03, 0.97 )
			:close_button()
			:width( 930 )
			:height( 584 )
			:movable()
			:esc()
			:on_drag_stop( save_position )
			:build()

		if m.db.popup_calendar.position then
			local p = m.db.popup_calendar.position
			frame:ClearAllPoints()
			frame:SetPoint( p.point, UIParent, p.relative_point, p.x, p.y )
		end

		-- Bouton Refresh
		frame.btn_refresh = m.GuiElements.tiny_button( frame, "R", nil, "#20F99F" )
		frame.btn_refresh.tooltip_key = "ui.refresh"
		frame.btn_refresh:SetPoint( "Right", frame.titlebar.btn_close, "Left", 2, 0 )
		frame.btn_refresh:SetScript( "OnClick", function()
			frame.btn_refresh:Disable()
			m.msg.request_events( true )
			if not m.debug_enabled then
				m.ace_timer.ScheduleTimer( M, function()
					frame.btn_refresh:Enable()
				end, 30 )
			end
		end )

		-- Bouton Settings
		frame.btn_settings = m.GuiElements.tiny_button( frame, "S", nil, "#F3DF2B" )
		frame.btn_settings.tooltip_key = "ui.settings"
		frame.btn_settings:SetPoint( "Right", frame.btn_refresh, "Left", 2, 0 )
		frame.btn_settings:SetScript( "OnClick", function()
			frame.btn_settings.active = not frame.settings:IsVisible()
			if frame.settings:IsVisible() then
				pending_locale_flag = nil
				pending_time_format = nil
				frame.settings:Hide()
				if m.pfui_skin_enabled then
					frame.btn_settings:SetBackdropBorderColor( 0.2, 0.2, 0.2, 1 )
				end
			else
				pending_time_format = m.db.user_settings.time_format
				pending_locale_flag = m.db.user_settings.locale_flag or "enUS"
				frame.settings.time_format:SetSelected( pending_time_format )
				frame.settings.locale_flag:SetSelected( pending_locale_flag )
				if frame.settings.show_raid_resets then
					frame.settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 and 1 or nil )
				end
				if frame.settings.refresh_discord_ui then
					frame.settings.refresh_discord_ui()
				end
				refresh_settings_labels()
				frame.settings:Show()
				if m.pfui_skin_enabled then
					frame.btn_settings:SetBackdropBorderColor( 0.95, 0.87, 0.17, 1 )
				end
			end
		end )

		-- Bouton Nouvel evenement
		frame.btn_new_event = m.GuiElements.tiny_button( frame, "+", nil, "#00FFFF" )
		frame.btn_new_event.tooltip_key = "ui.new_event"
		frame.btn_new_event:SetPoint( "Right", frame.btn_settings, "Left", -2, 0 )
		frame.btn_new_event:SetScript( "OnClick", function()
			if m.EventManagePopup then
				m.EventManagePopup.show_create()
			end
		end )

		-- LED bot indicator
		frame.online_indicator = gui.create_online_indicator( frame, frame.btn_new_event )

		frame.calendar_panel = m.FrameBuilder.new()
			:parent( frame )
			:point( "TopLeft", frame, "TopLeft", 10, -32 )
			:width( 648 )
			:height( 542 )
			:frame_style( "TOOLTIP" )
			:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
			:backdrop_color( 0.04, 0.04, 0.06, 1 )
			:build()

		frame.detail_panel = m.FrameBuilder.new()
			:parent( frame )
			:point( "TopLeft", frame.calendar_panel, "TopRight", 8, 0 )
			:width( 252 )
			:height( 542 )
			:frame_style( "TOOLTIP" )
			:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
			:backdrop_color( 0.04, 0.04, 0.06, 1 )
			:build()

		frame.btn_prev_month = gui.tiny_button( frame.calendar_panel, "<", nil, "#c8a84b", 14 )
		frame.btn_prev_month:SetWidth( 24 )
		frame.btn_prev_month:SetHeight( 18 )
		frame.btn_prev_month:SetScript( "OnClick", function()
			current_month_time = shift_month( current_month_time or get_today(), -1 )
			selected_day = normalize_day( current_month_time )
			selected_event_key = nil
			frame.refresh()
		end )
		frame.btn_prev_month:SetPoint( "TopLeft", frame.calendar_panel, "TopLeft", 12, -12 )

		frame.btn_next_month = gui.tiny_button( frame.calendar_panel, ">", nil, "#c8a84b", 14 )
		frame.btn_next_month:SetWidth( 24 )
		frame.btn_next_month:SetHeight( 18 )
		frame.btn_next_month:SetScript( "OnClick", function()
			current_month_time = shift_month( current_month_time or get_today(), 1 )
			selected_day = normalize_day( current_month_time )
			selected_event_key = nil
			frame.refresh()
		end )
		frame.btn_next_month:SetPoint( "TopRight", frame.calendar_panel, "TopRight", -12, -12 )

		frame.btn_today = gui.tiny_button( frame.calendar_panel,
			m.L( "actions.today" ) or "Today", nil, "#c8a84b", 11 )
		frame.btn_today:SetWidth( 80 )
		frame.btn_today:SetHeight( 18 )
		frame.btn_today:SetScript( "OnClick", function()
			selected_day = get_today()
			selected_event_key = nil
			current_month_time = selected_day
			frame.refresh()
		end )
		frame.btn_today:SetPoint( "TopRight", frame.btn_next_month, "TopLeft", -6, 0 )

		frame.month_label = frame.calendar_panel:CreateFontString( nil, "ARTWORK", "RCFontHighlightBig" )
		frame.month_label:SetPoint( "Top", frame.calendar_panel, "Top", 0, -17 )
		frame.month_label:SetJustifyH( "Center" )
		-- Ligne décorative sous le mois
		local cal_sep = frame.calendar_panel:CreateTexture( nil, "ARTWORK" )
		cal_sep:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		cal_sep:SetPoint( "TopLeft", frame.calendar_panel, "TopLeft", 40, -40 )
		cal_sep:SetPoint( "TopRight", frame.calendar_panel, "TopRight", -40, -40 )
		cal_sep:SetHeight( 1 )
		cal_sep:SetVertexColor( 0.60, 0.46, 0.08, 0.45 )

		local week_header = CreateFrame( "Frame", nil, frame.calendar_panel )
		week_header:SetPoint( "TopLeft", frame.calendar_panel, "TopLeft", 12, -46 )
		week_header:SetWidth( 616 )
		week_header:SetHeight( 18 )

		-- Bande de fond derrière les labels de jours
		local wh_bg = week_header:CreateTexture( nil, "BACKGROUND" )
		wh_bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		wh_bg:SetAllPoints( week_header )
		wh_bg:SetVertexColor( 0.12, 0.10, 0.03, 0.55 )

		-- Séparateur bas de la bande
		local wh_sep = week_header:CreateTexture( nil, "ARTWORK" )
		wh_sep:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		wh_sep:SetPoint( "BottomLeft", week_header, "BottomLeft", 0, 0 )
		wh_sep:SetPoint( "BottomRight", week_header, "BottomRight", 0, 0 )
		wh_sep:SetHeight( 1 )
		wh_sep:SetVertexColor( 0.55, 0.42, 0.08, 0.60 )

		frame.week_day_labels = {}
		for i = 1, days_per_week do
			local label = week_header:CreateFontString( nil, "ARTWORK", "RCFontNormalBold" )
			label:SetWidth( 88 )
			label:SetHeight( 18 )
			label:SetPoint( "TopLeft", week_header, "TopLeft", (i - 1) * 88, 0 )
			label:SetJustifyH( "Center" )
			if i == 6 then
				label:SetTextColor( 1, 0.55, 0 )
			elseif i == 7 then
				label:SetTextColor( 1, 0.2, 0.2 )
			else
				label:SetTextColor( 0.92, 0.82, 0.35 )
			end
			label:SetText( m.get_day_name( mod( i, 7 ) + 1, true ) )
			frame.week_day_labels[ i ] = label
		end

		local grid = CreateFrame( "Frame", nil, frame.calendar_panel )
		grid:SetPoint( "TopLeft", week_header, "BottomLeft", 0, -6 )
		grid:SetWidth( 616 )
		grid:SetHeight( 456 )
		frame.grid = grid

		for row = 1, weeks do
			for column = 1, days_per_week do
				local cell = create_day_cell( grid, 88, 76 )
				cell:SetPoint( "TopLeft", grid, "TopLeft", (column - 1) * 88, -((row - 1) * 76) )
				table.insert( day_cells, cell )
			end
		end

		frame.empty_state = frame.calendar_panel:CreateFontString( nil, "ARTWORK", "RCFontNormalH2" )
		frame.empty_state:SetPoint( "Center", grid, "Center", 0, 0 )
		frame.empty_state:SetTextColor( 0.72, 0.72, 0.72 )
		frame.empty_state:SetText( m.L( "ui.no_events_loaded" ) )
		frame.empty_state:Hide()

		frame.detail_panel.header = frame.detail_panel:CreateFontString( nil, "ARTWORK", "RCFontHighlightBig" )
		frame.detail_panel.header:SetPoint( "TopLeft", frame.detail_panel, "TopLeft", 12, -11 )
		frame.detail_panel.header:SetText( m.L( "ui.month_events" ) )

		-- Séparateur doré sous le titre du panneau
		frame.detail_panel.separator = frame.detail_panel:CreateTexture( nil, "ARTWORK" )
		frame.detail_panel.separator:SetTexture( "Interface\\Buttons\\WHITE8x8" )
		frame.detail_panel.separator:SetPoint( "TopLeft", frame.detail_panel.header, "BottomLeft", 0, -5 )
		frame.detail_panel.separator:SetPoint( "TopRight", frame.detail_panel, "TopRight", -12, 0 )
		frame.detail_panel.separator:SetHeight( 1 )
		frame.detail_panel.separator:SetVertexColor( 0.72, 0.56, 0.08, 0.70 )

		frame.detail_panel.subheader = frame.detail_panel:CreateFontString( nil, "ARTWORK", "RCFontNormalBold" )
		frame.detail_panel.subheader:SetPoint( "TopLeft", frame.detail_panel.separator, "BottomLeft", 0, -5 )
		frame.detail_panel.subheader:SetTextColor( 0.96, 0.84, 0.28 )

		frame.detail_panel.header_count = frame.detail_panel:CreateFontString( nil, "ARTWORK", "RCFontNormalSmall" )
		frame.detail_panel.header_count:SetPoint( "TopLeft", frame.detail_panel.subheader, "BottomLeft", 0, -3 )
		frame.detail_panel.header_count:SetTextColor( 0.68, 0.68, 0.76 )

		frame.detail_panel.empty = frame.detail_panel:CreateFontString( nil, "ARTWORK", "RCFontNormalH3" )
		frame.detail_panel.empty:SetPoint( "Center", frame.detail_panel, "Center", 0, 0 )
		frame.detail_panel.empty:SetTextColor( 0.58, 0.58, 0.62 )
		frame.detail_panel.empty:SetText( m.L( "ui.no_events_month" ) )
		frame.detail_panel.empty:Hide()

		frame.settings = m.FrameBuilder.new()
			:parent( frame )
			:point( "TopLeft", frame, "TopLeft", 10, -32 )
			:point( "Right", frame.detail_panel, "Right", 0, 0 )
			:height( 160 )
			:frame_level( 85 )
			:frame_style( "TOOLTIP" )
			:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
			:backdrop_color( 0, 0, 0, 0.97 )
			:hidden()
			:build()

		local btn_welcome = gui.create_button( frame.settings, m.L( "actions.welcome_popup" ) or "Welcome popup", 130, function()
			m.welcome_popup.show()
			popup:Hide()
		end )
		btn_welcome:SetPoint( "TopRight", frame.settings, "TopRight", -10, -15 )
		frame.settings.btn_welcome = btn_welcome

		local btn_disconnect_pf
		btn_disconnect_pf = gui.create_button( frame.settings, m.L( "actions.disconnect" ) or "Disconnect", 110, function()
			m.db.user_settings.discord_id = nil
			m.db.user_settings.channel_access = {}
			if frame.settings.refresh_discord_ui then
				frame.settings.refresh_discord_ui()
			end
		end )
		-- Meme position que btn_welcome : exclusion mutuelle
		btn_disconnect_pf:SetPoint( "TopRight", frame.settings, "TopRight", -10, -15 )
		btn_disconnect_pf:Hide()
		frame.settings.btn_disconnect = btn_disconnect_pf

		local btn_save = gui.create_button( frame.settings, m.L( "actions.save" ) or "Save", 110, on_save_settings )
		-- Ancre sur btn_welcome (position fixe)
		btn_save:SetPoint( "TopRight", btn_welcome, "TopRight", 0, -30 )
		frame.settings.btn_save = btn_save

		local function refresh_discord_ui_pf()
			if m.db.user_settings.discord_id and m.db.user_settings.discord_id ~= "" then
				btn_welcome:Hide()
				if btn_disconnect_pf then btn_disconnect_pf:Show() end
			else
				btn_welcome:Show()
				if btn_disconnect_pf then btn_disconnect_pf:Hide() end
			end
		end
		frame.settings.refresh_discord_ui = refresh_discord_ui_pf

		-- (case use_character_name supprimee, valeur forcee a 1 dans RaidCalendar.lua)

		local settings_label_x = 10
		local settings_first_row_y = -20
		local settings_row_spacing = 32
		local settings_label_width = 105
		local settings_dropdown_x = settings_label_x + settings_label_width + 6

		local lbl_tf = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_tf:SetWidth( settings_label_width )
		lbl_tf:SetJustifyH( "Left" )
		lbl_tf:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_label_x, settings_first_row_y )
		lbl_tf:SetText( m.L( "ui.time_format" ) )
		frame.settings.label_timeformat = lbl_tf

		local dd_timeformat = scroll_drop:New( frame.settings, {
			default_text = "",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_timeformat:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_dropdown_x, settings_first_row_y + 2 )
		dd_timeformat:SetItems( {
			{ value = "12", text = m.L( "options.time_format_12" ) },
			{ value = "24", text = m.L( "options.time_format_24" ) }
		}, function( value )
			pending_time_format = value
		end )
		frame.settings.time_format = dd_timeformat

		local lbl_loc = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_loc:SetWidth( settings_label_width )
		lbl_loc:SetJustifyH( "Left" )
		lbl_loc:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_label_x, settings_first_row_y - settings_row_spacing )
		lbl_loc:SetText( m.L( "ui.language" ) )
		frame.settings.label_locale = lbl_loc

		local dd_locale = scroll_drop:New( frame.settings, {
			default_text = m.L( "ui.select_language" ),
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_locale:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_dropdown_x, settings_first_row_y - settings_row_spacing + 2 )
		dd_locale:SetItems( (m.get_available_locales and m.get_available_locales()) or {
			{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
			{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Fran\195\167ais" }
		}, function( value )
			pending_locale_flag = value
		end )
		frame.settings.locale_flag = dd_locale

		local lbl_theme = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_theme:SetWidth( settings_label_width )
		lbl_theme:SetJustifyH( "Left" )
		lbl_theme:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_label_x, settings_first_row_y - (settings_row_spacing * 2) )
		lbl_theme:SetText( m.L( "ui.ui_theme" ) )
		frame.settings.lbl_theme = lbl_theme

		local dd_theme = scroll_drop:New( frame.settings, {
			default_text = m.db.user_settings.ui_theme or "Original",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_theme:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_dropdown_x, settings_first_row_y - (settings_row_spacing * 2) + 2 )
		dd_theme:SetItems( {
			{ value = "Original", text = "Original" },
			{ value = "Pfui", text = "pfUI" },
			{ value = "Blizzard", text = "Blizzard" }
		} )
		pending_ui_theme = m.db.user_settings.ui_theme or "Original"
		dd_theme:SetSelected( pending_ui_theme )
		dd_theme.on_select = function( sel )
			if not sel then
				return
			end

			pending_ui_theme = sel
		end
		frame.settings.dd_theme = dd_theme

		local cb_reset_icons = CreateFrame( "CheckButton", "RaidCalendarPopupShowRaidResetsPfui", frame.settings, "UICheckButtonTemplate" )
		cb_reset_icons:SetWidth( 22 )
		cb_reset_icons:SetHeight( 22 )
		cb_reset_icons:SetPoint( "TopLeft", frame.settings, "TopLeft", 300, settings_first_row_y - settings_row_spacing + 2 )
		getglobal( cb_reset_icons:GetName() .. "Text" ):SetText( m.L( "ui.show_raid_resets" ) )
		frame.settings.show_raid_resets = cb_reset_icons

		-- Label + EditBox pour l'offset UTC du serveur WoW
		local lbl_utc = frame.settings:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
		lbl_utc:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_label_x, settings_first_row_y - (settings_row_spacing * 3) )
		lbl_utc:SetText( m.L( "ui.wow_utc_offset" ) or "WoW UTC offset (s)" )
		frame.settings.lbl_utc_offset = lbl_utc
		local eb_utc = CreateFrame( "EditBox", "RaidCalendarUtcOffsetPfui", frame.settings )
		eb_utc:SetWidth( 60 )
		eb_utc:SetHeight( 18 )
		eb_utc:SetPoint( "TopLeft", frame.settings, "TopLeft", settings_dropdown_x, settings_first_row_y - (settings_row_spacing * 3) + 2 )
		eb_utc:SetAutoFocus( false )
		eb_utc:SetMaxLetters( 7 )
		eb_utc:SetText( tostring( m.db.user_settings.wow_utc_offset or 0 ) )
		eb_utc:SetFontObject( "GameFontHighlightSmall" )
		if m.pfui_skin_enabled and m.api and m.api.pfUI and m.api.pfUI.api then
			local pfui = m.api.pfUI.api
			if pfui.StripTextures then pfui.StripTextures( eb_utc ) end
			if pfui.CreateBackdrop then pfui.CreateBackdrop( eb_utc, nil, true ) end
		else
			local bd = CreateFrame( "Frame", nil, eb_utc )
			bd:SetAllPoints()
			bd:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 } )
			bd:SetBackdropColor( 0, 0, 0, 0.85 )
			bd:SetBackdropBorderColor( 0.3, 0.3, 0.3, 1 )
		end
		frame.settings.eb_utc_offset = eb_utc

		if m.pfui_skin_enabled and m.api and m.api.pfUI and m.api.pfUI.api then
			local pfui = m.api.pfUI.api
			if pfui.StripTextures then
				pfui.StripTextures( dd_theme )
			end
			if pfui.CreateBackdrop then
				pfui.CreateBackdrop( dd_theme, nil, true )
			end
			if dd_theme.dropdown_button then
				if pfui.SkinArrowButton then
					pfui.SkinArrowButton( dd_theme.dropdown_button, "down", 16 )
				end
				dd_theme.dropdown_button:SetPoint( "Right", dd_theme, "Right", -4, 0 )
			end
		end

		frame.settings.btn_loopup = nil
		frame.settings.discord = nil
		frame.settings.discord_response = nil

		frame.refresh = refresh_calendar
		gui.pfui_skin( frame )

		frame:SetScript( "OnHide", function()
			if m.close_all_popups then m.close_all_popups() end
		end )

		return frame
	end

	local auto_refresh_timer_cal = nil

	local function show()
		if not popup then
			popup = create_frame()
		end

		if not current_month_time then
			current_month_time = get_today()
		end

		selected_event_key = nil
		popup:Show()
		popup.refresh()

		if m.msg then
			m.msg.request_events( true )
		end
		-- Auto-refresh toutes les 60 secondes quand le calendrier est ouvert
		if m.ace_timer then
			if auto_refresh_timer_cal then
				m.ace_timer.CancelTimer( m, auto_refresh_timer_cal )
			end
			auto_refresh_timer_cal = m.ace_timer.ScheduleRepeatingTimer( m, function()
				if popup and popup:IsVisible() and m.msg then
					m.msg.request_events()
				end
			end, 60 )
		end
	end

	local function hide()
		if auto_refresh_timer_cal and m.ace_timer then
			m.ace_timer.CancelTimer( m, auto_refresh_timer_cal )
			auto_refresh_timer_cal = nil
		end
		if m.close_all_popups then m.close_all_popups() end
		if popup then
			popup:Hide()
		end
	end

	local function toggle()
		if popup and popup:IsVisible() then
			popup:Hide()
		else
			show()
		end
	end

	local function is_visible()
		return popup and popup:IsVisible() or false
	end

	local function unselect()
		selected_event_key = nil
		if popup and popup:IsVisible() then
			popup.refresh()
		end
	end

	local function discord_response( success, user_id )
		if popup and popup:IsVisible() and popup.settings.btn_loopup then
			popup.settings.btn_loopup:Enable()
			if success then
				local name = popup.settings.discord and popup.settings.discord:GetText() or ""
				popup.settings.discord_response:SetText( m.L( "ui.name_found", { name = name } ) )
				if popup.settings.discord then
					popup.settings.discord:SetText( user_id )
				end
			else
				popup.settings.discord_response:SetText( m.L( "ui.name_not_found" ) )
			end
		end
	end

	local function auth_response()
	end

	local function update()
		if popup and popup:IsVisible() then
			if getn( m.db.local_events or {} ) > 0 then
				local_events_requested = false
			end
			refresh_data( true )
			popup.refresh()
		end
	end

	local function sync_settings()
		if not popup then
			return
		end
		if popup.settings and popup.settings.time_format then
			popup.settings.time_format:SetSelected( (popup.settings:IsVisible() and pending_time_format) or m.db.user_settings.time_format )
		end
		if popup.settings and popup.settings.locale_flag then
			popup.settings.locale_flag:SetSelected( (popup.settings:IsVisible() and pending_locale_flag) or (m.db.user_settings.locale_flag or "enUS") )
		end
		if popup.settings and popup.settings.show_raid_resets then
			popup.settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 and 1 or nil )
		end
		if popup.settings and popup.settings.eb_utc_offset then
			popup.settings.eb_utc_offset:SetText( tostring( m.db.user_settings.wow_utc_offset or 0 ) )
		end
		pending_ui_theme = m.db.user_settings.ui_theme or "Original"
		if popup.settings and popup.settings.dd_theme then
			popup.settings.dd_theme:SetSelected( pending_ui_theme )
		end
	end

	---@type CalendarPopup
	return {
		show = show,
		hide = hide,
		toggle = toggle,
		is_visible = is_visible,
		unselect = unselect,
		discord_response = discord_response,
		auth_response = auth_response,
		update = update,
		sync_settings = sync_settings
	}
end

m.CalendarPopupPfui = M
return M
