RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.EventPopup then return end

---@class EventPopup
---@field show fun( event_id: string )
---@field hide fun()
---@field toggle fun( event_id: string?)
---@field is_visible fun(): boolean
---@field update fun( event_id: string? )
---@field online_status fun( online: boolean )

---@class Signup
---@field id number
---@field userid string
---@field position number
---@field name string
---@field entryTime number
---@field status string
---@field specName string
---@field className string
---@field roleName string

local M = {}

---@type ScrollDropdown
local scroll_drop = LibStub:GetLibrary( "LibScrollDrop-1.3" )

function M.new()
	local popup
	local event
	local signup_id
	local frame_cache = {}
	local guild_online_cache = {}
	local refresh
	local gui = m.GuiElements

	local buttons = { "Signup", "Bench", "Late", "Tentative", "Absence", "Change Spec" }
	-- Pre-computed mapping: "Signup" → "btn_signup", "Change Spec" → "btn_change_spec", etc.
	-- Avoids repeated string.gsub(string.lower(v)) calls inside every refresh/click handler.
	local btn_keys = {}
	for _, v in ipairs( buttons ) do
		btn_keys[ v ] = "btn_" .. string.gsub( string.lower( v ), "%s", "_" )
	end

	local function save_position( self )
		local point, _, relative_point, x, y = self:GetPoint()

		m.db.popup_event.position = {
			point = point,
			relative_point = relative_point,
			x = x,
			y = y
		}
	end

	local function close_open_dropdowns()
		if CloseDropDownMenus then
			pcall( CloseDropDownMenus )
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
		m.calendar_popup.unselect()
	end

	local function extract_tagged_link( description, tag )
		if not description or description == "" then
			return nil
		end

		local pattern = tag .. "[ ]*%-%>[ ]*(https://[^%s]+)"
		return string.match( description, pattern )
	end

	local function strip_tagged_links( description )
		if not description or description == "" then
			return description
		end

		local cleaned = description
		cleaned = string.gsub( cleaned, "SR[ ]*%-%>[ ]*https://[^\r\n]+[\r\n]*", "" )
		cleaned = string.gsub( cleaned, "RF[ ]*%-%>[ ]*https://[^\r\n]+[\r\n]*", "" )
		cleaned = string.gsub( cleaned, "\n\n\n+", "\n\n" )
		cleaned = string.gsub( cleaned, "^[\r\n%s]+", "" )
		cleaned = string.gsub( cleaned, "[\r\n%s]+$", "" )
		return cleaned
	end

	---@param frame_type string
	local function get_from_cache( frame_type )
		frame_cache[ frame_type ] = frame_cache[ frame_type ] or {}

		for i = getn( frame_cache[ frame_type ] ), 1, -1 do
			if not frame_cache[ frame_type ][ i ].is_used then
				return frame_cache[ frame_type ][ i ]
			end
		end
	end

	-- Guild roster can be 500+ members. Rebuilding on every refresh() is expensive.
	-- Use a 30s TTL: only re-query the API if the cache is stale.
	local _guild_cache_time = 0
	local function update_guild_online_cache()
		local now = GetTime()
		if now - _guild_cache_time < 30 then return end
		_guild_cache_time = now
		m.wipe( guild_online_cache )
		if IsInGuild() then
			for i = 1, GetNumGuildMembers() do
				local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo( i )
				guild_online_cache[ name ] = isOnline
			end
		end
	end

	local function is_player_online( signup_name )
		for name in string.gmatch( signup_name, "([^/]+)" ) do
			name = strtrim( name ) -- Remove leading/trailing spaces if any
			if guild_online_cache[ name ] then
				return name
			end
		end
		return false
	end

	---@param name string
	local function is_in_group( name )
		-- Check party
		for i = 1, GetNumPartyMembers() do
			if UnitName( "party" .. i ) == name then
				return true
			end
		end
		-- Check raid
		for i = 1, GetNumRaidMembers() do
			if UnitName( "raid" .. i ) == name then
				return true
			end
		end
		return false
	end

	local function on_invite_click()
		local invite_list = {}
		for _, v in pairs( event.signUps ) do
			if v.userId and v.userId ~= m.db.user_settings.discord_id and v.status ~= "Absence" then
				local name = is_player_online( v.name )
				if name and not is_in_group( name ) then
					table.insert( invite_list, name )
				end
			end
		end

		local i = 1
		local function invite_next()
			if i <= getn( invite_list ) then
				InviteByName( invite_list[ i ] )
				i = i + 1
				m.ace_timer.ScheduleTimer( M, function()
					invite_next()
				end, 0.7 )
			end
		end

		if getn( invite_list ) > 0 then
			m.debug( m.L( "ui.inviting" ) or "Inviting " .. getn( invite_list ) .. m.L( "ui.players_to_event" ) or " players to event: " .. event.title )
			if not IsInRaid() then ConvertToRaid() end
			invite_next()
		else
			m.error( m.L( "ui.no_players_to_invite" ) or "No players to invite" )
		end
	end

	local function on_button_click()
		local btn_name = this.action or this.title  -- action = nom original anglais

		if not m.db.user_settings.discord_id then
			m.error( m.L( "ui.discord_not_set" ) or "DiscordID is not set" )
			return
		end

		if btn_name == "Signup" then
			m.db.user_settings[ event.templateId .. "_className" ] = popup.dd_class.selected
			m.db.user_settings[ event.templateId .. "_specName" ] = popup.dd_spec.selected

			if not m.db.user_settings[ event.templateId .. "_className" ] then
				m.error( m.L( "ui.class_not_selected" ) or "Class not selected" )
				return
			elseif not m.db.user_settings[ event.templateId .. "_specName" ] then
				m.error( m.L( "ui.spec_not_selected" ) or "Spec not selected" )
				return
			end
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Disable()
			end
			if signup_id then
				m.msg.signup_edit( event.id, signup_id )
			else
				m.msg.signup( event.id, m.db.user_settings.discord_id )
			end
		elseif btn_name == "Change Spec" then
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Hide()
			end
			popup.cs_change:Enable()
			popup.cs_change:Show()
			popup.cs_cancel:Enable()
			popup.cs_cancel:Show()

			popup.dd_class:SetPoint( "Top", popup.attending, "Top", 0, 0 )
			popup.dd_class:Show()
			popup.dd_spec:Show()
		else
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Disable()
			end
			m.msg.signup_edit( event.id, signup_id, btn_name )
		end
	end

	local function change_spec()
		if not popup.dd_class.selected then
			m.error( m.L( "ui.class_not_selected" ) or "Class not selected" )
			return
		end

		if not popup.dd_spec.selected then
			m.error( m.L( "ui.spec_not_selected" ) or "Spec not selected" )
			return
		end

		popup.cs_change:Disable()

		m.db.user_settings[ event.templateId .. "_className" ] = popup.dd_class.selected
		m.db.user_settings[ event.templateId .. "_specName" ] = popup.dd_spec.selected

		m.msg.signup_edit( event.id, signup_id )
	end

	---@param parent Frame
	---@param class string
	---@param count number
	---@return ClassFrame
	local function create_class_frame( parent, class, count )
		local frame = get_from_cache( "class" )

		if not frame then
			---@class ClassFrame: Frame
			frame = CreateFrame( "Frame", nil, parent )
			frame:SetWidth( 100 )
			frame:SetHeight( 100 )

			frame.header = gui.create_icon_label( frame, "", 100 )
			frame.header:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )
			frame.header:SetBackdrop( { bgFile = "Interface\\Buttons\\WHITE8X8" } )
			frame.header:SetBackdropColor( 0.3, 0.3, 0.3, 1 )

			frame.is_used = true
			table.insert( frame_cache[ "class" ], frame )
		else
			frame:SetParent( parent )
			frame.is_used = true
		end

		frame.header.set( class .. " (" .. tostring( count ) .. ")" )


		if gui.class_icons[ string.upper( class ) ] then
			frame.header.set_icon( "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes" )
			frame.header.icon:SetTexCoord( unpack( gui.class_icons[ string.upper( class ) ] ) )
		else
			frame.header.set_icon( "Interface\\AddOns\\RaidCalendar\\assets\\icon_" .. string.lower( class ) .. ".tga" )
			frame.header.icon:SetTexCoord( 0, 1, 0, 1 )
		end

		frame:Show()

		return frame
	end

	---@param parent Frame
	---@param signup Signup
	local function create_player_frame( parent, signup )
		local frame = get_from_cache( "player" )


		if not frame then
			---@class PlayerFrame: Frame
			frame = CreateFrame( "Frame", nil, parent )
			frame:SetWidth( 100 )
			frame:SetHeight( 16 )
			frame:SetBackdrop( { bgFile = "Interface\\Buttons\\WHITE8X8" } )
			frame:SetBackdropColor( 0.2, 0.2, 0.2, 1 )

			frame.player = gui.create_icon_label( frame, "", 100 )
			frame.player:SetPoint( "TopLeft", frame, "TopLeft", 0, 0 )

			frame.is_used = true
			table.insert( frame_cache[ "player" ], frame )
		else
			frame.is_used = true
			frame:SetParent( parent )
		end

		local entry_time = date( "%d. %b %Y " .. m.time_format, signup.entryTime )
		frame.player.set( signup.name, signup.position, entry_time )
		frame.player.set_icon( gui.spec_icons[ signup.specName ] and gui.spec_icons[ signup.specName ] or "", string.match( signup.specName, "(%a+)" ) )

		local online = is_player_online( signup.name )
		frame.player.label:SetTextColor( online and 1 or 0.75, online and 1 or 0.7, online and 1 or 0.7 )
		frame:Show()

		return frame
	end

	local function create_frame()
		---@class EventFrame: BuilderFrame
		local frame = m.FrameBuilder.new()
				:name( "RaidCalendarEventPopup" )
				:title( string.format( "Raid Calendar v%s", m.version ) )
				:frame_style( "TOOLTIP" )
				:frame_level( 100 )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 0.9 )
				:close_button()
				:width( 540 )
				:height( 380 )
				:movable()
				:esc()
				:on_drag_stop( save_position )
				:on_hide( on_hide )
				:build()

		if m.db.popup_event.position then
			local p = m.db.popup_event.position
			frame:ClearAllPoints()
			frame:SetPoint( p.point, UIParent, p.relative_point, p.x, p.y )
		end

		---
		--- Titlebar buttons
		---
		frame.btn_invite = m.GuiElements.tiny_button( frame, "I", m.L( "ui.invite_to_raid" ) or "Invite to raid", "#7b1fa2" )
		frame.btn_invite:SetPoint( "Right", frame.titlebar.btn_close, "Left", 2, 0 )
		frame.btn_invite:SetScript( "OnClick", on_invite_click )
		frame.btn_invite:Hide()

		-- Bouton Gerer l'evenement (crayon - visible si leader ou role manager)
		frame.btn_manage = m.GuiElements.tiny_button( frame, "E", m.L( "ui.manage_event" ) or "Manage event", "#1565c0" )
		frame.btn_manage:SetPoint( "Right", frame.btn_invite, "Left", -4, 0 )
		frame.btn_manage:SetScript( "OnClick", function()
			if event and m.EventManagePopup then
				m.EventManagePopup.show_edit( event.id )
			end
		end )
		frame.btn_manage:Hide()

		-- Bouton Gestion des Groupes (manager uniquement)
		frame.btn_groups = m.GuiElements.tiny_button( frame, "G", m.L( "ui.manage_groups" ) or "Manage groups", "#e65100" )
		frame.btn_groups:SetPoint( "Right", frame.btn_manage, "Left", -4, 0 )
		frame.btn_groups:SetScript( "OnClick", function()
			if event and m.GroupPopup then
				m.GroupPopup.toggle( event.id )
			end
		end )
		frame.btn_groups:Hide()

		frame.online_indicator = gui.create_online_indicator( frame, frame.btn_groups )

		local border_desc = m.FrameBuilder.new()
				:parent( frame )
				:point( "TopLeft", frame, "TopLeft", 10, -32 )
				:point( "BottomRight", frame, "TopRight", -10, -132 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0.08, 0.08, 0.08, 1 )
				:build()

		border_desc:EnableMouseWheel( true )
		border_desc:SetScript( "OnMouseWheel", function()
			local value = frame.scroll_bar:GetValue() - arg1 * 11.851852176058
			frame.scroll_bar:SetValue( value )
		end )
		frame.border_desc = border_desc

		-- Champs SR / RF copiables (Ctrl+C) affiches en haut de la zone de description
		frame.sr_label = border_desc:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall" )
		frame.sr_label:SetPoint( "TopLeft", border_desc, "TopLeft", 8, -10 )
		frame.sr_label:SetTextColor( 1, 0.82, 0, 1 )  -- or
		frame.sr_label:SetText( "SR :" )
		frame.sr_label:Hide()

		local function make_link_box( parent, y )
			local box = CreateFrame( "EditBox", nil, parent )
			box:SetAutoFocus( false )
			box:SetMultiLine( false )
			box:SetFontObject( GameFontHighlightSmall )
			box:SetHeight( 18 )
			box:SetPoint( "TopLeft",  parent, "TopLeft",  36, y )
			box:SetPoint( "TopRight", parent, "TopRight", -26, y )
			box:SetBackdrop( {
				bgFile   = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 8, edgeSize = 8,
				insets = { left = 2, right = 2, top = 2, bottom = 2 },
			} )
			box:SetBackdropColor( 0.03, 0.03, 0.04, 0.98 )
			box:SetBackdropBorderColor( 0.35, 0.28, 0.08, 0.95 )  -- bordure doree subtile
			box:SetTextInsets( 6, 4, 0, 0 )
			box:SetScript( "OnEscapePressed", function() this:ClearFocus() end )
			box:SetScript( "OnEditFocusGained", function() this:HighlightText() end )
			box:Hide()
			return box
		end

		frame.sr_box = make_link_box( border_desc, -6 )


		local scroll_bar = CreateFrame( "Slider", "RaidCalendarDescScrollBar", border_desc, "UIPanelScrollBarTemplate" )
		frame.scroll_bar = scroll_bar
		-- Position initiale : sous les deux boxes (Y=-54). Ajuste dynamiquement dans refresh().
		scroll_bar:SetPoint( "TopRight", border_desc, "TopRight", -5, -30 )
		scroll_bar:SetPoint( "Bottom",   border_desc, "Bottom",    0,  20 )
		scroll_bar:SetMinMaxValues( 0, 0 )
		scroll_bar:SetValueStep( 1 )
		scroll_bar:SetScript( "OnValueChanged", function()
			frame.desc:SetPoint( "Top", border_desc, "Top", 0, arg1 - 10 )
		end )

		frame.desc_scroll = CreateFrame( "ScrollFrame", nil, border_desc )
		frame.desc_scroll:SetPoint( "TopLeft", border_desc, "TopLeft", 8, -30 )
		frame.desc_scroll:SetPoint( "BottomRight", border_desc, "BottomRight", -22, 5 )

		frame.desc_frame = CreateFrame( "Frame", nil, frame.desc_scroll )
		frame.desc_scroll:SetScrollChild( frame.desc_frame )
		frame.desc_frame:SetWidth( 480 )
		frame.desc_frame:SetHeight( 40 )

		frame.desc = gui.create_rich_text_frame( frame.desc_frame, 480 )
		frame.desc:SetPoint( "Top", frame.desc_frame, "Top", 0, 0 )
		frame.desc:SetPoint( "Left", frame.desc_frame, "Left", 0, 0 )

		frame.leader = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_leader.tga", 140 )
		frame.leader:SetPoint( "TopLeft", frame, "TopLeft", 20, -140 )

		frame.signups = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_signups.tga", 80 )
		frame.signups:SetPoint( "TopLeft", frame.leader, "TopRight", 5, 0 )

		frame.date = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_date.tga", 110 )
		frame.date:SetPoint( "TopLeft", frame.signups, "TopRight", 5, 0 )

		frame.time = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_time.tga", 70 )
		frame.time:SetPoint( "TopLeft", frame.date, "TopRight", 5, 0 )

		frame.time_offset = gui.create_icon_label( frame, "Interface\\AddOns\\RaidCalendar\\assets\\icon_hourglass.tga" )
		frame.time_offset:SetPoint( "TopLeft", frame.time, "TopRight", 5, 0 )

		frame.attending = m.FrameBuilder.new()
				:parent( frame )
				:point( "Top", frame.leader, "Bottom", 0, -7 )
				:point( "Left", frame, "Left", 10, 0 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0.08, 0.08, 0.08, 1 )
				:width( 416 )
				:build()

		frame.missing = m.FrameBuilder.new()
				:parent( frame )
				:point( "TopLeft", frame.attending, "BottomLeft", 0, -5 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0.08, 0.08, 0.08, 1 )
				:width( 416 )
				:build()

		local prev
		for _, v in buttons do
			local btn = btn_keys[ v ]
			frame[ btn ] = gui.create_button( frame, m.L( v ), 100, on_button_click )
			frame[ btn ].action = v  -- nom original anglais pour la logique
			if prev then
				frame[ btn ]:SetPoint( "TopRight", prev, "BottomRight", 0, -5 )
			else
				frame[ btn ]:SetPoint( "Top", frame.attending, "TopRight", 0, 0 )
				frame[ btn ]:SetPoint( "Right", frame, "Right", -10, -0 )
			end
			prev = frame[ btn ]
		end

		frame.label_noaccess = frame:CreateFontString( nil, "ARTWORK", "RCFontHighlight" )
		frame.label_noaccess:SetPoint( "TopLeft", frame.attending, "TopRight", 10, 0 )
		frame.label_noaccess:SetPoint( "Right", frame, "Right", -10, 0 )
		frame.label_noaccess:SetHeight( 40 )
		frame.label_noaccess:SetJustifyV( "Top" )
		frame.label_noaccess:SetJustifyH( "Left" )
		frame.label_noaccess:SetText( m.L and m.L( "ui.access_denied" ) or "You do not have access to signup for this event." )
		frame.label_noaccess:Hide()

		frame.btn_access = gui.create_button( frame, m.L( "Refresh Access" ), 100, function()
			this:Disable()
			frame.label_noaccess:SetText( m.L( "ui.checking_access" ) )
			m.msg.check_channel_access( event.channelId, true )
		end )
		frame.btn_access:SetPoint( "Top", frame.label_noaccess, "Bottom", 0, -10 )
		frame.btn_access:SetPoint( "Right", frame, "TopRight", -10, 0 )
		frame.btn_access:Hide()

		frame.cs_change = gui.create_button( frame, m.L( "Change" ), 100, change_spec )
		frame.cs_change:SetPoint( "TopRight", frame, "TopRight", -10, -230 )
		frame.cs_change:Hide()

		frame.cs_cancel = gui.create_button( frame, m.L( "Cancel" ), 100, function() refresh( event.id ) end )
		frame.cs_cancel:SetPoint( "TopRight", frame.cs_change, "BottomRight", 0, -5 )
		frame.cs_cancel:Hide();

		frame.dd_class = scroll_drop:New( frame, {
			default_text = m.L( "ui.select_class" ),
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			label_on_select = "value",
			search = false,
			width = 95
		} )

		frame.dd_class:SetPoint( "TopRight", frame, "TopRight", -12, -360 )
		frame.dd_class:SetItems( function()
			local list = {}

			for _, v in event.classes do
				if v.type == "primary" then
					table.insert( list, {
						value = v.name,
						text = m.class_name( v.name ) or v.name,
					} )
				end
			end

			return list
		end, function( value )
			frame.dd_spec:SetText( m.L( "ui.select_spec" ) )
		end )

		frame.dd_spec = scroll_drop:New( frame, {
			default_text = m.L( "ui.select_spec" ),
			dropdown_style = m.pfui_skin_enabled and "pfui" or "classic",
			label_on_select = "value",
			search = false,
			width = 95
		} )
		frame.dd_spec:SetPoint( "TopRight", frame.dd_class, "BottomRight", 0, -5 )
		frame.dd_spec:SetItems( function()
			local list = {}
			local class = frame.dd_class.selected

			if class then
				for _, v in m.find( class, event.classes, "name" ).specs do
					table.insert( list, {
						value = v.name,
						text = m.spec_name( v.name ) or string.match( v.name, "(%a+)" ),
						icon = gui.spec_icons[ v.name ],
					} )
				end
			end

			return list
		end )

		gui.pfui_skin( frame )
		return frame
	end

	function refresh( event_id )
		close_open_dropdowns()
		local now = time( date( "*t" ) )
		local signup_class
		event = m.db.events[ event_id ]
		popup.online_indicator.update()
		update_guild_online_cache()
		-- Re-translate button texts in case locale changed
		if m.L then
			for _, v in buttons do
				local btn = btn_keys[ v ]
				if popup[ btn ] then popup[ btn ]:SetText( m.L( v ) ) end
			end
			if popup.btn_access then popup.btn_access:SetText( m.L( "actions.refresh_access" ) ) end
			if popup.cs_change then popup.cs_change:SetText( m.L( "actions.change" ) ) end
			if popup.cs_cancel then popup.cs_cancel:SetText( m.L( "actions.cancel" ) ) end
		end

		-- Reset cached elements
		for _, type in frame_cache do
			for _, frame in type do
				frame.is_used = false
				frame:Hide()
			end
		end

		-- Check if event exists and has description
		if not event or not event.description then
			popup.titlebar.title:SetText( event and event.title or "Loading..." )
			popup.desc:SetRichText( 'Hang on while event data is loaded...' )
			popup.dd_class:Hide()
			popup.dd_spec:Hide()
			m.msg.request_event( event_id )
			return
		end

		local is_leader    = event.leaderId == m.db.user_settings.discord_id or m.debug_enabled
		local has_manager  = m.db.user_settings.has_manager_role == true
		local has_raider   = m.db.user_settings.has_raider_role == true
		local can_signup   = has_raider or has_manager
		if is_leader or has_manager then
			popup.btn_invite:Show()
			popup.btn_invite:Enable()
		else
			popup.btn_invite:Hide()
		end
		if is_leader or has_manager then
			popup.btn_manage:Show()
		else
			popup.btn_manage:Hide()
		end
		if (is_leader or has_manager) and event.roles then
			popup.btn_groups:Show()
		else
			popup.btn_groups:Hide()
		end

		popup.titlebar.title:SetText( event.title )

		local clean_description = strip_tagged_links( event.description )
		local sr_url = extract_tagged_link( event.description, "SR" )

		popup.desc:SetRichText( clean_description or "" )
		popup.scroll_bar:SetMinMaxValues( 0, math.max( 0, popup.desc:GetHeight() - 65 ) )
		popup.scroll_bar:SetValue( 0 )

		-- ── Liens SR / RF ─────────────────────────────────────────────────────────
		-- Un event RaidRes est identifie par la presence d'un lien SR.
		-- Pour ces events, SR et RF sont toujours affiches (RF peut etre vide).
		-- Pour les events Raid-Helper standard, les deux boxes restent masquees.
		local is_raidres = sr_url and sr_url ~= ""
		local has_desc   = clean_description and clean_description ~= ""

		if is_raidres then
			popup.sr_label:Show()
			popup.sr_box:SetText( sr_url )
			popup.sr_box:Show()
		else
			popup.sr_label:Hide()
			popup.sr_box:SetText( "" )
			popup.sr_box:Hide()
		end

		-- ── Geometrie dynamique de border_desc ────────────────────────────────
		-- Fonction locale pour recalculer l'ancrage de border_desc.
		local function set_border_height( h )
			popup.border_desc:ClearAllPoints()
			popup.border_desc:SetPoint( "TopLeft",    popup, "TopLeft",  10, -32 )
			popup.border_desc:SetPoint( "BottomRight", popup, "TopRight", -10, -(32 + h) )
		end

		if is_raidres and not has_desc then
			-- Vue compacte : sr_box uniquement (rf supprimee), un peu de hauteur quand meme
			set_border_height( 38 )
			popup.desc_scroll:Hide()
			popup.scroll_bar:Hide()
		else
			-- Vue complete : desc_scroll visible sous les boxes (ou depuis le haut si pas de boxes)
			set_border_height( 100 )
			local desc_y = is_raidres and -30 or -8
			popup.desc_scroll:ClearAllPoints()
			popup.desc_scroll:SetPoint( "TopLeft",    popup.border_desc, "TopLeft",    8,   desc_y )
			popup.desc_scroll:SetPoint( "BottomRight", popup.border_desc, "BottomRight", -22, 5 )
			popup.scroll_bar:ClearAllPoints()
			popup.scroll_bar:SetPoint( "TopRight", popup.border_desc, "TopRight", -5, desc_y )
			popup.scroll_bar:SetPoint( "Bottom",   popup.border_desc, "Bottom",    0, 20 )
			popup.desc_scroll:Show()
			popup.scroll_bar:Show()
		end

		popup.leader.set( event.leaderName )
		popup.date.set( m.format_local_date( event.startTime, "day_month_year" ) )

		local time_format = m.db.user_settings.time_format == "24" and "%H:%M" or "%I:%M %p"
		popup.time.set( date( time_format, event.startTime ) )
		popup.time_offset.set( m.format_time_difference( event.startTime - now ) )

		--
		-- Signup counts
		--
		table.sort( event.signUps, function( a, b )
			if a.specName == nil and b.specName ~= nil then
				return true
			elseif a.specName ~= nil and b.specName == nil then
				return false
			elseif a.specName == b.specName then
				return a.position < b.position
			else
				return a.specName < b.specName
			end
		end )

		local signups_count = { Total = 0 }
		local classes_count = 0
		-- Pre-group signups by className in a single O(n) pass.
		-- The class render loop below then does O(1) lookup instead of O(n) per class.
		local signups_by_class = {}
		for _, v in pairs( event.signUps ) do
			if v.className ~= "Tentative" and v.className ~= "Absence" and v.className ~= "Late" then
				signups_count[ "Total" ] = signups_count[ "Total" ] + 1
				if not signups_count[ v.className ] then
					classes_count = classes_count + 1
				end
			end
			signups_count[ v.className ] = signups_count[ v.className ] and signups_count[ v.className ] + 1 or 1
			signups_by_class[ v.className ] = signups_by_class[ v.className ] or {}
			table.insert( signups_by_class[ v.className ], v )
		end

		local extra = (signups_count[ "Tentative" ] and signups_count[ "Tentative" ] or 0) + (signups_count[ "Late" ] and signups_count[ "Late" ] or 0)
		popup.signups.set( tostring( signups_count[ "Total" ] ) .. (extra > 0 and " (+" .. extra .. ")" or "") )

		--
		-- Classes
		--
		local current
		local data = {
			attending = { x = 5, y = -5, max_y = 0, count = 0, total_y = 0 },
			missing = { x = 5, y = -5, max_y = 0, count = 0, total_y = 0 }
		}

		signup_id = nil
		for _, class in ipairs( event.classes ) do
			current = class.type == "primary" and "attending" or "missing"

			local class_frame = create_class_frame( popup[ current ], class.name, signups_count[ class.name ] or 0 )
			class_frame:SetPoint( "TopLeft", popup[ current ], "TopLeft", data[ current ].x, data[ current ].y )

			data[ current ].x = data[ current ].x + 102
			data[ current ].count = data[ current ].count + 1

			local y = 17
			-- O(1) lookup via pre-grouped table — was O(n) scan across all signups per class
			for _, v in ipairs( signups_by_class[ class.name ] or {} ) do
				local player_frame = create_player_frame( class_frame, v )
				player_frame:SetPoint( "TopLeft", class_frame, "TopLeft", 0, -y )

				y = y + 17
				if y > data[ current ].max_y then data[ current ].max_y = y end
				if m.db.user_settings.discord_id and m.db.user_settings.discord_id == v.userId then
					signup_id = v.id
					signup_class = class.name
				end
			end

			if y == 17 then
				class_frame:Hide()
				data[ current ].x = data[ current ].x - 102
				data[ current ].count = data[ current ].count - 1
			end

			if data[ current ].count ~= 0 and data[ current ].count ~= classes_count and mod( data[ current ].count, 4 ) == 0 then
				data[ current ].x = 5
				data[ current ].total_y = data[ current ].total_y + data[ current ].max_y + 15
				data[ current ].y = -5 - data[ current ].total_y
				data[ current ].max_y = 0
			end

			class_frame:SetHeight( y )
		end

		popup.attending:SetHeight( math.max( 20, data[ "attending" ].total_y + data[ "attending" ].max_y + 9 ) )

		if data[ "missing" ].count == 0 then
			popup.missing:SetHeight( 0 )
			popup.missing:Hide()
		else
			popup.missing:SetHeight( data[ "missing" ].total_y + data[ "missing" ].max_y + 9 )
			popup.missing:Show()
		end

		popup:SetHeight( math.max( 345, 196 + data[ "attending" ].total_y + data[ "attending" ].max_y + data[ "missing" ].total_y + data[ "missing" ].max_y ) )

		--
		-- Buttons
		--
		local class = m.db.user_settings[ event.templateId .. "_className" ]
		popup.dd_class:SetSelected( class or nil )
		popup.dd_class:Hide()

		local spec = m.db.user_settings[ event.templateId .. "_specName" ]
		popup.dd_spec:SetSelected( spec or nil )
		popup.dd_spec:Hide()
		popup.cs_change:Hide()
		popup.cs_cancel:Hide()

		if signup_id then
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Enable()
				popup[ btn ]:Show()
			end

			local btn = "btn_" .. string.gsub( string.lower( signup_class ), "%s", "_" )
			if popup[ btn ] then
				popup[ btn ]:Disable()
			else
				popup.btn_signup:Disable()
			end
		else
			popup.btn_signup:Show()
			popup.btn_signup:Enable()
			popup.dd_class:SetPoint( "Top", popup, "Top", 0, -220 )
			popup.dd_class:Show()
			popup.dd_spec:Show()
			for _, v in buttons do
				if v ~= "Signup" then
					local btn = btn_keys[ v ]
					popup[ btn ]:Hide()
				end
			end
		end

		-- Event closed
		if event.closingTime < now then
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Disable()
			end
			popup.dd_class:Hide()
			popup.dd_spec:Hide()
			return
		end

		popup.label_noaccess:Hide()
		popup.btn_access:Hide()
		local has_access = m.db.user_settings.channel_access[ event.channelId ]

		-- Vérifier rôle raider si pas encore fait
		if m.db.user_settings.has_raider_role == nil and not has_manager then
			if m.msg and m.msg.check_raider_role then
				m.msg.check_raider_role( m.db.user_settings.discord_id )
			end
		end
		-- No access
		if not can_signup then
			-- Joueur sans rôle raider/manager : masquer les boutons signup
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Hide()
			end
			popup.dd_class:Hide()
			popup.dd_spec:Hide()
			popup.label_noaccess:Show()
			popup.label_noaccess:SetText( m.L and m.L( "ui.access_denied" ) or "You do not have access to signup for this event." )
		elseif has_access == false then
			for _, v in buttons do
				local btn = btn_keys[ v ]
				popup[ btn ]:Hide()
			end
			popup.dd_class:Hide()
			popup.dd_spec:Hide()
			popup.label_noaccess:Show()
			popup.label_noaccess:SetText( m.L and m.L( "ui.access_denied" ) or "You do not have access to signup for this event." )
			popup.btn_access:Enable()
			popup.btn_access:Show()
		elseif has_access == nil then
			m.msg.check_channel_access( event.channelId )
		end
	end

	local function show( event_id )
		-- Ferme les autres popups secondaires
		if m.close_all_popups then m.close_all_popups() end

		if not popup then
			popup = create_frame()
		end
		M.current_popup = popup

		close_open_dropdowns()
		popup:Show()
		refresh( event_id )
	end

	local function hide()
		if popup then
			close_open_dropdowns()
			popup:Hide()
		end
	end

	local function toggle( event_id )
		if popup and popup:IsVisible() and (event.id and event_id == event.id or not event_id) then
			popup:Hide()
		elseif (event and event.id) or event_id then
			show( event_id or event.id )
		end
	end

	local function is_visible()
		return popup and popup:IsVisible() or false
	end

	local function update( event_id )
		if popup and popup:IsVisible() then
			if event_id and event and event.id ~= event_id then
				return
			end
			refresh( event_id or event.id )
		end
	end

	local function online_status( online )
		if popup then
			if online then
				popup.indicator_tex:SetVertexColor( 0, 1, 0, .9 )
			else
				popup.indicator_tex:SetVertexColor( 1, 0, 0, .9 )
			end
		end
	end

	---@type EventPopup
	return {
		show = show,
		hide = hide,
		toggle = toggle,
		is_visible = is_visible,
		update = update,
		online_status = online_status,
	}
end

m.EventPopup = M
return M
