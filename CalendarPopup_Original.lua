RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.CalendarPopupOriginal then return end

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
	local refresh
	local offset = 0
	local selected
	local events
	local frame_items = {}
	local rows = 5
	local gui = m.GuiElements
	local pending_ui_theme

	local function save_position( self )
		local point, _, relative_point, x, y = self:GetPoint()

		m.db.popup_calendar.position = {
			point = point,
			relative_point = relative_point,
			x = x,
			y = y
		}
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
		local l = m.L
		if not l then return end
		popup.settings.label_timeformat:SetText( l( "ui.time_format" ) )
		popup.settings.label_locale:SetText( l( "ui.language" ) )
		popup.settings.time_format:SetItems( {
			{ value = "24", text = l( "options.time_format_24" ) },
			{ value = "12", text = l( "options.time_format_12" ) }
		} )
		popup.settings.locale_flag:SetItems( (m.get_available_locales and m.get_available_locales()) or {
			{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
			{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Français" }
		} )
		popup.settings.btn_save:SetText( l( "actions.save" ) )
		popup.settings.btn_welcome:SetText( l( "actions.welcome_popup" ) )
		popup.settings.btn_disconnect:SetText( l( "actions.disconnect" ) )
		if popup.settings.show_raid_resets then
			getglobal( popup.settings.show_raid_resets:GetName() .. "Text" ):SetText( l( "ui.show_raid_resets" ) )
		end
		if popup.settings.lbl_theme then popup.settings.lbl_theme:SetText( l( "ui.ui_theme" ) ) end
		popup.btn_refresh.tooltip = l( "ui.refresh" )
		popup.btn_settings.tooltip = l( "ui.settings" )
	end

	local function on_save_settings()
		local selected_theme = ( popup.settings and popup.settings.pending_ui_theme ) or pending_ui_theme or ( popup.settings.dd_theme and popup.settings.dd_theme.selected ) or m.db.user_settings.ui_theme or "Original"
		local theme_changed = selected_theme ~= ( m.db.user_settings.ui_theme or "Original" )

		-- use_character_name est force a 1 (case a cocher supprimee)
		m.db.user_settings.use_character_name = 1
		if popup.settings.show_raid_resets then
			m.db.user_settings.show_raid_reset_icons = popup.settings.show_raid_resets:GetChecked() and 1 or 0
		end
		m.db.user_settings.time_format = popup.settings.time_format.selected
		m.time_format = m.db.user_settings.time_format == "24" and "%H:%M" or "%I:%M %p"
		local locale_changed = popup.settings.locale_flag and
			popup.settings.locale_flag.selected and
			popup.settings.locale_flag.selected ~= m.db.user_settings.locale_flag
		if popup.settings.locale_flag and popup.settings.locale_flag.selected then
			m.db.user_settings.locale_flag = popup.settings.locale_flag.selected
			if m.set_locale then m.set_locale( m.db.user_settings.locale_flag ) end
		end
		-- Auto time format: fr->24h, en->12h (unless user manually changed it this save)
		local tf_manually_changed = popup.settings.time_format.selected ~= m.db.user_settings.time_format
		if locale_changed and not tf_manually_changed then
			local auto_tf = (m.db.user_settings.locale_flag == "frFR") and "24" or "12"
			m.db.user_settings.time_format = auto_tf
			m.time_format = auto_tf == "24" and "%H:%M" or "%I:%M %p"
			popup.settings.time_format:SetSelected( auto_tf )
		end
		refresh_settings_labels()

		if theme_changed then
			m.db.user_settings.ui_theme = selected_theme
			popup.settings.pending_ui_theme = nil
			pending_ui_theme = nil
			if m.calendar_popup then
				m.calendar_popup.hide()
			end
			m.calendar_popup_instances = m.calendar_popup_instances or {}
			if not m.calendar_popup_instances[ selected_theme ] then
				local mod = m[ "CalendarPopup" .. selected_theme ] or m.CalendarPopupOriginal
				m.calendar_popup_instances[ selected_theme ] = mod.new()
			end
			m.calendar_popup = m.calendar_popup_instances[ selected_theme ]
			if m.calendar_popup.sync_settings then
				m.calendar_popup.sync_settings()
			end
			m.calendar_popup.show()
			return
		end

		popup.settings:Hide()
		popup:SetHeight( 250 )
		refresh()
		-- Refresh EventPopup and SRPopup if open so their texts update immediately
		if m.event_popup and m.event_popup.update then m.event_popup.update() end
		if m.sr_popup and m.sr_popup.update then m.sr_popup.update() end
	end

	-- position_settings_checkbox supprimee (case a cocher supprimee, use_character_name force a 1)
	---@param parent Frame
	---@return Frame
	local function create_item( parent )
		---@class CalendarEventFrame: Button
		local frame = m.FrameBuilder.new()
				:type( "Button" )
				:parent( parent )
				:frame_style( "NONE" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0.1, 0.1, 0.1, 0.9 )
				:point( "Left", parent, "Left", 4, 0 )
				:width( 485 )
				:height( 40 )
				:build()

		frame:SetHighlightTexture( "Interface\\QuestFrame\\UI-QuestTitleHighlight" )

        -- Separator line between events
        local separator = frame:CreateTexture(nil, "OVERLAY")
        separator:SetTexture("Interface/Buttons/WHITE8x8")
        separator:SetHeight(1)
        separator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        separator:SetVertexColor(0.3, 0.3, 0.3, 0.6)

		frame:SetScript( "OnClick", function()
			if not events or not frame.index then return end
			local item = events[ frame.index ]
			if not item then return end
			-- Event local : ouvrir LocalEventPopup
			if item.source == "local" then
				if selected == frame.index then
					selected = nil
					if m.LocalEventPopup then m.LocalEventPopup.hide() end
				else
					selected = frame.index
					if m.LocalEventPopup then m.LocalEventPopup.show( item.key ) end
				end
				refresh()
				return
			end
			if m.api.IsShiftKeyDown() then
				local event_data = m.db.events[ item.key ]
				if event_data then
					local raid_link = "|cffffffff|Hraidcal:event:" .. item.key .. "|h[" .. event_data.title .. "]|h|r"
					m.api.ChatFrameEditBox:Insert( raid_link )
				end
				return
			end
			if selected == frame.index then
				selected = nil
				m.event_popup.hide()
			else
				selected = frame.index
				m.event_popup.show( item.key )
			end

			refresh()
		end )

		local selected_tex = frame:CreateTexture( nil, "ARTWORK" )
		selected_tex:SetTexture( "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" )
		selected_tex:SetAllPoints( frame )
		selected_tex:SetVertexColor( 0.3, 0.3, 1, 0.6 )
		selected_tex:Hide()

		local color_bar = frame:CreateTexture( nil, "ARTWORK" )
		color_bar:SetWidth( 2 )
		color_bar:SetHeight( 40 )
		color_bar:SetTexture( "Interface/Buttons/WHITE8x8" )
		color_bar:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )
		color_bar:SetVertexColor( 0, 0, 0, 0 )


		local title = frame:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		title:SetPoint( "TopLeft", frame, "TopLeft", 5, -2 )
		title:SetWidth( 260 )
		title:SetHeight( 35 )
		title:SetTextColor( NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b )
		title:SetFont( "Interface\\AddOns\\RaidCalendar\\assets\\Myriad-Pro.ttf", 13, "OUTLINE" )
		title:SetJustifyH( "Left" )
		title:SetJustifyV( "Middle" )

		local date_label = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_date.tga", 85, 14 )
		date_label:SetPoint( "TopRight", frame, "TopRight", 0, -3 )

		local time_label = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_time.tga", 85, 14 )
		time_label:SetPoint( "TopRight", frame, "TopRight", 0, -21 )

		local time_offset = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_hourglass.tga", 100, 14 )
		time_offset:SetPoint( "TopRight", date_label, "TopLeft", -5, 0 )

		local signups_label = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_signups.tga", 100, 14 )
		signups_label:SetPoint( "TopRight", time_label, "TopLeft", -5, 0 )

		local sr_frame = CreateFrame( "Button", nil, frame )
		sr_frame:SetPoint( "TopRight", time_offset, "TopLeft", -5, -6 )
		sr_frame:SetWidth( 20 )
		sr_frame:SetHeight( 20 )
		sr_frame:SetNormalTexture( "Interface\\AddOns\\RaidCalendar\\assets\\raidres.tga" )
		sr_frame:SetScript( "OnEnter", function()
			sr_frame:GetNormalTexture():SetBlendMode( "ADD" )
			frame:LockHighlight()
		end )
		sr_frame:SetScript( "OnLeave", function()
			sr_frame:GetNormalTexture():SetBlendMode( "BLEND" )
			frame:UnlockHighlight()
		end )

		sr_frame:SetScript( "OnClick", function()
			if m.api.IsShiftKeyDown() then
				local raid_link = "|cffffffff|Hraidcal:sr:" .. events[ frame.index ].key .. "|h[SR]|h|r"
				m.api.ChatFrameEditBox:Insert( raid_link )
				return
			end
			m.sr_popup.toggle( events[ frame.index ].key )
		end )

		---@param select boolean
		frame.set_selected = function( select )
			if select then
				selected_tex:Show()
			else
				selected_tex:Hide()
			end
		end

		frame.set_item = function( index )
			frame.index = index
			local item = events[ index ]
			local is_local = (item.source == "local")
			local event
			if is_local then
				event = m.db.local_events and m.db.local_events[ item.key ]
			else
				event = m.db.events[ item.key ]
			end
			if not event then return end

			if is_local then
				-- Couleur violette pour les events locaux
				color_bar:SetVertexColor( 0.6, 0.4, 1, 1 )
			else
				local rgb = m.get_event_color( event )
				color_bar:SetVertexColor( rgb[1], rgb[2], rgb[3], 1 )
			end

			title:SetText( event.title or "" )
			date_label.set( date( "%d. %b %Y", event.startTime ) )
			time_label.set( date( m.time_format, event.startTime ) )

			local diff = event.startTime - time( date( "*t" ) )
			time_offset.set( m.format_time_difference( diff ) )
			if diff < 0 then
				time_offset.icon:SetVertexColor( 1, 0, 0, 1 )
			else
				time_offset.icon:SetVertexColor( 1, 1, 1, 1 )
			end

			if not is_local and event.srId then
				sr_frame:Show()
				if event.sr and event.sr.reservations then
					local cnt = 0
					for _, res in ipairs( event.sr.reservations ) do
						if res.character.name == m.player then
							cnt = cnt + 1
						end
					end
					if cnt == event.sr.reservationLimit then
						sr_frame:GetNormalTexture():SetVertexColor( 0, 1, 0, 1 )
					else
						sr_frame:GetNormalTexture():SetVertexColor( 1, 1, 1, 1 )
					end
				else
					sr_frame:GetNormalTexture():SetVertexColor( 1, 1, 1, 1 )
				end
			else
				sr_frame:Hide()
			end
			if is_local then sr_frame:Hide() end

			local signed_up = false
			if not is_local and event.signUps then
				local signups = 0
				for _, v in ipairs( event.signUps ) do
					if v.className ~= "Absence" then
						signups = signups + 1
					end
					if m.db.user_settings.discord_id and m.db.user_settings.discord_id == v.userId then
						signed_up = true
					end
				end
				signups_label.set( m.L and m.L( "ui.signups", { count = signups } ) or (tostring( signups ) .. " " .. (m.L( "ui.signups_short" ) or "signups")) )
			elseif event.signUpCount then
				signups_label.set( m.L and m.L( "ui.signups", { count = event.signUpCount } ) or (event.signUpCount .. " " .. (m.L( "ui.signups_short" ) or "signups")) )
			end

			if signed_up then
				signups_label.icon:SetVertexColor( 0, 1, 0, 1 )
			else
				signups_label.icon:SetVertexColor( 1, 1, 1, 1 )
			end

			frame:Show()
		end

				-- Bouton Nouvel evenement
		frame.btn_new_event = m.GuiElements.tiny_button( frame, "+", nil, "#2e7d32" )
		frame.btn_new_event.tooltip_key = "ui.new_event"
		frame.btn_new_event:SetPoint( "TopRight", frame, "TopRight", -34, -4 )
		frame.btn_new_event:SetScript( "OnClick", function()
			if m.EventManagePopup then
				m.EventManagePopup.show_create()
			end
		end )
		return frame
	end

	local function create_frame()
		---@class CalendarFrame: BuilderFrame
		local frame = m.FrameBuilder.new()
				:name( "RaidCalendarPopupOriginal" )
				:title( string.format( "Raid Calendar v%s", m.version ) )
				:frame_style( "TOOLTIP" )
				:frame_level( 80 )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 0.8 )
				:close_button()
				:width( 530 )
				:height( 250 )
				:movable()
				:esc()
				:on_drag_stop( save_position )
				:build()

		if m.db.popup_calendar.position then
			local p = m.db.popup_calendar.position
			frame:ClearAllPoints()
			frame:SetPoint( p.point, UIParent, p.relative_point, p.x, p.y )
		end

		---
		--- Titlebar buttons
		---
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

		frame.btn_settings = m.GuiElements.tiny_button( frame, "S", nil, "#F3DF2B" )
		frame.btn_settings.tooltip_key = "ui.settings"
		frame.btn_settings:SetPoint( "Right", frame.btn_refresh, "Left", 2, 0 )
		frame.btn_settings:SetScript( "OnClick", function()
			if frame.settings:IsVisible() then
				frame.settings:Hide()
				frame:SetHeight( 250 )
			else
				frame.settings.time_format:SetSelected( m.db.user_settings.time_format )
				if frame.settings.locale_flag then
					frame.settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
				end
				pending_ui_theme = m.db.user_settings.ui_theme or "Original"
				frame.settings.pending_ui_theme = pending_ui_theme
				if frame.settings.dd_theme then
					frame.settings.dd_theme:SetSelected( pending_ui_theme )
				end
				if frame.settings.refresh_discord_ui then
					frame.settings.refresh_discord_ui()
				end
				refresh_settings_labels()
				frame.settings:Show()
				frame:SetHeight( 425 )
			end
		end )

		frame.online_indicator = gui.create_online_indicator( frame, frame.btn_settings )
		---
		--- Events
		---
		local border_events = m.FrameBuilder.new()
				:parent( frame )
				:point( "TopLeft", frame, "TopLeft", 10, -32 )
				:point( "Right", frame, "Right", -10, 0 )
				:height( 208 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 1 )
				:build()

		border_events:EnableMouseWheel( true )
		border_events:SetScript( "OnMouseWheel", function()
			local value = frame.scroll_bar:GetValue() - arg1
			frame.scroll_bar:SetValue( value )
		end )
		frame.border_events = border_events

		local bg = border_events:CreateTexture( nil, "ARTWORK" )
		bg:SetTexture( "Interface\\AddOns\\RaidCalendar\\assets\\background.tga" )
		bg:SetWidth( 190 )
		bg:SetHeight( 190 )
		bg:SetPoint( "Center", border_events, "Center", 0, 0 )

		local scroll_bar = CreateFrame( "Slider", "RaidCalendarScrollBarOriginal", border_events, "UIPanelScrollBarTemplate" )
		frame.scroll_bar = scroll_bar
		scroll_bar:SetPoint( "TopRight", border_events, "TopRight", -5, -20 )
		scroll_bar:SetPoint( "Bottom", border_events, "Bottom", 0, 20 )
		scroll_bar:SetMinMaxValues( 0, 0 )
		scroll_bar:SetValueStep( 1 )
		scroll_bar:SetScript( "OnValueChanged", function()
			offset = arg1
			refresh()
		end )

		for i = 1, rows do
			local item = create_item( border_events )
			item:SetPoint( "Top", border_events, "Top", 4, ((i - 1) * -40) - 4 )
			table.insert( frame_items, item )
		end

		---
		--- Settings
		---
		frame.settings = m.FrameBuilder.new()
				:parent( frame )
				:point( "TopLeft", border_events, "BottomLeft", 0, -6 )
				:point( "Right", frame, "Right", -10, 10 )
				:height( 130 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 1 )
				:hidden()
				:build()

		-- Layout:
		-- Left col (x=8):  labels + dropdowns stacked
		-- Right col (x=-10 from right): buttons stacked from bottom
		-- Row 1: checkbox (full width)
		-- Row 2: Discord label + editbox + Verify  (OR Disconnect btn when connected)
		-- Row 3: Format de l'heure  [dd_timeformat]
		-- Row 4: Langue             [dd_locale]
		-- Row 5: UI Theme           [dd_theme]      <- injected by ThemeSelector
		-- Buttons: Save / Welcome popup / Disconnect (right col, bottom up)

		-- (case use_character_name supprimee, valeur forcee a 1 dans RaidCalendar.lua)

		-- Row 2: Discord
		local discord_label = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		discord_label:SetPoint( "TopLeft", frame.settings, "TopLeft", 8, -34 )
		discord_label:SetText( m.L and m.L( "ui.discord_name_id" ) or m.L( "ui.discord" ) or "Discord:" )
		frame.settings.discord_label = discord_label

		local discord_box = CreateFrame( "EditBox", nil, frame.settings )
		discord_box:SetAutoFocus( false ); discord_box:SetMultiLine( false )
		discord_box:SetFontObject( GameFontHighlightSmall )
		discord_box:SetHeight( 18 ); discord_box:SetWidth( 150 )
		discord_box:SetPoint( "Left", discord_label, "Right", 6, 0 )
		discord_box:SetBackdrop( { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left=2, right=2, top=2, bottom=2 } } )
		discord_box:SetBackdropColor( 0.02, 0.02, 0.02, 0.95 )
		discord_box:SetTextInsets( 4, 4, 0, 0 )
		discord_box:SetScript( "OnEscapePressed", function() discord_box:ClearFocus() end )
		discord_box:SetScript( "OnEditFocusGained", function() discord_box:HighlightText() end )
		if m.db.user_settings.discord_id then discord_box:SetText( m.db.user_settings.discord_id ) end
		frame.settings.discord = discord_box

		local btn_lookup_orig = gui.create_button( frame.settings, m.L and m.L( "actions.verify" ) or "Verify", 70, function()
			local name = discord_box:GetText()
			if name and name ~= "" then m.msg.find_discord_id( name ) end
		end )
		btn_lookup_orig:SetPoint( "Left", discord_box, "Right", 6, 0 )
		frame.settings.btn_loopup = btn_lookup_orig

		local discord_response_orig = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		discord_response_orig:SetPoint( "Left", btn_lookup_orig, "Right", 6, 0 )
		discord_response_orig:SetTextColor( 0.5, 0.9, 0.5 )
		discord_response_orig:SetText( "" )
		frame.settings.discord_response = discord_response_orig

		local btn_disconnect_orig
		local function refresh_discord_ui_orig()
			if m.db.user_settings.discord_id and m.db.user_settings.discord_id ~= "" then
				discord_box:Hide(); btn_lookup_orig:Hide(); discord_label:Hide()
				discord_response_orig:SetText( "" )
				if btn_disconnect_orig then btn_disconnect_orig:Show() end
				if frame.settings.btn_welcome then frame.settings.btn_welcome:Hide() end
			else
				discord_box:Show(); btn_lookup_orig:Show(); btn_lookup_orig:Enable(); discord_label:Show()
				discord_box:SetText( "" )
				if btn_disconnect_orig then btn_disconnect_orig:Hide() end
				if frame.settings.btn_welcome then frame.settings.btn_welcome:Show() end
			end
		end
		frame.settings.refresh_discord_ui = refresh_discord_ui_orig

		local function align_theme_selector_row()
			local settings = frame and frame.settings
			if not settings then
				return
			end

			local theme_label = settings.label_theme
			if not theme_label then
				local regions = { settings:GetRegions() }
				for _, region in ipairs( regions ) do
					if region and region.GetObjectType and region:GetObjectType() == "FontString" then
						local txt = region.GetText and region:GetText() or nil
						if txt == m.L( "ui.ui_theme" ) or "UI Theme" then
							theme_label = region
							settings.label_theme = region
							break
						end
					end
				end
			end

			if theme_label then
				theme_label:ClearAllPoints()
				theme_label:SetPoint( "TopLeft", settings, "TopLeft", 10, -84 )
				theme_label:SetJustifyH( "LEFT" )
			end

			if settings.dd_theme then
				settings.dd_theme:ClearAllPoints()
				settings.dd_theme:SetPoint( "TopLeft", settings, "TopLeft", 121, -82 )
			end
		end

		-- Row 3: Format de l'heure
		local label_timeformat = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		label_timeformat:SetPoint( "TopLeft", frame.settings, "TopLeft", 10, -20 )
		label_timeformat:SetText( m.L and m.L( "ui.time_format" ) or m.L( "ui.time_format" ) or "Time format" )
		frame.settings.label_timeformat = label_timeformat

		local dd_timeformat = scroll_drop:New( frame.settings, {
			default_text = "",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 110
		} )
		dd_timeformat:SetPoint( "TopLeft", frame.settings, "TopLeft", 121, -18 )
		dd_timeformat:SetItems( {
			{ value = "24", text = m.L and m.L( "options.time_format_24" ) or "24-hour" },
			{ value = "12", text = m.L and m.L( "options.time_format_12" ) or "12-hour" }
		} )
		frame.settings.time_format = dd_timeformat

		-- Row 4: Langue
		local label_locale = frame.settings:CreateFontString( nil, "ARTWORK", "RCFontNormal" )
		label_locale:SetPoint( "TopLeft", frame.settings, "TopLeft", 10, -52 )
		label_locale:SetText( m.L and m.L( "ui.language" ) or "Language" )
		frame.settings.label_locale = label_locale

		local dd_locale = scroll_drop:New( frame.settings, {
			default_text = m.L and m.L( "ui.select_language" ) or "Language",
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			search = false,
			width = 110
		} )
		dd_locale:SetPoint( "TopLeft", frame.settings, "TopLeft", 121, -50 )
		dd_locale:SetItems( (m.get_available_locales and m.get_available_locales()) or {
			{ value = "enUS", text = m.locale_native_name and m.locale_native_name( "enUS" ) or "English" },
			{ value = "frFR", text = m.locale_native_name and m.locale_native_name( "frFR" ) or "Français" }
		} )
		frame.settings.locale_flag = dd_locale

		local cb_reset_icons = CreateFrame( "CheckButton", "RaidCalendarPopupShowRaidResetsOriginal", frame.settings, "UICheckButtonTemplate" )
		cb_reset_icons:SetWidth( 22 )
		cb_reset_icons:SetHeight( 22 )
		cb_reset_icons:SetPoint( "TopLeft", frame.settings, "TopLeft", 10, -84 )
		getglobal( cb_reset_icons:GetName() .. "Text" ):SetText( m.L( "ui.show_raid_resets" ) )
		frame.settings.show_raid_resets = cb_reset_icons

		local btn_welcome = gui.create_button( frame.settings, m.L and m.L( "actions.welcome_popup" ) or "Welcome popup", 130, function()
			m.welcome_popup.show()
			popup:Hide()
		end )
		btn_welcome:SetPoint( "TopRight", frame.settings, "TopRight", -10, -20 )
		frame.settings.btn_welcome = btn_welcome

		-- Disconnect (meme position que btn_welcome, exclusion mutuelle)
		btn_disconnect_orig = gui.create_button( frame.settings,
			m.L and m.L( "actions.disconnect" ) or "Disconnect", 110,
			function()
				m.db.user_settings.discord_id = nil
				m.db.user_settings.channel_access = {}
				discord_response_orig:SetText( "" )
				btn_lookup_orig:Enable()
				refresh_discord_ui_orig()
			end )
		btn_disconnect_orig:SetPoint( "TopRight", frame.settings, "TopRight", -10, -20 )
		btn_disconnect_orig:Hide()
		frame.settings.btn_disconnect = btn_disconnect_orig

		-- Boutons en haut a droite, empiles vers le bas
		local btn_save = gui.create_button( frame.settings, m.L and m.L( "actions.save" ) or "Save", 110, on_save_settings )
		btn_save:SetPoint( "TopRight", btn_welcome, "TopRight", 0, -30 )
		frame.settings.btn_save = btn_save

		-- UI Theme: meme ligne que Format de l'heure et Langue (colonne gauche)
		if m.ThemeSelector then
			m.ThemeSelector.inject( frame.settings, dd_locale )
		end
		align_theme_selector_row()
		gui.pfui_skin( frame )

		frame:SetScript( "OnHide", function()
			if m.close_all_popups then m.close_all_popups() end
		end )

		return frame
	end

	---@param refresh_data boolean?
	function refresh( refresh_data )
		popup.online_indicator.update()
		if m.debug_enabled then popup.btn_refresh:Enable() end

		popup.settings.time_format:SetSelected( m.db.user_settings.time_format )
		if popup.settings.locale_flag then
			popup.settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
		end
		if popup.settings.show_raid_resets then
			popup.settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 )
		end

		if not events or refresh_data then
			events = {}
			for k, v in pairs( m.db.events ) do
				table.insert( events, { key = k, value = v.startTime, source = "raidhelper" } )
			end
			-- Inclure les evenements locaux
			for k, v in pairs( m.db.local_events or {} ) do
				table.insert( events, { key = k, value = v.startTime, source = "local" } )
			end

			table.sort( events, function( a, b )
				return a.value < b.value
			end )

			local max = math.max( 0, getn( events ) - rows )
			popup.scroll_bar:SetMinMaxValues( 0, max )

			if getn( events ) == 0 then
				m.msg.request_events()
			end
		end

		for i = 1, rows do
			if events[ i + offset ] then
				frame_items[ i ].set_item( i + offset )
				frame_items[ i ].set_selected( selected == i + offset )
			else
				frame_items[ i ]:Hide()
			end
		end

		local max = math.max( 0, getn( events ) - rows )
		local value = math.min( max, popup.scroll_bar:GetValue() )

		popup.scroll_bar:SetValue( value )
		if value == 0 then
			m.api[ "RaidCalendarScrollBarOriginalScrollUpButton" ]:Disable()
		else
			m.api[ "RaidCalendarScrollBarOriginalScrollUpButton" ]:Enable()
		end

		if value == max then
			m.api[ "RaidCalendarScrollBarOriginalScrollDownButton" ]:Disable()
		else
			m.api[ "RaidCalendarScrollBarOriginalScrollDownButton" ]:Enable()
		end
	end

	local function show()
		if not popup then
			popup = create_frame()
		end

		selected = nil
		popup:Show()
		refresh()
	end

	local function hide()
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
		if popup and popup:IsVisible() then
			selected = nil
			refresh()
		end
	end

	local function discord_response( success, user_id )
		if popup and popup:IsVisible() then
			popup.settings.btn_loopup:Enable()
			if success then
				local name = popup.settings.discord:GetText()
				popup.settings.discord_response:SetText( m.L and m.L( "ui.name_found", { name = name } ) or ("UserID for \"" .. name .. "\" found") )
				popup.settings.discord:SetText( user_id )
			else
				popup.settings.discord_response:SetText( m.L and m.L( "ui.name_not_found" ) or "Name not found." )
			end
		end
	end

	local function update()
		if popup and popup:IsVisible() then
			refresh( true )
		end
	end

	local function sync_settings()
		if not popup then return end
		if popup.settings.time_format then
			popup.settings.time_format:SetSelected( m.db.user_settings.time_format )
		end
		if popup.settings.locale_flag then
			popup.settings.locale_flag:SetSelected( m.db.user_settings.locale_flag or "enUS" )
		end
		if popup.settings.show_raid_resets then
			popup.settings.show_raid_resets:SetChecked( m.db.user_settings.show_raid_reset_icons == 1 )
		end
		pending_ui_theme = m.db.user_settings.ui_theme or "Original"
		if popup.settings.dd_theme then
			popup.settings.pending_ui_theme = pending_ui_theme
			popup.settings.dd_theme:SetSelected( pending_ui_theme )
		end
		if popup.settings.label_theme or popup.settings.dd_theme then
			local settings = popup.settings
			local theme_label = settings.label_theme
			if not theme_label then
				local regions = { settings:GetRegions() }
				for _, region in ipairs( regions ) do
					if region and region.GetObjectType and region:GetObjectType() == "FontString" then
						local txt = region.GetText and region:GetText() or nil
						if txt == m.L( "ui.ui_theme" ) or "UI Theme" then
							theme_label = region
							settings.label_theme = region
							break
						end
					end
				end
			end
			if theme_label then
				theme_label:ClearAllPoints()
				theme_label:SetPoint( "TopLeft", settings, "TopLeft", 10, -84 )
				theme_label:SetJustifyH( "LEFT" )
			end
			if settings.dd_theme then
				settings.dd_theme:ClearAllPoints()
				settings.dd_theme:SetPoint( "TopLeft", settings, "TopLeft", 121, -82 )
			end
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

m.CalendarPopupOriginal = M
return M
