RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.CalendarPopupBlizzard then return end

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

local TEX = "Interface\\AddOns\\RaidCalendar\\Textures\\"
local TC = {
	Top = { 0, 715 / 1024, 0, 50 / 64 },
	Bottom = { 0, 715 / 1024, 0, 6 / 8 },
	Left = { 0, 9 / 16, 0, 629 / 1024 },
	Right = { 0, 9 / 16, 0, 629 / 1024 },
	Bg = { 0, 100 / 128, 0, 100 / 128 },
	Arrow = { 0, 20 / 32, 0, 20 / 32 }
}
local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"
local BORDER_L = 9
local BORDER_R = 9
local BORDER_T = 50
local BORDER_B = 6
local CELL_SIZE = 100
local CELL_STEP = CELL_SIZE - 1
local COLS = 7
local DAY_LABEL_H = 29
local DETAIL_W = 260
local CAL_W = BORDER_L + COLS * CELL_STEP + 1 + BORDER_R
local MAX_CHIPS = 3
local UI_SCALE = 0.90

function M.new()
	local popup = nil
	local detail_panel = nil
	local tex_left, tex_right
	local day_labels = {}
	local day_headers = {}
	local cell_pool = {}
	local cell_pool_n = 0
	local used_cells = {}
	local used_count = 0
	local selected_day = nil
	local selected_event_key = nil
	local current_year = nil
	local current_month = nil
	local events = nil
	local events_by_day = {}
	local detail_items = {}
	local local_events_requested = false
	local gui = m.GuiElements

	local function normalize_day( ts )
		local info = date( "*t", ts )
		info.hour = 12
		info.min = 0
		info.sec = 0
		return time( info )
	end

	local function get_today()
		return normalize_day( time( date( "*t" ) ) )
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

	local function get_grid_base_frame_level()
		if popup and popup.GetFrameLevel then
			return popup:GetFrameLevel() + 2
		end
		return 82
	end

	local function apply_ui_scale( frame )
		if frame and frame.SetScale then
			frame:SetScale( UI_SCALE )
		end
	end

	local function get_checkbox_label( checkbox )
		if not checkbox then
			return nil
		end

		local label = getglobal( checkbox:GetName() .. "Text" )
		if label then
			return label
		end

		local regions = { checkbox:GetRegions() }
		for _, region in ipairs( regions ) do
			if region and region.GetObjectType and region:GetObjectType() == "FontString" then
				return region
			end
		end

		return nil
	end

	local function center_checkbox_with_text( parent, checkbox, anchor_y )
		if not parent or not checkbox then
			return
		end

		local label = get_checkbox_label( checkbox )
		if not label then
			return
		end

		label:Show()
		label:SetTextColor( 1, 0.82, 0, 1 )
		label:ClearAllPoints()
		label:SetPoint( "LEFT", checkbox, "RIGHT", 2, 1 )
		label:SetJustifyH( "LEFT" )

		local spacing = 2
		local total_width = checkbox:GetWidth() + spacing + label:GetStringWidth()

		checkbox:ClearAllPoints()
		checkbox:SetPoint( "TOPLEFT", parent, "TOP", -(total_width / 2), anchor_y )
	end

	local function get_month_grid_start( month_time )
		local info = date( "*t", month_time )
		info.day = 1
		info.hour = 12
		info.min = 0
		info.sec = 0
		local first_of_month = time( info )
		local weekday = tonumber( date( "%w", first_of_month ) ) or 0
		local monday_offset = mod( weekday + 6, 7 )
		return normalize_day( first_of_month - monday_offset * 86400 )
	end

	local function shift_month( year, month, amount )
		month = month + amount
		while month < 1 do
			month = month + 12
			year = year - 1
		end
		while month > 12 do
			month = month - 12
			year = year + 1
		end
		return year, month
	end

	local function build_event_cache()
		events_by_day = {}
		if not events then
			return
		end
		for _, item in ipairs( events ) do
			-- Chercher l'event dans raidhelper ou local selon source
			local event = item.source == "local"
				and ( m.db.local_events and m.db.local_events[ item.key ] )
				or  m.db.events[ item.key ]
			if event and event.startTime then
				local dk = tostring( normalize_day( event.startTime ) )
				events_by_day[ dk ] = events_by_day[ dk ] or {}
				table.insert( events_by_day[ dk ], item )
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
			if table.getn( events ) == 0 then
				m.msg.request_events()
			end
		end
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

	local function get_cell()
		local cell
		if cell_pool_n > 0 then
			cell = cell_pool[ cell_pool_n ]
			cell_pool[ cell_pool_n ] = nil
			cell_pool_n = cell_pool_n - 1
		else
			cell = CreateFrame( "Frame", nil, popup )
			cell:SetWidth( CELL_SIZE )
			cell:SetHeight( CELL_SIZE )
				cell:EnableMouse( true )
			if popup and popup.GetFrameStrata then
				cell:SetFrameStrata( popup:GetFrameStrata() )
			end

			local bh = CreateFrame( "Frame", nil, cell )
			bh:SetAllPoints()
			local bg = bh:CreateTexture( nil, "BACKGROUND" )
			bg:SetTexture( TEX .. "UI-Calendar-Background" )
			bg:SetTexCoord( TC.Bg[ 1 ], TC.Bg[ 2 ], TC.Bg[ 3 ], TC.Bg[ 4 ] )
			bg:SetAllPoints()
			cell.bg = bg

			local function ln( h, w )
				local t = cell:CreateTexture( nil, "ARTWORK" )
				t:SetTexture( SOLID )
				if h then
					t:SetHeight( h )
				else
					t:SetWidth( w )
				end
				return t
			end

			local bT = ln( 1, nil )
			bT:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
			bT:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
			local bB = ln( 1, nil )
			bB:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
			bB:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
			local bL = ln( nil, 1 )
			bL:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
			bL:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
			local bR = ln( nil, 1 )
			bR:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
			bR:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
			cell.borders = { bT, bB, bL, bR }

			local gT = ln( 2, nil )
			gT:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
			gT:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
			gT:SetVertexColor( 1, 0.82, 0.1, 1 )
			gT:Hide()

			local gB = ln( 2, nil )
			gB:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
			gB:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
			gB:SetVertexColor( 1, 0.82, 0.1, 1 )
			gB:Hide()

			local gL = ln( nil, 2 )
			gL:SetPoint( "TopLeft", cell, "TopLeft", 0, 0 )
			gL:SetPoint( "BottomLeft", cell, "BottomLeft", 0, 0 )
			gL:SetVertexColor( 1, 0.82, 0.1, 1 )
			gL:Hide()

			local gR = ln( nil, 2 )
			gR:SetPoint( "TopRight", cell, "TopRight", 0, 0 )
			gR:SetPoint( "BottomRight", cell, "BottomRight", 0, 0 )
			gR:SetVertexColor( 1, 0.82, 0.1, 1 )
			gR:Hide()

			cell.gold = { gT, gB, gL, gR }

			local hl = cell:CreateTexture( nil, "OVERLAY" )
			hl:SetTexture( SOLID )
			hl:SetVertexColor( 0, 0, 0, 0 )
			hl:SetAllPoints( cell )
			cell.hl = hl

			cell.num = cell:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
			cell.num:SetPoint( "TopLeft", cell, "TopLeft", 5, -4 )

			cell.reset_bg = cell:CreateTexture( nil, "ARTWORK" )
			cell.reset_bg:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
			cell.reset_bg:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
			cell.reset_bg:SetTexCoord( 0.08, 0.92, 0.08, 0.92 )
			cell.reset_bg:Hide()

			cell.reset_dim = cell:CreateTexture( nil, "ARTWORK" )
			cell.reset_dim:SetTexture( SOLID )
			cell.reset_dim:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
			cell.reset_dim:SetPoint( "BottomRight", cell, "BottomRight", -1, 1 )
			cell.reset_dim:SetVertexColor( 0, 0, 0, 0.5 )
			cell.reset_dim:Hide()

			cell.reset_ribbon = cell:CreateTexture( nil, "ARTWORK" )
			cell.reset_ribbon:SetTexture( SOLID )
			cell.reset_ribbon:SetPoint( "TopLeft", cell, "TopLeft", 1, -1 )
			cell.reset_ribbon:SetPoint( "TopRight", cell, "TopRight", -1, -1 )
			cell.reset_ribbon:SetHeight( 6 )
			cell.reset_ribbon:Hide()

			cell.reset_border_top = cell:CreateTexture( nil, "OVERLAY" )
			cell.reset_border_top:SetTexture( SOLID )
			cell.reset_border_top:SetPoint( "TopLeft", cell, "TopLeft", 2, -2 )
			cell.reset_border_top:SetPoint( "TopRight", cell, "TopRight", -2, -2 )
			cell.reset_border_top:SetHeight( 1 )
			cell.reset_border_top:Hide()

			cell.reset_border_left = cell:CreateTexture( nil, "OVERLAY" )
			cell.reset_border_left:SetTexture( SOLID )
			cell.reset_border_left:SetPoint( "TopLeft", cell, "TopLeft", 2, -2 )
			cell.reset_border_left:SetPoint( "BottomLeft", cell, "BottomLeft", 2, 2 )
			cell.reset_border_left:SetWidth( 1 )
			cell.reset_border_left:Hide()

			cell.reset_shadow_bottom = cell:CreateTexture( nil, "OVERLAY" )
			cell.reset_shadow_bottom:SetTexture( SOLID )
			cell.reset_shadow_bottom:SetPoint( "BottomLeft", cell, "BottomLeft", 2, 2 )
			cell.reset_shadow_bottom:SetPoint( "BottomRight", cell, "BottomRight", -2, 2 )
			cell.reset_shadow_bottom:SetHeight( 1 )
			cell.reset_shadow_bottom:Hide()

			cell.reset_shadow_right = cell:CreateTexture( nil, "OVERLAY" )
			cell.reset_shadow_right:SetTexture( SOLID )
			cell.reset_shadow_right:SetPoint( "TopRight", cell, "TopRight", -2, -2 )
			cell.reset_shadow_right:SetPoint( "BottomRight", cell, "BottomRight", -2, 2 )
			cell.reset_shadow_right:SetWidth( 1 )
			cell.reset_shadow_right:Hide()
			cell.reset_icons = {}

			cell:SetScript( "OnEnter", function()
				cell.hl:SetVertexColor( 0, 0, 0, 0.2 )
				if (not m.should_show_raid_reset_icons or m.should_show_raid_reset_icons()) and cell.raid_resets and getn( cell.raid_resets ) > 0 then
					m.show_raid_reset_tooltip( cell, cell.raid_resets, cell.day_time )
				end
			end )
			cell:SetScript( "OnLeave", function()
				cell.hl:SetVertexColor( 0, 0, 0, 0 )
				if GameTooltip and GameTooltip:IsOwned( cell ) then
					GameTooltip:Hide()
				end
			end )

			cell.chips = {}
		end
		return cell
	end

	local function hide_reset_icon_slots( cell )
		if not cell or not cell.reset_icons then
			return
		end
		cell.reset_icon_rows = 0
		for i = 1, getn( cell.reset_icons ) do
			cell.reset_icons[ i ].bg:Hide()
			cell.reset_icons[ i ].icon:Hide()
		end
	end

	local function ensure_reset_icon_slot( cell, index )
		if not cell.reset_icons then
			cell.reset_icons = {}
		end
		if cell.reset_icons[ index ] then
			return cell.reset_icons[ index ]
		end

		local slot = {}
		slot.bg = cell:CreateTexture( nil, "ARTWORK" )
		slot.bg:SetTexture( SOLID )
		slot.bg:SetVertexColor( 0, 0, 0, 0.42 )
		slot.bg:SetWidth( 16 )
		slot.bg:SetHeight( 16 )
		slot.bg:Hide()

		slot.icon = cell:CreateTexture( nil, "OVERLAY" )
		slot.icon:SetWidth( 14 )
		slot.icon:SetHeight( 14 )
		slot.icon:SetTexCoord( 0.08, 0.92, 0.08, 0.92 )
		slot.icon:Hide()

		cell.reset_icons[ index ] = slot
		return slot
	end

	local function render_reset_icons( cell, visuals, is_current )
		hide_reset_icon_slots( cell )
		if type( visuals ) ~= "table" or getn( visuals ) == 0 then
			return
		end

		local icons_per_row = 5
		local max_icons = math.min( getn( visuals ), 10 )
		local row_count = math.ceil( max_icons / icons_per_row )
		cell.reset_icon_rows = row_count
		local start_x = 4
		local start_y = (row_count > 1) and -12 or -18
		local step_x = 16
		local step_y = 17

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

	local function recycle_cells()
		for i = 1, used_count do
			local cell = used_cells[ i ]
			cell:Hide()
			if cell.chips then
				for _, ch in ipairs( cell.chips ) do
					ch:Hide()
				end
			end
			cell:SetScript( "OnMouseUp", nil )
			cell_pool_n = cell_pool_n + 1
			cell_pool[ cell_pool_n ] = cell
			used_cells[ i ] = nil
		end
		used_count = 0
	end

	local function get_current_month_events()
		local month_evts = {}

		if not events or not current_year or not current_month then
			return month_evts
		end

		for _, item in ipairs( events ) do
			local ev
			if item.source == "local" then
				ev = m.db.local_events and m.db.local_events[ item.key ]
			else
				ev = m.db.events[ item.key ]
			end
			if ev and ev.startTime then
				local info = date( "*t", m.ts( ev.startTime ) )
				if info.year == current_year and info.month == current_month then
					table.insert( month_evts, item )
				end
			end
		end

		return month_evts
	end

	local function update_detail()
		if not detail_panel or not current_year or not current_month then
			return
		end

		local month_ts = time( {
			year = current_year,
			month = current_month,
			day = 1,
			hour = 12,
			min = 0,
			sec = 0
		} )
		local month_evts = get_current_month_events()
		local n = 0
		for _ in ipairs( month_evts ) do
			n = n + 1
		end

		detail_panel.subheader:SetText( m.format_local_date( month_ts, "month_year" ) )
		if n == 0 then
			detail_panel.count:SetText( "" )
			detail_panel.empty:Show()
		else
			detail_panel.count:SetText( m.L( n == 1 and "ui.event_count_one" or "ui.event_count_many", { count = n } ) )
			detail_panel.empty:Hide()
		end

		for i = 1, table.getn( detail_items ) do
			detail_items[ i ]:Hide()
		end

		local tf = m.time_format or "%H:%M"
		for i, item in ipairs( month_evts ) do
			local is_local = (item.source == "local")
			local ev
			if is_local then
				ev = m.db.local_events and m.db.local_events[ item.key ]
			else
				ev = m.db.events[ item.key ]
			end
			if not ev then
				break
			end

			local fr = detail_items[ i ]
			if not fr then
				fr = CreateFrame( "Frame", nil, detail_panel )
				fr:SetHeight( 54 )
				fr:EnableMouse( true )

				fr.bg = fr:CreateTexture( nil, "BACKGROUND" )
				fr.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
				fr.bg:SetAllPoints( fr )
				fr.bg:SetVertexColor( 0.08, 0.08, 0.08, 0.95 )

				fr.bar = fr:CreateTexture( nil, "ARTWORK" )
				fr.bar:SetTexture( SOLID )
				fr.bar:SetWidth( 4 )
				fr.bar:SetPoint( "TopLeft", fr, "TopLeft", 0, 0 )
				fr.bar:SetPoint( "BottomLeft", fr, "BottomLeft", 0, 0 )

				fr.hl = fr:CreateTexture( nil, "OVERLAY" )
				fr.hl:SetTexture( SOLID )
				fr.hl:SetAllPoints( fr )
				fr.hl:SetVertexColor( 1, 1, 1, 0 )

				fr.timeText = fr:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
				fr.timeText:SetPoint( "TopLeft", fr, "TopLeft", 10, -6 )
				fr.timeText:SetJustifyH( "Left" )
				fr.timeText:SetTextColor( 0.72, 0.72, 0.72 )

				fr.titleText = fr:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
				fr.titleText:SetPoint( "TopLeft", fr.timeText, "BottomLeft", 0, -2 )
				fr.titleText:SetPoint( "Right", fr, "Right", -8, 0 )
				fr.titleText:SetJustifyH( "Left" )
				fr.titleText:SetTextColor( 1, 0.82, 0 )

				fr.metaText = fr:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
				fr.metaText:SetPoint( "TopLeft", fr.titleText, "BottomLeft", 0, -2 )
				fr.metaText:SetJustifyH( "Left" )
				fr.metaText:SetTextColor( 0.6, 0.6, 0.6 )

				fr:SetScript( "OnEnter", function()
					fr.hl:SetVertexColor( 1, 1, 1, 0.05 )
				end )
				fr:SetScript( "OnLeave", function()
					fr.hl:SetVertexColor( 1, 1, 1, 0 )
				end )
				fr:SetScript( "OnMouseUp", function()
					if not fr.eventKey then
						return
					end

					if fr.eventSource == "local" then
						local local_event = m.db.local_events and m.db.local_events[ fr.eventKey ]
						selected_event_key = fr.eventKey
						if local_event and local_event.startTime then
							selected_day = normalize_day( local_event.startTime )
						end
						if m.LocalEventPopup then
							m.LocalEventPopup.show( fr.eventKey )
						end
						update_detail()
						return
					end

					local event_data = m.db.events[ fr.eventKey ]
					selected_event_key = fr.eventKey
					if event_data and event_data.startTime then
						selected_day = normalize_day( event_data.startTime )
					end
					if m.event_popup then
						m.event_popup.show( fr.eventKey )
					end
					update_detail()
				end )

				table.insert( detail_items, fr )
			end

			local rgb = m.get_event_color( ev )
			fr.bar:SetVertexColor( rgb[1], rgb[2], rgb[3], 1 )

			fr:ClearAllPoints()
			if i == 1 then
				fr:SetPoint( "TopLeft", detail_panel.count, "BottomLeft", 0, -12 )
			else
				fr:SetPoint( "TopLeft", detail_items[ i - 1 ], "BottomLeft", 0, -4 )
			end
			fr:SetPoint( "Right", detail_panel, "Right", -8, 0 )

			fr.timeText:SetText( date( "%d/%m ", m.ts( ev.startTime ) ) .. date( tf, m.ts( ev.startTime ) ) )
			fr.titleText:SetText( ev.title or "" )

			local su = m.L( "ui.no_signup_data" )
			if ev.signUps then
				local cnt = 0
				for _, s in ipairs( ev.signUps ) do
					if s.className ~= "Absence" then
						cnt = cnt + 1
					end
				end
				su = m.L( "ui.signups", { count = cnt } )
			elseif ev.signUpCount then
				su = m.L( "ui.signups", { count = ev.signUpCount } )
			end

			fr.metaText:SetText( su )
			fr.eventKey    = item.key
							fr.eventSource = item.source
			fr:Show()
		end
	end

	local function update_cell_events()
		local tf = m.time_format or "%H:%M"
		for i = 1, used_count do
			local cell = used_cells[ i ]
			if cell and cell.day_time then
				local dk = tostring( cell.day_time )
				local day_evts = events_by_day[ dk ] or {}
				local n = 0
				for _ in ipairs( day_evts ) do
					n = n + 1
				end

				for _, ch in ipairs( cell.chips ) do
					ch:Hide()
				end
				if cell.evDot then
					cell.evDot:Hide()
				end

				if n > 0 then
					if not cell.evDot then
						cell.evDot = cell:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
						cell.evDot:SetPoint( "TopRight", cell, "TopRight", -5, -18 )
						cell.evDot:SetJustifyH( "Right" )
						cell.evDot:SetTextColor( 1, 0.82, 0.1 )
					end
					cell.evDot:SetText( n > MAX_CHIPS and ("+" .. tostring( n - MAX_CHIPS )) or "" )
					cell.evDot:Show()

					local shown = 0
					for j, item in ipairs( day_evts ) do
						if shown >= MAX_CHIPS then
							break
						end

						local ev_is_local = (item.source == "local")
						local ev
						if ev_is_local then
							ev = m.db.local_events and m.db.local_events[ item.key ]
						else
							ev = m.db.events[ item.key ]
						end
						if ev then
							local chip = cell.chips[ j ]
							if not chip then
								chip = CreateFrame( "Frame", nil, cell )
								chip:SetHeight( 12 )
								chip:EnableMouse( true )
								chip:SetFrameStrata( cell:GetFrameStrata() )

								chip.bg = chip:CreateTexture( nil, "ARTWORK" )
								chip.bg:SetTexture( "Interface\\Buttons\\WHITE8x8" )
								chip.bg:SetAllPoints( chip )
								chip.bg:SetVertexColor( 0.04, 0.04, 0.04, 0.95 )

								chip.bar = chip:CreateTexture( nil, "ARTWORK" )
								chip.bar:SetTexture( SOLID )
								chip.bar:SetWidth( 5 )
								chip.bar:SetPoint( "TopLeft", chip, "TopLeft", 0, 0 )
								chip.bar:SetPoint( "BottomLeft", chip, "BottomLeft", 0, 0 )

								chip.lbl = chip:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
								chip.lbl:SetPoint( "Left", chip, "Left", 7, 0 )
								chip.lbl:SetPoint( "Right", chip, "Right", -1, 0 )
								chip.lbl:SetJustifyH( "Left" )
								chip.lbl:SetTextColor( 0.95, 0.95, 0.95 )

								chip:SetScript( "OnEnter", function()
									chip.bg:SetVertexColor( 0.14, 0.14, 0.14, 0.98 )
								end )
								chip:SetScript( "OnLeave", function()
									chip.bg:SetVertexColor( 0.04, 0.04, 0.04, 0.95 )
								end )

								cell.chips[ j ] = chip
							end

							chip:SetFrameLevel( cell:GetFrameLevel() + 3 )

							if ev_is_local then
								chip.bar:SetVertexColor( 0.6, 0.4, 1, 1 )
							else
								local rgb = m.get_event_color( ev )
								chip.bar:SetVertexColor( rgb[1], rgb[2], rgb[3], 1 )
							end

							local chip_title = truncate_cell_label( ev.title or "", 11 )
							chip.lbl:SetText( date( tf, m.ts( ev.startTime ) ) .. " " .. chip_title )
							chip.eventKey    = item.key
							chip.eventSource = item.source
							local icon_offset = (cell.reset_icon_rows and cell.reset_icon_rows > 0) and (cell.reset_icon_rows * 17) or 0
							chip:ClearAllPoints()
							chip:SetPoint( "TopLeft", cell, "TopLeft", 2, -(22 + icon_offset + shown * 12) )
							chip:SetPoint( "TopRight", cell, "TopRight", -2, -(22 + icon_offset + shown * 12) )
							chip:SetScript( "OnMouseUp", function()
								if not chip.eventKey then
									return
								end

								if chip.eventSource == "local" then
									local local_event = m.db.local_events and m.db.local_events[ chip.eventKey ]
									selected_event_key = chip.eventKey
									if local_event and local_event.startTime then
										selected_day = normalize_day( local_event.startTime )
									end
									if m.LocalEventPopup then
										m.LocalEventPopup.show( chip.eventKey )
									end
									update_detail()
									return
								end

								local event_data = m.db.events[ chip.eventKey ]
								selected_event_key = chip.eventKey
								if event_data and event_data.startTime then
									selected_day = normalize_day( event_data.startTime )
								end
								if m.event_popup then
									m.event_popup.show( chip.eventKey )
								end
								update_detail()
							end )
							chip:Show()
							shown = shown + 1
						end
					end

					cell:SetScript( "OnMouseUp", function()
						selected_day = normalize_day( cell.day_time )
						update_detail()
					end )
				else
					cell:SetScript( "OnMouseUp", nil )
				end
			end
		end
	end

	local function render_calendar()
		recycle_cells()
		if popup and popup.online_indicator then
			popup.online_indicator.update()
		end

		local month_ts = time( {
			year = current_year,
			month = current_month,
			day = 1,
			hour = 12,
			min = 0,
			sec = 0
		} )
		if popup then
			popup.month_label:SetText( m.format_local_date( month_ts, "month_year" ) )
		end

		for i = 1, COLS do
			if day_labels[ i ] then
				day_labels[ i ]:SetText( m.get_day_name( mod( i, 7 ) + 1, true ) )
			end
			if day_headers[ i ] then
				day_headers[ i ]:SetWidth( CELL_SIZE )
				day_headers[ i ]:ClearAllPoints()
				day_headers[ i ]:SetPoint( "TopLeft", popup, "TopLeft", BORDER_L + (i - 1) * CELL_STEP, -BORDER_T )
			end
		end

		local grid_start = get_month_grid_start( month_ts )
		local today = get_today()
		local TOTAL_CELLS = 42

		local innerH = DAY_LABEL_H + 6 * CELL_STEP + 1
		local frameH = BORDER_T + innerH + BORDER_B
		popup:SetHeight( frameH )
		if popup.parchment_set_inner_height then
			popup.parchment_set_inner_height( innerH )
		end
		if detail_panel then
			detail_panel:SetHeight( frameH - 32 )
		end

		local startY = -(BORDER_T + DAY_LABEL_H)
		local month_info = date( "*t", month_ts )

		for i = 1, TOTAL_CELLS do
			local col = math.mod( i - 1, COLS )
			local row = math.floor( (i - 1) / COLS )
			local day_time = normalize_day( grid_start + ((i - 1) * 86400) )
			local day_info = date( "*t", day_time )
			local isCurrent = day_info.month == month_info.month and day_info.year == month_info.year
			local isToday = day_time == today

			local cell = get_cell()
			local base_level = get_grid_base_frame_level()
			cell:SetFrameStrata( popup:GetFrameStrata() )
			cell:SetPoint( "TopLeft", popup, "TopLeft", BORDER_L + col * CELL_STEP, startY - row * CELL_STEP )
			cell.day_time = day_time
			cell.raid_resets = m.get_raid_resets_for_day( day_time )

			local function setBorders( r, g, b, a )
				for _, b2 in pairs( cell.borders ) do
					b2:SetVertexColor( r, g, b, a )
				end
			end

			if isToday then
				if not isCurrent then
					cell.bg:SetVertexColor( 0.45, 0.38, 0.28, 1 )
					setBorders( 0.35, 0.35, 0.35, 1 )
				elseif col == 5 or col == 6 then
					cell.bg:SetVertexColor( 0.75, 0.72, 0.6, 1 )
					setBorders( 0.5, 0.5, 0.52, 1 )
				else
					cell.bg:SetVertexColor( 0.75, 0.72, 0.6, 1 )
					setBorders( 0.5, 0.5, 0.52, 1 )
				end
				for _, g in pairs( cell.gold ) do
					g:Show()
				end
				cell.num:SetTextColor( 1, 0.9, 0.2 )
				cell:SetFrameLevel( base_level + 4 )
			elseif not isCurrent then
				cell.bg:SetVertexColor( 0.45, 0.38, 0.28, 1 )
				setBorders( 0.35, 0.35, 0.35, 1 )
				for _, g in pairs( cell.gold ) do
					g:Hide()
				end
				cell.num:SetTextColor( 0.42, 0.38, 0.3 )
				cell:SetFrameLevel( base_level )
			elseif col == 5 then
				cell.bg:SetVertexColor( 0.75, 0.72, 0.6, 1 )
				setBorders( 0.5, 0.5, 0.52, 1 )
				for _, g in pairs( cell.gold ) do
					g:Hide()
				end
				cell.num:SetTextColor( 1, 0.6, 0.2 )
				cell:SetFrameLevel( base_level + 1 )
			elseif col == 6 then
				cell.bg:SetVertexColor( 0.75, 0.72, 0.6, 1 )
				setBorders( 0.5, 0.5, 0.52, 1 )
				for _, g in pairs( cell.gold ) do
					g:Hide()
				end
				cell.num:SetTextColor( 1, 0.3, 0.3 )
				cell:SetFrameLevel( base_level + 1 )
			else
				cell.bg:SetVertexColor( 0.75, 0.72, 0.6, 1 )
				setBorders( 0.5, 0.5, 0.52, 1 )
				for _, g in pairs( cell.gold ) do
					g:Hide()
				end
				cell.num:SetTextColor( 0.9, 0.85, 0.7 )
				cell:SetFrameLevel( base_level + 1 )
			end

			cell.num:SetText( tostring( day_info.day ) )
			if (not m.should_show_raid_reset_icons or m.should_show_raid_reset_icons()) and cell.raid_resets and getn( cell.raid_resets ) > 0 then
				local visuals = m.get_raid_reset_day_visuals and m.get_raid_reset_day_visuals( cell.raid_resets ) or nil
				render_reset_icons( cell, visuals, isCurrent )
			else
				hide_reset_icon_slots( cell )
			end
			cell.reset_bg:Hide()
			cell.reset_dim:Hide()
			cell.reset_ribbon:Hide()
			cell.reset_border_top:Hide()
			cell.reset_border_left:Hide()
			cell.reset_shadow_bottom:Hide()
			cell.reset_shadow_right:Hide()
			cell:Show()
			used_count = used_count + 1
			used_cells[ used_count ] = cell
		end

		update_cell_events()
		update_detail()
	end

	local function create_frame()
		local frame = m.FrameBuilder.new()
			:name( "RaidCalendarPopupBlizzard" )
			:frame_style( "PARCHMENT" )
			:parchment( {
				tex_path = TEX,
				border_l = BORDER_L,
				border_r = BORDER_R,
				border_t = BORDER_T,
				border_b = BORDER_B,
				tex_coords = TC
			} )
			:frame_level( 80 )
			:width( CAL_W )
			:height( 685 )
			:movable()
			:close_button()
			:esc()
			:on_drag_stop( function( self )
				local point, _, rp, x, y = self:GetPoint()
				m.db.popup_calendar.position = { point = point, relative_point = rp, x = x, y = y }
			end )
			:build()

		if m.db.popup_calendar.position then
			local p = m.db.popup_calendar.position
			frame:ClearAllPoints()
			frame:SetPoint( p.point, UIParent, p.relative_point, p.x, p.y )
		end

		apply_ui_scale( frame )

		local close_btn = frame.btn_close or (frame.titlebar and frame.titlebar.btn_close)
		if close_btn then
			frame.btn_close = close_btn
			close_btn.tooltip = m.L and m.L( "ui.close_window" ) or "Close"
			close_btn:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
			close_btn:RegisterForDrag( "RightButton" )

			close_btn:ClearAllPoints()
			close_btn:SetPoint("CENTER", frame, "TOPRIGHT", -10, -31)

			close_btn:SetScript( "OnEnter", function()
				if close_btn.LockHighlight then
					close_btn:LockHighlight()
				end
				if GameTooltip then
					GameTooltip:SetOwner( close_btn, "ANCHOR_LEFT" )
					GameTooltip:SetText( close_btn.tooltip or "Close", 1, 0.82, 0 )
					GameTooltip:Show()
				end
			end )

			close_btn:SetScript( "OnLeave", function()
				if close_btn.UnlockHighlight then
					close_btn:UnlockHighlight()
				end
				if GameTooltip then
					GameTooltip:Hide()
				end
			end )

			close_btn:SetScript( "OnDragStart", function()
				frame:StartMoving()
			end )

			close_btn:SetScript( "OnDragStop", function()
				frame:StopMovingOrSizing()
				local point, _, rp, x, y = frame:GetPoint()
				m.db.popup_calendar.position = { point = point, relative_point = rp, x = x, y = y }
			end )

			close_btn:SetScript( "OnClick", function()
				if arg1 == "LeftButton" then
					if GameTooltip then
						GameTooltip:Hide()
					end
					frame:Hide()
					if detail_panel then
						detail_panel:Hide()
					end
				end
			end )
		end

		local settings = nil
		local pending_ui_theme

		local function refresh_settings_labels()
			if not settings then return end
			frame.btn_today:SetText( m.L( "actions.today" ) )
			detail_panel.header:SetText( m.L( "ui.month_events" ) )
			detail_panel.empty:SetText( m.L( "ui.no_events_month" ) )
			settings.lbl_tf:SetText( m.L( "ui.time_format" ) )
			settings.lbl_loc:SetText( m.L( "ui.language" ) )
			if settings.lbl_theme then settings.lbl_theme:SetText( m.L( "ui.ui_theme" ) ) end
			settings.btn_save:SetText( m.L( "actions.save" ) )
			settings.btn_welcome:SetText( m.L( "actions.welcome_popup" ) )
			settings.btn_disconnect:SetText( m.L( "actions.disconnect" ) )
			if settings.show_raid_resets then
				getglobal( settings.show_raid_resets:GetName() .. "Text" ):SetText( m.L( "ui.show_raid_resets" ) )
			end
			if settings.lbl_utc_offset then
				settings.lbl_utc_offset:SetText( m.L( "ui.wow_utc_offset" ) or "WoW UTC offset (s)" )
			end
			settings.time_format:SetItems( {
				{ value = "24", text = m.L( "options.time_format_24" ) },
				{ value = "12", text = m.L( "options.time_format_12" ) }
			} )
			settings.locale_flag:SetItems( (m.get_available_locales and m.get_available_locales()) or {
				{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
				{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Fran\195\167ais" }
			} )
		end

		local function on_save()
			local theme_to_apply = pending_ui_theme or (settings.dd_theme and settings.dd_theme.selected) or m.db.user_settings.ui_theme or "Original"
			local previous_theme = m.db.user_settings.ui_theme or "Original"
			local locale_changed = settings.locale_flag.selected ~= m.db.user_settings.locale_flag
			local tf_manually_changed = settings.time_format.selected ~= m.db.user_settings.time_format
			local selected_reset_icons = (settings.show_raid_resets and settings.show_raid_resets:GetChecked() == 1) and 1 or 0
			if settings.eb_utc_offset then
				m.db.user_settings.wow_utc_offset = tonumber( settings.eb_utc_offset:GetText() ) or 0
			end

			-- use_character_name est force a 1 (case a cocher supprimee)
			m.db.user_settings.use_character_name = 1
			m.db.user_settings.show_raid_reset_icons = selected_reset_icons
			m.db.user_settings.time_format = settings.time_format.selected
			m.db.user_settings.locale_flag = settings.locale_flag.selected or m.db.user_settings.locale_flag
			m.db.user_settings.ui_theme = theme_to_apply
			m.time_format = m.db.user_settings.time_format == "24" and "%H:%M" or "%I:%M %p"
			m.set_locale( m.db.user_settings.locale_flag )

			if locale_changed and not tf_manually_changed then
				local auto_tf = (m.db.user_settings.locale_flag == "frFR") and "24" or "12"
				m.db.user_settings.time_format = auto_tf
				m.time_format = auto_tf == "24" and "%H:%M" or "%I:%M %p"
				settings.time_format:SetSelected( auto_tf )
			end

			refresh_settings_labels()
			settings:Hide()

			if m.event_popup and m.event_popup.update then
				m.event_popup.update()
			end
			if m.sr_popup and m.sr_popup.update then
				m.sr_popup.update()
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

			render_calendar()
		end

		tex_left = frame.parchment_tex_left
		tex_right = frame.parchment_tex_right

		frame.month_label = frame:CreateFontString( nil, "OVERLAY", "GameFontNormalLarge" )
		frame.month_label:SetPoint( "Top", frame, "Top", 0, -13 )
		frame.month_label:SetJustifyH( "CENTER" )
		frame.month_label:SetTextColor( 1, 0.82, 0 )

		frame.btn_refresh = gui.tiny_button( frame, "R", nil, "#20F99F" )
		frame.btn_refresh.tooltip_key = "ui.refresh"
		frame.btn_refresh:SetPoint( "Right", frame.btn_close, "Left", 1, 0 )

		local loading_overlay = CreateFrame( "Frame", nil, frame )
		loading_overlay:SetAllPoints( frame )
		loading_overlay:SetFrameStrata( frame:GetFrameStrata() )
		loading_overlay:SetFrameLevel( frame:GetFrameLevel() + 50 )
		loading_overlay:EnableMouse( true )
		loading_overlay:Hide()

		local loading_bg = loading_overlay:CreateTexture( nil, "BACKGROUND" )
		loading_bg:SetTexture( SOLID )
		loading_bg:SetVertexColor( 0, 0, 0, 0.7 )
		loading_bg:SetAllPoints( loading_overlay )

		local loading_text = loading_overlay:CreateFontString( nil, "OVERLAY", "GameFontNormalLarge" )
		loading_text:SetPoint( "Center", loading_overlay, "Center", 0, 0 )
		loading_text:SetTextColor( 1, 0.82, 0 )
		loading_text:SetText( m.L( "ui.loading_events" ) or "Loading events..." )
		frame.loading_overlay = loading_overlay

		-- Bouton Refresh
		frame.btn_refresh:SetScript( "OnClick", function()
			frame.btn_refresh:Disable()
			if not m.debug_enabled then
				loading_overlay:Show()
			end
			m.msg.request_events( true )
			m.ace_timer.ScheduleTimer( M, function()
				frame.btn_refresh:Enable()
				loading_overlay:Hide()
			end, 30 )
		end )

		-- Bouton Settings
		frame.btn_settings = gui.tiny_button( frame, "S", nil, "#F3DF2B" )
		frame.btn_settings.tooltip_key = "ui.settings"
		frame.btn_settings:SetPoint( "Right", frame.btn_refresh, "Left", -5, 0 )

		-- Force text center
		if frame.btn_settings:GetFontString() then
		    local fs = frame.btn_settings:GetFontString()
		    fs:ClearAllPoints()
		    fs:SetPoint("CENTER", frame.btn_settings, "CENTER", 0, 0)
		    fs:SetJustifyH("CENTER")
		    fs:SetJustifyV("MIDDLE")
		end

		-- Bouton Nouvel evenement
		frame.btn_new_event = m.GuiElements.tiny_button( frame, "+", nil, "#00FFFF" )
		frame.btn_new_event.tooltip_key = "ui.new_event"
		frame.btn_new_event:SetPoint( "Right", frame.btn_settings, "Left", -2, 0 )

		-- Force text center
		if frame.btn_new_event:GetFontString() then
		    local fs = frame.btn_new_event:GetFontString()
		    fs:ClearAllPoints()
		    fs:SetPoint("CENTER", frame.btn_new_event, "CENTER", 0, 0)
		    fs:SetJustifyH("CENTER")
		    fs:SetJustifyV("MIDDLE")
		end

		frame.btn_new_event:SetScript( "OnClick", function()
			if m.EventManagePopup then
				m.EventManagePopup.show_create()
			end
		end )

		-- LED bot indicator
		frame.online_indicator = gui.create_online_indicator( frame, frame.btn_new_event )

		local bPrev = CreateFrame( "Button", nil, frame )
		bPrev:SetWidth( 20 )
		bPrev:SetHeight( 20 )
		bPrev:SetPoint( "CENTER", frame, "Top", -105, -21 )
		bPrev:EnableMouse( true )

		local tP = bPrev:CreateTexture( nil, "ARTWORK" )
		tP:SetTexture( TEX .. "UI-Calendar-Left-Arrow" )
		tP:SetTexCoord( TC.Arrow[ 1 ], TC.Arrow[ 2 ], TC.Arrow[ 3 ], TC.Arrow[ 4 ] )
		tP:SetAllPoints( bPrev )

		bPrev:SetScript( "OnEnter", function()
			tP:SetVertexColor( 1, 0.82, 0 )
		end )
		bPrev:SetScript( "OnLeave", function()
			tP:SetVertexColor( 1, 1, 1 )
		end )
		bPrev:SetScript( "OnClick", function()
			current_year, current_month = shift_month( current_year, current_month, -1 )
			render_calendar()
		end )

		local bNext = CreateFrame( "Button", nil, frame )
		bNext:SetWidth( 20 )
		bNext:SetHeight( 20 )
		bNext:SetPoint( "CENTER", frame, "Top", 105, -21 )
		bNext:EnableMouse( true )
		local tN = bNext:CreateTexture( nil, "ARTWORK" )
		tN:SetTexture( TEX .. "UI-Calendar-Right-Arrow" )
		tN:SetTexCoord( TC.Arrow[ 1 ], TC.Arrow[ 2 ], TC.Arrow[ 3 ], TC.Arrow[ 4 ] )
		tN:SetAllPoints( bNext )
		bNext:SetScript( "OnEnter", function()
			tN:SetVertexColor( 1, 0.82, 0 )
		end )
		bNext:SetScript( "OnLeave", function()
			tN:SetVertexColor( 1, 1, 1 )
		end )
		bNext:SetScript( "OnClick", function()
			current_year, current_month = shift_month( current_year, current_month, 1 )
			render_calendar()
		end )

		frame.btn_today = gui.create_button( frame, m.L( "actions.today" ), 80, function()
			local t = date( "*t" )
			current_year = t.year
			current_month = t.month
			selected_day = get_today()
			render_calendar()
		end )
		frame.btn_today:SetPoint( "TopLeft", frame, "TopLeft", 2, -19 )

		for i = 1, COLS do
			local hdr = CreateFrame( "Frame", nil, frame )
			hdr:SetWidth( CELL_SIZE )
			hdr:SetHeight( DAY_LABEL_H )
			hdr:SetPoint( "TopLeft", frame, "TopLeft", BORDER_L + (i - 1) * CELL_STEP, -BORDER_T )

			local hdrbg = hdr:CreateTexture( nil, "BACKGROUND" )
			hdrbg:SetTexture( TEX .. "UI-Calendar-Background" )
			hdrbg:SetTexCoord( TC.Bg[ 1 ], TC.Bg[ 2 ], TC.Bg[ 3 ], TC.Bg[ 4 ] )
			hdrbg:SetAllPoints()
			hdrbg:SetVertexColor( 0.65, 0.32, 0.08, 1 )

			if i < COLS then
				local sep = hdr:CreateTexture( nil, "ARTWORK" )
				sep:SetTexture( SOLID )
				sep:SetVertexColor( 0.5, 0.5, 0.52, 1 )
				sep:SetWidth( 1 )
				sep:SetPoint( "TopRight", hdr, "TopRight", 0, 0 )
				sep:SetPoint( "BottomRight", hdr, "BottomRight", 0, 0 )
			end

			local lbl = hdr:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
			lbl:SetAllPoints( hdr )
			lbl:SetJustifyH( "CENTER" )
			lbl:SetJustifyV( "MIDDLE" )

			if i == 6 then
				lbl:SetTextColor( 1, 0.6, 0.2 )
			elseif i == 7 then
				lbl:SetTextColor( 1, 0.3, 0.3 )
			else
				lbl:SetTextColor( 1, 0.9, 0.6 )
			end

			lbl:SetText( m.get_day_name( i, true ) )
			day_labels[ i ] = lbl
			day_headers[ i ] = hdr
		end

		local dp = CreateFrame( "Frame", nil, UIParent )
		dp:SetWidth( DETAIL_W )
		dp:SetHeight( 650 )
		dp:SetPoint( "TopLeft", frame, "TopRight", 0, -32 )
		dp:SetFrameStrata( "DIALOG" )
		dp:SetFrameLevel( 80 )
		apply_ui_scale( dp )
		dp:SetBackdrop( {
			bgFile = "Interface/Buttons/WHITE8x8",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		} )
		dp:SetBackdropColor( 0.03, 0.03, 0.04, 0.95 )
		detail_panel = dp

		dp.header = dp:CreateFontString( nil, "OVERLAY", "GameFontNormalLarge" )
		dp.header:SetPoint( "TopLeft", dp, "TopLeft", 12, -12 )
		dp.header:SetTextColor( 1, 0.82, 0 )
		dp.header:SetText( m.L( "ui.month_events" ) )

		dp.subheader = dp:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
		dp.subheader:SetPoint( "TopLeft", dp.header, "BottomLeft", 0, -4 )
		dp.subheader:SetTextColor( 0.92, 0.82, 0.35 )

		dp.count = dp:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
		dp.count:SetPoint( "TopLeft", dp.subheader, "BottomLeft", 0, -4 )
		dp.count:SetTextColor( 0.72, 0.72, 0.72 )

		dp.empty = dp:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
		dp.empty:SetPoint( "Center", dp, "Center", 0, 0 )
		dp.empty:SetTextColor( 0.5, 0.5, 0.5 )
		dp.empty:SetText( m.L( "ui.no_events_month" ) )
		dp.empty:Hide()

		settings = CreateFrame( "Frame", nil, frame )
		settings:SetPoint( "TopLeft", frame, "TopLeft", 5, -45 )
		settings:SetPoint( "Right", frame, "Right", -5, 0 )
		settings:SetHeight( 170 )
		settings:SetFrameStrata( "DIALOG" )
		settings:SetFrameLevel( 100 )
		settings:SetBackdrop( {
			bgFile = "Interface/Buttons/WHITE8x8",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		} )
		settings:SetBackdropColor( 0, 0, 0, 1 )
		settings:Hide()
		frame.settings = settings

		local settings_label_x = 10
		local settings_first_row_y = -20
		local settings_row_spacing = 32
		local settings_label_width = 105
		local settings_dropdown_x = settings_label_x + settings_label_width + 6

		local btn_welcome = gui.create_button( settings, m.L( "actions.welcome_popup" ) or "Welcome popup", 130, function()
			m.welcome_popup.show()
			frame:Hide()
		end )
		btn_welcome:SetPoint( "TopRight", settings, "TopRight", -10, settings_first_row_y )
		settings.btn_welcome = btn_welcome

		local btn_disconnect
		btn_disconnect = gui.create_button( settings, m.L( "actions.disconnect" ) or "Disconnect", 110, function()
			m.db.user_settings.discord_id = nil
			m.db.user_settings.channel_access = {}
			if settings.refresh_discord_ui then
				settings.refresh_discord_ui()
			end
		end )
		-- Meme position que btn_welcome : ils s'excluent mutuellement
		btn_disconnect:SetPoint( "TopRight", settings, "TopRight", -10, settings_first_row_y )
		btn_disconnect:Hide()
		settings.btn_disconnect = btn_disconnect

		local function refresh_discord_ui()
			if m.db.user_settings.discord_id and m.db.user_settings.discord_id ~= "" then
				btn_welcome:Hide()
				btn_disconnect:Show()
			else
				btn_welcome:Show()
				btn_disconnect:Hide()
			end
		end
		settings.refresh_discord_ui = refresh_discord_ui

		local btn_save = gui.create_button( settings, m.L( "actions.save" ) or "Save", 110, on_save )
		-- Ancre sur btn_welcome (toujours a la meme position, visible ou non)
		btn_save:SetPoint( "TopRight", btn_welcome, "TopRight", 0, -30 )
		settings.btn_save = btn_save

		local lbl_tf = settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_tf:SetWidth( settings_label_width )
		lbl_tf:SetJustifyH( "Left" )
		lbl_tf:SetPoint( "TopLeft", settings, "TopLeft", settings_label_x, settings_first_row_y )
		lbl_tf:SetText( m.L( "ui.time_format" ) )
		lbl_tf:SetTextColor( 1, 0.82, 0, 1 )
		settings.lbl_tf = lbl_tf

		local dd_tf = scroll_drop:New( settings, {
			default_text = "",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_tf:SetPoint( "TopLeft", settings, "TopLeft", settings_dropdown_x, settings_first_row_y + 2 )
		dd_tf:SetItems( {
			{ value = "24", text = m.L( "options.time_format_24" ) },
			{ value = "12", text = m.L( "options.time_format_12" ) }
		} )
		settings.time_format = dd_tf

		local lbl_loc = settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_loc:SetWidth( settings_label_width )
		lbl_loc:SetJustifyH( "Left" )
		lbl_loc:SetPoint( "TopLeft", settings, "TopLeft", settings_label_x, settings_first_row_y - settings_row_spacing )
		lbl_loc:SetText( m.L( "ui.language" ) )
		lbl_loc:SetTextColor( 1, 0.82, 0, 1 )
		settings.lbl_loc = lbl_loc

		local dd_loc = scroll_drop:New( settings, {
			default_text = m.L( "ui.select_language" ),
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_loc:SetPoint( "TopLeft", settings, "TopLeft", settings_dropdown_x, settings_first_row_y - settings_row_spacing + 2 )
		dd_loc:SetItems( (m.get_available_locales and m.get_available_locales()) or {
			{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
			{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Fran\195\167ais" }
		} )
		settings.locale_flag = dd_loc

		local lbl_theme = settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		lbl_theme:SetWidth( settings_label_width )
		lbl_theme:SetJustifyH( "Left" )
		lbl_theme:SetPoint( "TopLeft", settings, "TopLeft", settings_label_x, settings_first_row_y - (settings_row_spacing * 2) )
		lbl_theme:SetText( m.L( "ui.ui_theme" ) )
		lbl_theme:SetTextColor( 1, 0.82, 0, 1 )
		settings.lbl_theme = lbl_theme

		local dd_theme = scroll_drop:New( settings, {
			default_text = m.db.user_settings.ui_theme or "Original",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 100
		} )
		dd_theme:SetPoint( "TopLeft", settings, "TopLeft", settings_dropdown_x, settings_first_row_y - (settings_row_spacing * 2) + 2 )
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
		settings.dd_theme = dd_theme

		local cb_reset_icons = CreateFrame( "CheckButton", "RaidCalendarPopupShowRaidResetsBlizzard", settings, "UICheckButtonTemplate" )
		cb_reset_icons:SetWidth( 22 )
		cb_reset_icons:SetHeight( 22 )
		cb_reset_icons:SetPoint( "TopLeft", settings, "TopLeft", 300, settings_first_row_y - settings_row_spacing + 2 )
		getglobal( cb_reset_icons:GetName() .. "Text" ):SetText( m.L( "ui.show_raid_resets" ) )
		settings.show_raid_resets = cb_reset_icons

		local lbl_utc = settings:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
		lbl_utc:SetPoint( "TopLeft", settings, "TopLeft", settings_label_x, settings_first_row_y - (settings_row_spacing * 3) )
		lbl_utc:SetText( m.L( "ui.wow_utc_offset" ) or "WoW UTC offset (s)" )
		settings.lbl_utc_offset = lbl_utc
		local eb_utc = CreateFrame( "EditBox", "RaidCalendarUtcOffsetBlizzard", settings )
		eb_utc:SetWidth( 60 )
		eb_utc:SetHeight( 18 )
		eb_utc:SetPoint( "TopLeft", settings, "TopLeft", settings_label_x + 120, settings_first_row_y - (settings_row_spacing * 3) + 2 )
		eb_utc:SetAutoFocus( false )
		eb_utc:SetMaxLetters( 7 )
		eb_utc:SetText( tostring( m.db.user_settings.wow_utc_offset or 0 ) )
		eb_utc:SetFontObject( "GameFontHighlightSmall" )
		local eb_utc_bd = CreateFrame( "Frame", nil, eb_utc )
		eb_utc_bd:SetAllPoints()
		eb_utc_bd:SetBackdrop( { bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 } )
		eb_utc_bd:SetBackdropColor( 0, 0, 0, 0.85 )
		eb_utc_bd:SetBackdropBorderColor( 0.3, 0.3, 0.3, 1 )
		settings.eb_utc_offset = eb_utc

		-- La case "use_character_name" est supprimee, la valeur est forcee a 1 dans RaidCalendar.lua

		frame.btn_settings:SetScript( "OnClick", function()
			if settings:IsVisible() then
				settings:Hide()
			else
				settings.time_format:SetSelected( m.db.user_settings.time_format or "24" )
				settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
				if settings.show_raid_resets then
					settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 and 1 or nil )
				end
				if settings.eb_utc_offset then
					settings.eb_utc_offset:SetText( tostring( m.db.user_settings.wow_utc_offset or 0 ) )
				end
				pending_ui_theme = m.db.user_settings.ui_theme or "Original"
				if settings.dd_theme then
					settings.dd_theme:SetSelected( pending_ui_theme )
				end
				refresh_discord_ui()
				refresh_settings_labels()
				settings:Show()
			end
		end )

		-- NOTE: online_indicator refresh is handled by its own OnUpdate in GuiElements.
		-- No secondary OnUpdate needed here.

		frame:SetScript( "OnHide", function()
			if detail_panel then
				detail_panel:Hide()
			end
			if settings:IsVisible() then
				settings:Hide()
			end
			if m.close_all_popups then m.close_all_popups() end
		end )

		frame.refresh = function()
			render_calendar()
		end

		return frame
	end

	local auto_refresh_timer_cal = nil

	local function show()
		if not popup then
			popup = create_frame()
		end

		local t = date( "*t" )
		if not current_year then
			current_year = t.year
		end
		if not current_month then
			current_month = t.month
		end

		refresh_data( false )
		if table.getn( m.db.local_events or {} ) == 0 then
			request_local_events_once( false )
		end
		ensure_selected_day()

		popup:Show()
		if detail_panel then
			detail_panel:Show()
		end

		render_calendar()
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
					request_local_events_once( true )
				end
			end, 60 )
		end
	end

	local function hide()
		local_events_requested = false
		if auto_refresh_timer_cal and m.ace_timer then
			m.ace_timer.CancelTimer( m, auto_refresh_timer_cal )
			auto_refresh_timer_cal = nil
		end
		if popup then
			popup:Hide()
		end
		if detail_panel then
			detail_panel:Hide()
		end
	end

	local function toggle()
		if popup and popup:IsVisible() then
			hide()
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
			render_calendar()
		end
	end

	local function discord_response( success, user_id )
		if popup and popup:IsVisible() and popup.settings and popup.settings.refresh_discord_ui then
			if success then
				m.msg.authorize_user( user_id )
			end
		end
	end

	local function auth_response( user_id, success )
		if success and popup and popup.settings and popup.settings.refresh_discord_ui then
			popup.settings.refresh_discord_ui()
		end
	end

	local function update()
		if popup and popup:IsVisible() then
			if table.getn( m.db.local_events or {} ) > 0 then
				local_events_requested = false
			end
			if popup.loading_overlay then
				popup.loading_overlay:Hide()
			end
			if popup.btn_refresh then
				popup.btn_refresh:Enable()
			end
			refresh_data( true )
			render_calendar()
		end
	end

	local function sync_settings()
		if not popup then
			return
		end
		if popup.settings and popup.settings.time_format then
			popup.settings.time_format:SetSelected( m.db.user_settings.time_format )
		end
		if popup.settings and popup.settings.locale_flag then
			popup.settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
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

m.CalendarPopupBlizzard = M
return M
