---@class RaidCalendar
RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar
local lib_stub = LibStub

RaidCalendar.name = "RaidCalendar"
RaidCalendar.prefix = "RaidCal"
RaidCalendar.tagcolor = "FF7b1fa2"
RaidCalendar.events = {}
RaidCalendar.debug_enabled = false
RaidCalendar.api = getfenv()

---@alias NotAceTimer any
---@alias TimerId number

---@class AceTimer
---@field ScheduleTimer fun( self: NotAceTimer, callback: function, delay: number, ... ): TimerId
---@field ScheduleRepeatingTimer fun( self: NotAceTimer, callback: function, delay: number, arg: any ): TimerId
---@field CancelTimer fun( self: NotAceTimer, timer_id: number )
---@field TimeLeft fun( self: NotAceTimer, timer_id: number )

function RaidCalendar:init()
	self.frame = CreateFrame( "Frame" )
	self.frame:SetScript( "OnEvent", function()
		if self.events[ event ] then
			self.events[ event ]( self )
		end
	end )

	for k, _ in pairs( m.events ) do
		self.frame:RegisterEvent( k )
	end
end

function RaidCalendar.events:ADDON_LOADED()
	if arg1 ~= self.name then return end

	---@type AceTimer
	m.ace_timer = lib_stub( "AceTimer-3.0" )

	m.player = UnitName( "player" )
	m.player_class = UnitClass( "player" )

	RaidCalendarDB = RaidCalendarDB or {}
	m.db = RaidCalendarDB
	m.db.events = m.db.events or {}
	m.db.user_settings = m.db.user_settings or {}
	m.db.user_settings.time_format = m.db.user_settings.time_format or "24"
	m.db.user_settings.channel_access = m.db.user_settings.channel_access or {}
	m.db.popup_sr = m.db.popup_sr or {}
	m.db.popup_event = m.db.popup_event or {}
	m.db.popup_calendar = m.db.popup_calendar or {}
	m.db.minimap_icon = m.db.minimap_icon or {}
	m.db.group_plans = m.db.group_plans or {}
	m.db.user_settings.ui_theme = m.db.user_settings.ui_theme or "Blizzard"
	-- Toujours utiliser le nom du personnage (case a cocher supprimee, option forcee)
	m.db.user_settings.use_character_name = 1

	m.time_format = m.db.user_settings.time_format == "24" and "%H:%M" or "%I:%M %p"

	-- Apply saved locale, otherwise use WoW client locale, fallback to enUS
	if m.set_locale then
		local selected_locale = m.db.user_settings.locale_flag
		if not selected_locale or selected_locale == "" then
			selected_locale = ( GetLocale and GetLocale() ) or "enUS"
		end

		if selected_locale ~= "enUS" and selected_locale ~= "frFR" then
			selected_locale = "enUS"
		end

		m.set_locale( selected_locale )
		m.db.user_settings.locale_flag = selected_locale
	end

	---@type MessageHandler
	m.msg = m.MessageHandler.new()

	-- -- Raid Tracker ------------------------------------------
	m.raid_tracker    = m.RaidTracker
	m.raid_tracker_ui = m.RaidTrackerUI
	m.event_manage    = m.EventManagePopup
	m.local_events    = m.LocalEventManager
	m.local_popup     = m.LocalEventPopup
	if m.LocalEventManager then
		m.LocalEventManager.init()
		-- Nettoyage automatique si le joueur est manager Discord
		-- has_manager_role est mis a jour a chaque connexion via RAID_ROLE_RESULT
		if m.db and m.db.user_settings and m.db.user_settings.has_manager_role then
			pcall( function() m.LocalEventManager.cleanup_old() end )
		end
	end

	-- Verifier les roles Discord au demarrage (5s apres chargement)
	if m.db.user_settings.discord_id then
		m.ace_timer.ScheduleTimer( m, function()
			if m.RaidTracker and m.RaidTracker.request_role_check then
				m.RaidTracker.request_role_check()
			end
		end, 5 )
	end

	-- Bot status detection:
	-- The bot emits an explicit RC_BOT_ONLINE heartbeat every 10s.
	-- Addon keeps ONLINE for 15s, DEGRADED until 25s, then OFFLINE.
	m.ace_timer.ScheduleTimer( m, function()
		if m.msg and m.msg.bot_status then
			m.msg.bot_status()
		end
	end, 3 )

	local function should_poll_bot_status()
		local ui_active = false
		if m.calendar_popup and m.calendar_popup.IsVisible and m.calendar_popup:IsVisible() then ui_active = true end
		if not ui_active and m.event_popup and m.event_popup.IsVisible and m.event_popup:IsVisible() then ui_active = true end
		if not ui_active and m.local_event_popup and m.local_event_popup.IsVisible and m.local_event_popup:IsVisible() then ui_active = true end
		if not ui_active and m.sr_popup and m.sr_popup.IsVisible and m.sr_popup:IsVisible() then ui_active = true end
		if not ui_active and m.GroupPopup and m.GroupPopup.popup and m.GroupPopup.popup.IsVisible and m.GroupPopup.popup:IsVisible() then ui_active = true end
		return ui_active
	end

	local _poll_elapsed = 0
	local poll_frame = CreateFrame( "Frame" )
	poll_frame:SetScript( "OnUpdate", function()
		-- Accumulate delta; bail immediately below the minimum possible interval (5s).
		-- All heavier checks (get_bot_state, should_poll_bot_status) are only reached
		-- after that threshold, saving work on the overwhelming majority of frames.
		_poll_elapsed = _poll_elapsed + arg1
		if _poll_elapsed < 5 then return end

		local state = m.get_bot_state()
		local interval
		if state == "OFFLINE" then
			interval = 5
		elseif state == "DEGRADED" then
			interval = 8
		elseif should_poll_bot_status() then
			interval = 30
		else
			interval = 120
		end

		if _poll_elapsed < interval then return end
		_poll_elapsed = 0
		m.msg.bot_status()
	end )

	local tracker_frame = CreateFrame( "Frame" )
	tracker_frame:RegisterEvent( "CHAT_MSG_LOOT" )
	tracker_frame:RegisterEvent( "CHAT_MSG_COMBAT_HOSTILE_DEATH" )
	tracker_frame:RegisterEvent( "PLAYER_REGEN_DISABLED" )
	tracker_frame:RegisterEvent( "PLAYER_REGEN_ENABLED" )
	tracker_frame:SetScript( "OnEvent", function()
		if not m.RaidTracker then return end
		if event == "CHAT_MSG_LOOT" then
			m.RaidTracker.on_chat_loot( arg1 )
		elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
			m.RaidTracker.on_hostile_death( arg1 )
		elseif event == "PLAYER_REGEN_DISABLED" then
			m.RaidTracker.on_combat_start()
		elseif event == "PLAYER_REGEN_ENABLED" then
			m.RaidTracker.on_combat_end()
		end
	end )
	-- --------------------------------------------------------

	---@type EventPopup
	m.event_popup = m.EventPopup.new()

	---@type CalendarPopup
	local theme = m.db.user_settings.ui_theme or "Original"
	local popup_module = m["CalendarPopup" .. theme] or m.CalendarPopupOriginal
	m.calendar_popup_instances = m.calendar_popup_instances or {}
	m.calendar_popup_instances[theme] = popup_module.new()
	m.calendar_popup = m.calendar_popup_instances[theme]

	---@type SRPopup
	m.sr_popup = m.SRPopup.new()

	---@type WelcomePopup
	m.welcome_popup = m.WelcomePopup.new()

	---@type MinimapIcon
	m.minimap_icon = m.MinimapIcon.new()

	if m.db.user_settings.sr_admins == nil then
		m.msg.bot_status()
	end

	if m.api.IsAddOnLoaded( "pfUI" ) and m.api.pfUI and m.api.pfUI.api and m.api.pfUI.env and m.api.pfUI.env.C then
		m.pfui_skin_enabled = true
		m.api.pfUI:RegisterSkin( "RaidCalendar", "vanilla", function()
			if m.api.pfUI.env.C.disabled and m.api.pfUI.env.C.disabled[ "skin_RaidCalendar" ] == "1" then
				m.pfui_skin_enabled = false
			end
		end )
	end

	local orig_SetItemRef = SetItemRef
	function SetItemRef( link, text, button, chatFrame )
		local linkType, data = string.match( link, "^([^:]+):(.+)" )

		if linkType == "raidcal" then
			local type, id = string.match( data, "^(%w+):(.+)" )
			if type == "event" then
				m.event_popup.toggle( id )
			elseif type == "sr" then
				if tonumber( id ) == nil then
					_, id = m.find( id, m.db.events, "srId" )
				end
				if tonumber( id ) then
					m.sr_popup.toggle( id )
				end
			end
			return
		end

		return orig_SetItemRef( link, text, button, chatFrame )
	end

	for i = 1, NUM_CHAT_WINDOWS do
		local frame = self.api[ "ChatFrame" .. i ]
		if frame then self.wrap_chat_frame( frame ) end
	end

	m.api[ "SLASH_RaidCalendar1" ] = "/rc"
	m.api[ "SLASH_RaidCalendar2" ] = "/RaidCalendar"

	SlashCmdList[ "RaidCalendar" ] = function( args )
		if args == "raid" or args == "rt" then
			m.RaidTrackerUI.toggle()
			return
		end

		if args == "new" or args == "create" then
			m.EventManagePopup.show_create()
			return
		end

		if args == "local" then
			m.EventManagePopup.show_create_local()
			return
		end

				if args == "debug" then
			m.debug_enabled = not m.debug_enabled
			m.info( "Debug is " .. (m.debug_enabled and "enabled" or "disabled") )
			return
		end

		if args == "clear" then
			m.info( "All events have been removed" )
			m.db.events = {}
			return
		end

		if args == "welcome" then
			m.welcome_popup.show()
			return
		end

		if args == "vc" then
			m.msg.version_check( true )
			return
		end

		if args == "refresh" then
			m.msg.request_events( true )
			return
		end

		-- /rc bot <message> : envoie un chuchotement au personnage bot
		-- Le nom du bot est récupéré depuis les settings (bot_name défini via RBSTATUS)
		local bot_msg = string.match(args, "^bot%s+(.+)$")
		if bot_msg then
			local bot_name = m.db.user_settings and m.db.user_settings.bot_name
			if bot_name and bot_name ~= "" then
				SendChatMessage(bot_msg, "WHISPER", nil, bot_name)
			else
				m.error( m.L and m.L("ui.bot_name_unknown") or "Bot name unknown. Reconnect (/rc) to initialize." )
			end
			return
		end

		m.calendar_popup.show()
	end

	m.version = GetAddOnMetadata( m.name, "Version" )
	self.info( string.format( "(v%s) Loaded", m.version ) )

	if m.db.user_settings.bot_name and m.db.user_settings.bot_name ~= "" and m.db.user_settings.discord_id then
		-- Refresh events if last update is older then 6h
		if not m.db.user_settings.last_updated or time() - m.db.user_settings.last_updated > 3600 * 6 then
			m.debug( "Fetching events..." )
			m.msg.request_events( true )
		end
	elseif m.db.user_settings.show_welcome_popup ~= false then
		m.welcome_popup.show()
	end

	self.check_new_version()
end

-- ISO-8601 timestamp pattern used by wrap_chat_frame.
-- Hoisted here so it is allocated once at load time, not on every AddMessage call.
local _ISO_TS_PATTERN = "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z"

---@param frame Frame
function RaidCalendar.wrap_chat_frame( frame )
	local original_add_message = frame[ "AddMessage" ]

	frame[ "AddMessage" ] = function( self, msg, r, g, b, id )
		if msg then
			-- Single pass: string.find with captures avoids a redundant string.match scan.
			local _, _, year, month, day, hour, minute, second =
				string.find( msg, _ISO_TS_PATTERN )

			if year then
				local timestamp = time( {
					year = year, month = month, day = day,
					hour = hour, min = minute, sec = second
				} )
				local date_formatted = date( "%A", timestamp )
					.. " " .. tonumber( date( "%d", timestamp ) )
					.. ". " .. date( "%B", timestamp )
				msg = string.gsub( msg, _ISO_TS_PATTERN, date_formatted )
			end
		end

		return original_add_message( self, msg, r, g, b, id )
	end
end

function RaidCalendar.get_raid_members()
	local members = {}
	local num = GetNumRaidMembers()
	for i = 1, num do
		local name = GetRaidRosterInfo( i )
		if name then
			table.insert( members, string.upper( name ) )
		end
	end
	return members
end

function RaidCalendar.check_new_version()
	if not m.db.user_settings.last_versioncheck or time() - m.db.user_settings.last_versioncheck > 3600 * 24 then
		m.msg.bot_status()
		m.msg.version_check()
	end
end

-- Ferme toutes les popups secondaires (EventPopup, LocalEventPopup, EventManagePopup, SRPopup)
function RaidCalendar.close_all_popups()
    local m = RaidCalendar
    if m.event_popup and m.event_popup.hide then m.event_popup.hide() end
    if m.LocalEventPopup and m.LocalEventPopup.hide then m.LocalEventPopup.hide() end
    if m.EventManagePopup and m.EventManagePopup.hide then m.EventManagePopup.hide() end
    if m.sr_popup and m.sr_popup.hide then m.sr_popup.hide() end
    if m.GroupPopup and m.GroupPopup.hide then m.GroupPopup.hide() end
end


RaidCalendar:init()
