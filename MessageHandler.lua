RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.MessageHandler then return end

---@type MessageCommand
local MessageCommand = {
	-- Outgoing
	RequestBotStatus = "RBSTATUS",
	RequestDiscordId = "RDID",
	RequestDiscordAuth = "RDAUTH",
	RequestChannelCheck = "CHCHECK",
	RequestEvent = "REVENT",
	RequestEvents = "REVENTS",
	Signup = "SIGNUP",
	SignupEdit = "SIGNUP_EDIT",
	RequestSR = "RSR",
	AddSR = "SRADD",
	DeleteSR = "SRDELETE",
	LockSR = "SRLOCK",
	VersionCheck = "VERC",
	-- Raid Tracker
	RaidEvent     = "RAID_EVENT",
	LootAssign    = "LOOT_ASSIGN",
	RaidSummary   = "RAID_SUMMARY",
	RaidRoleCheck  = "RAID_ROLE_CHECK",
	-- Verification role membre
	RaiderRoleCheck  = "RAIDER_ROLE_CHECK",
	RaiderRoleResult = "RAIDER_ROLE_RESULT",
	MemberRoleCheck  = "MEMBER_ROLE_CHECK",
	LocalEventAnnounce  = "LOCAL_EVENT_ANNOUNCE",
	LocalEventCreate    = "LOCAL_EVENT_CREATE",
	LocalEventEdit      = "LOCAL_EVENT_EDIT",
	LocalEventDelete    = "LOCAL_EVENT_DELETE",
	LocalEventList      = "LOCAL_EVENT_LIST",
	LocalEventSignup    = "LOCAL_EVENT_SIGNUP",
	LocalEventUnsignup  = "LOCAL_EVENT_UNSIGNUP",
	-- Gestion des evenements
	RaidresCreate  = "RAIDRES_CREATE",
	RfDataRequest  = "RF_DATA_REQUEST",
	RfDataResult   = "RF_DATA_RESULT",
		CreateEvent    = "CREATE_EVENT",
	EditEvent      = "EDIT_EVENT",
	DeleteEvent    = "DELETE_EVENT",
	GroupPlanGet       = "GROUP_PLAN_GET",
	GroupPlanSaveBegin = "GROUP_PLAN_SAVE_BEGIN",
	GroupPlanSaveChunk = "GROUP_PLAN_SAVE_CHUNK",
	GroupPlanSaveEnd   = "GROUP_PLAN_SAVE_END",
	GroupPlanClear     = "GROUP_PLAN_CLEAR",
	GroupPlanWatch     = "GROUP_PLAN_WATCH",
	GroupThreadTakeLead = "GROUP_THREAD_TAKE_LEAD",
	GroupThreadSetAssistant = "GROUP_THREAD_SET_ASSISTANT",
	GroupThreadAnnounce = "GROUP_THREAD_ANNOUNCE",
	-- Incoming
	BotStatus = "BSTATUS",
	DiscordId = "DID",
	DiscordAuth = "DAUTH",
	ChannelCheckResult = "CHCHECK_RESULT",
	Event = "EVENT",
	Events = "EVENTS",
	EventsUpdate = "EVENTS_UPDATE",
	SignupResult = "SIGNUP_RESULT",
	SR = "SR",
	AddSRResult = "SRADD_RESULT",
	DeleteSRResult = "SRDELETE_RESULT",
	LockSRResult = "SRLOCK_RESULT",
	Version = "VER",
	-- Raid Tracker
	RaidRoleResult   = "RAID_ROLE_RESULT",
	-- Gestion des evenements
	MemberRoleResult        = "MEMBER_ROLE_RESULT",
	CleanupLocalEvents      = "CLEANUP_LOCAL_EVENTS",
	LocalEventResult        = "LOCAL_EVENT_RESULT",
	LocalEventsList         = "LOCAL_EVENTS_LIST",
	LocalSignupResult       = "LOCAL_SIGNUP_RESULT",
	-- Gestion des evenements
	RaidresCreateResult = "RAIDRES_CREATE_RESULT",
		CreateEventResult = "CREATE_EVENT_RESULT",
	EditEventResult   = "EDIT_EVENT_RESULT",
	DeleteEventResult = "DELETE_EVENT_RESULT",
	GroupPlanResult   = "GROUP_PLAN_RESULT",
	GroupThreadResult = "GROUP_THREAD_RESULT",
}

---@alias MessageCommand
---| "RDAUTH"
---| "DAUTH"
---| "CHCHECK"
---| "CHCHECK_RESULT"
---| "RBSTATUS"
---| "RAIDER_ROLE_CHECK"
---| "RAIDER_ROLE_RESULT"
---| "RF_DATA_REQUEST"
---| "RF_DATA_RESULT"
---| "BSTATUS"
---| "DID"
---| "RDID"
---| "SR"
---| "RSR"
---| "SRADD"
---| "SRADD_RESULT"
---| "SRDELETE"
---| "SRDELETE_RESULT"
---| "SRLOCK"
---| "SRLOCK_RESULT"
---| "REVENT"
---| "REVENTS"
---| "EVENT"
---| "EVENTS"
---| "SIGNUP"
---| "SIGNUP_EDIT"
---| "SIGNUP_RESULT"
---| "VERC"
---| "VER"

---@class AceComm
---@field RegisterComm fun( self: any, prefix: string, method: function? )
---@field SendCommMessage fun( self: any, prefix: string, text: string, distribution: string, target: string?, prio: "BULK"|"NORMAL"|"ALERT"?, callbackFn: function?, callbackArg: any? )

---@class MessageHandler
---@field find_discord_id fun( name: string )
---@field check_channel_access fun( channel_id: string, renew: boolean? )
---@field authorize_user fun( user_id: string )
---@field add_sr fun( raid_id: number, sr_id: string, sr1: number, sr2: number, comment: string? )
---@field delete_sr fun( sr_id: string, id: number )
---@field request_sr fun( sr_id: string )
---@field lock_sr fun( sr_id: string, lock: boolean )
---@field request_event fun( event_id: string )
---@field request_events fun(force: boolean?)
---@field signup fun( event_id: string, user_id: string )
---@field signup_edit fun( event_id: string, signup_id: string, role: string? )
---@field bot_status fun()
---@field version_check fun( show_all: boolean?)

local M = {}

function M.new()
	local lib_stub = LibStub

	---@type AceComm
	local ace_comm = lib_stub( "AceComm-3.0" )

	local chunk_state_by_sender = {}
	local key_map = {
		a = "announcements",
		n = "name",
		ct = "closingTime",
		s = "startTime",
		cl = "classes",
		l = "lastUpdated",
		e = "entryTime",
		d = "description",
		le = "leaderName",
		ch = "channelType",
		ld = "leaderId",
		si = "signUps",
		cn = "channelName",
		ef = "effectiveName",
		r = "roleName",
		c = "color",
		et = "endTime",
		i = "id",
		se = "serverId",
		t = "templateId",
		da = "date",
		ro = "roles",
		st = "status",
		cs = "className",
		sp = "specName",
		p = "position",
		ti = "time",
		u = "userId",
		tl = "title",
		ty = "type",
		li = "limit",
		ci = "channelId",
		sc = "specs",
		di = "displayTitle",
		su = "signUpCount",
		co = "closeTime",
		re = "reference",
		ad = "allowDuplicateReservation",
		ac = "allowComments",
		rl = "reservationLimit",
		cm = "comment",
		ca = "character",
		b = "raidItemId",
		f = "itemId",
		sr = "srPlus",
		z = "specialization",
		ah = "advancedHrItems",
		h = "isHardReserved",
		cz = "characterSpecializations",
		cb = "characterNames",
		rv = "reservations",
		-- Clés spécifiques aux évènements in-game (non compressées)
		-- Ces entrées servent de pass-through: clé=clé pour qu'elles survivent au decode
		action              = "action",
		eventId             = "eventId",
		creator             = "creator",
		location            = "location",
		createdAt           = "createdAt",
		signedAt            = "signedAt",
		discordThreadId     = "discordThreadId",
		events              = "events",
		player              = "player",
		success             = "success",
		signups             = "signups",
		raidHelperStatus    = "raidHelperStatus",
		updatedBy           = "updatedBy",
		updatedAt           = "updatedAt",
		planEncoded         = "planEncoded",
		targetPlayer        = "targetPlayer",
	}

	local EVENT_REQUEST_MIN_INTERVAL = 5
	local EVENT_REQUEST_IN_FLIGHT_TIMEOUT = 12
	local last_events_request_at = 0
	local events_request_in_flight = false

	local value_map = {
		[ "#1" ] = "Tanks",
		[ "#2" ] = "Arms",
		[ "#3" ] = "Fury",
		[ "#4" ] = "Protection",
		[ "#5" ] = "Protection1",
		[ "#6" ] = "Holy",
		[ "#7" ] = "Holy1",
		[ "#8" ] = "Retribution",
		[ "#9" ] = "Guardian",
		[ "#10" ] = "Combat",
		[ "#11" ] = "Demonology",
		[ "#12" ] = "Destruction",
		[ "#13" ] = "Enhancement",
		[ "#14" ] = "Dps",
		[ "#15" ] = "Feral",
		[ "#16" ] = "Assassination",
		[ "#17" ] = "Subtlety",
		[ "#18" ] = "Survival",
		[ "#19" ] = "Beastmastery",
		[ "#20" ] = "Arcane",
		[ "#21" ] = "Fire",
		[ "#22" ] = "Frost",
		[ "#23" ] = "Affliction",
		[ "#24" ] = "Marksmanship",
		[ "#25" ] = "Balance",
		[ "#26" ] = "Shadow",
		[ "#27" ] = "Smite",
		[ "#28" ] = "Elemental",
		[ "#29" ] = "Ranged",
		[ "#30" ] = "Discipline",
		[ "#31" ] = "Restoration",
		[ "#32" ] = "Restoration1",
		[ "#33" ] = "Healer",
		[ "#34" ] = "Late",
		[ "#35" ] = "Bench",
		[ "#36" ] = "Tentative",
		[ "#37" ] = "Absence",
		[ "#38" ] = "Healers",
		[ "#39" ] = "Melee",
		[ "#40" ] = "Tank",
		[ "#41" ] = "primary",

		[ "#42" ] = "Druid",
		[ "#43" ] = "DruidBalance",
		[ "#44" ] = "DruidFeral",
		[ "#45" ] = "DruidRestoration",
		[ "#46" ] = "DruidBear",
		[ "#47" ] = "Hunter",
		[ "#48" ] = "HunterBeastMastery",
		[ "#49" ] = "HunterMarksmanship",
		[ "#50" ] = "HunterSurvival",
		[ "#51" ] = "Mage",
		[ "#52" ] = "MageArcane",
		[ "#53" ] = "MageFire",
		[ "#54" ] = "MageFrost",
		[ "#55" ] = "Paladin",
		[ "#56" ] = "PaladinHoly",
		[ "#57" ] = "PaladinProtection",
		[ "#58" ] = "PaladinRetribution",
		[ "#59" ] = "Priest",
		[ "#60" ] = "PriestDiscipline",
		[ "#61" ] = "PriestHoly",
		[ "#62" ] = "PriestShadow",
		[ "#63" ] = "Rogue",
		[ "#64" ] = "RogueSwords",
		[ "#65" ] = "RogueDaggers",
		[ "#66" ] = "RogueMaces",
		[ "#67" ] = "Shaman",
		[ "#68" ] = "ShamanElemental",
		[ "#69" ] = "ShamanEnchancement",
		[ "#70" ] = "ShamanRestoration",
		[ "#71" ] = "ShamanTank",
		[ "#72" ] = "Warlock",
		[ "#73" ] = "WarlockAffliction",
		[ "#74" ] = "Demonology",
		[ "#75" ] = "Destruction",
		[ "#76" ] = "Warrior",
		[ "#77" ] = "WarriorArms",
		[ "#78" ] = "WarriorFury",
		[ "#79" ] = "WarriorProtection"
	}

	setmetatable( key_map, { __index = function( _, key ) return key end } );
	setmetatable( value_map, { __index = function( _, key ) return key end } );

	---@param tbl table
	---@param keymap table
	---@param valuemap table
	---@return table
	local function decode( tbl, keymap, valuemap )
		local ret = {}
		if not tbl then return ret end

		for key, value in pairs( tbl ) do
			if type( value ) == "table" then
				value = decode( value, keymap, valuemap )
			elseif type( value ) == "string" then
				value = valuemap[ value ] or value
			end

			-- Si la clé est dans le keymap, utiliser la clé longue
			-- Sinon conserver la clé originale (pass-through défensif)
			local mapped_key = keymap[ key ]
			ret[ mapped_key ~= nil and mapped_key or key ] = value
		end

		return ret
	end

	---@param command MessageCommand
	---@param data table?
	local function broadcast( command, data )
		m.debug( string.format( "Broadcasting %s", command ) )
		local _data = data and m.flatten( data ) or ""
		ace_comm:SendCommMessage( m.prefix, command .. "::" .. _data, "GUILD", nil, "NORMAL" )
	end


	local function encode_group_plan( plan )
		if type( plan ) ~= "table" then return "" end
		local entries = {}
		for g = 1, 8 do
			local grp = plan[g]
			if type( grp ) == "table" then
				for s = 1, 5 do
					local name = grp[s]
					if type( name ) == "string" and name ~= "" then
						local safe = string.gsub( name, "([^%w_%-])", function( c )
							return string.format( "%%%02X", string.byte( c ) )
						end )
						table.insert( entries, g .. "," .. s .. "," .. safe )
					end
				end
			end
		end
		return table.concat( entries, ";" )
	end

	local function decode_group_plan( encoded )
		local plan = {}
		if type( encoded ) ~= "string" or encoded == "" then return plan end
		for token in string.gmatch( encoded, "([^;]+)" ) do
			local g, s, safe = string.match( token, "^(%d+),(%d+),(.+)$" )
			g = tonumber( g )
			s = tonumber( s )
			if g and s and safe then
				safe = string.gsub( safe, "%%(%x%x)", function( hex )
					return string.char( tonumber( hex, 16 ) )
				end )
				plan[g] = plan[g] or {}
				plan[g][s] = safe
			end
		end
		return plan
	end

	local function send_group_plan_chunks( event_id, user_id, encoded )
		local chunk_size = 150
		local total = 0
		if encoded and encoded ~= "" then
			total = math.ceil( string.len( encoded ) / chunk_size )
		end

		broadcast( MessageCommand.GroupPlanSaveBegin, {
			eventId = event_id,
			userId = user_id or "",
			total = total,
		} )

		local idx = 1
		local pos = 1
		while pos <= string.len( encoded ) do
			local chunk = string.sub( encoded, pos, pos + chunk_size - 1 )
			broadcast( MessageCommand.GroupPlanSaveChunk, {
				eventId = event_id,
				userId = user_id or "",
				index = idx,
				chunk = chunk,
			} )
			pos = pos + chunk_size
			idx = idx + 1
		end

		broadcast( MessageCommand.GroupPlanSaveEnd, {
			eventId = event_id,
			userId = user_id or "",
		} )
	end

	local function find_discord_id( name )
		broadcast( MessageCommand.RequestDiscordId, { name = name } )
	end

	local function check_channel_access( channel_id, renew )
		broadcast( MessageCommand.RequestChannelCheck, {
			userId = m.db.user_settings.discord_id,
			channelId = channel_id,
			renew = renew or false
		} )
	end

	local function authorize_user( user_id )
		broadcast( MessageCommand.RequestDiscordAuth, {
			userId = user_id
		} )
	end

	local function add_sr( raid_id, sr_id, sr1, sr2, comment )
		local data = {
			raidId = raid_id,
			reference = sr_id,
			comment = comment,
			characterName = m.player,
			characterClass = m.player_class,
			specialization = m.player_class .. m.db.user_settings.sr_specName,
			raidItemIds = {}
		}
		if sr1 then table.insert( data.raidItemIds, sr1 ) end
		if sr2 then table.insert( data.raidItemIds, sr2 ) end

		broadcast( MessageCommand.AddSR, data )
	end

	local function delete_sr( sr_id, id )
		broadcast( MessageCommand.DeleteSR, {
			reference = sr_id,
			id = id
		} )
	end

	local function request_sr( sr_id )
		broadcast( MessageCommand.RequestSR, {
			id = sr_id
		} )
	end

	local function lock_sr( sr_id, locked )
		broadcast( MessageCommand.LockSR, {
			id = sr_id,
			locked = locked
		} )
	end

	local function request_events( force )
		local now = time()

		if not force then
			if events_request_in_flight and ( now - last_events_request_at ) < EVENT_REQUEST_IN_FLIGHT_TIMEOUT then
				if m.debug then
					m.debug( "Skip REVENTS: request already in flight" )
				end
				return false
			end

			if last_events_request_at > 0 and ( now - last_events_request_at ) < EVENT_REQUEST_MIN_INTERVAL then
				if m.debug then
					m.debug( "Skip REVENTS: throttled" )
				end
				return false
			end
		end

		last_events_request_at = now
		events_request_in_flight = true
		broadcast( MessageCommand.RequestEvents )
		return true
	end

	local function request_event( event_id )
		broadcast( MessageCommand.RequestEvent, {
			id = event_id
		} )
	end

	local function signup( event_id, user_id )
		local name = m.db.user_settings.use_character_name and m.player
		local class_name = m.db.user_settings[ m.db.events[ event_id ].templateId .. "_className" ]
		local spec_name = m.db.user_settings[ m.db.events[ event_id ].templateId .. "_specName" ]
		local channel_id = m.db.events[ event_id ].channelId

		broadcast( MessageCommand.Signup, {
			eventId = event_id,
			userId = user_id,
			className = class_name,
			specName = spec_name,
			channelId = channel_id,
			name = name
		} );
	end

	local function signup_edit( event_id, signup_id, role )
		local name = m.db.user_settings.use_character_name and m.player
		local class_name = role and role or m.db.user_settings[ m.db.events[ event_id ].templateId .. "_className" ]
		local spec_name = m.db.user_settings[ m.db.events[ event_id ].templateId .. "_specName" ]
		local channel_id = m.db.events[ event_id ].channelId

		broadcast( MessageCommand.SignupEdit, {
			eventId = event_id,
			signupId = signup_id,
			className = class_name,
			specName = spec_name,
			channelId = channel_id,
			name = name
		} )
	end

	local function group_thread_take_lead(event_id, user_id, title, start_time, take_over_from)
		broadcast( MessageCommand.GroupThreadTakeLead, {
			eventId = event_id,
			userId = user_id or "",
			title = title or "",
			startTime = start_time or 0,
			takeOverFromPlayer = take_over_from or "",
		} )
	end

	local function group_thread_set_assistant(event_id, user_id, assistant_player)
		broadcast( MessageCommand.GroupThreadSetAssistant, {
			eventId = event_id,
			userId = user_id or "",
			assistantPlayer = assistant_player or "",
		} )
	end

	local function group_thread_announce(event_id, user_id, title, start_time, lines)
		broadcast( MessageCommand.GroupThreadAnnounce, {
			eventId = event_id,
			userId = user_id or "",
			title = title or "",
			startTime = start_time or 0,
			lines = lines or {},
		} )
	end

	local function bot_status()
		-- Send directly to avoid ChatThrottle's startup delay
		if m.mark_bot_status_poll then m.mark_bot_status_poll() end
		SendAddonMessage( m.prefix, MessageCommand.RequestBotStatus .. "::", "GUILD" )
	end

	local function version_check( show_all )
		m.version_show_all = show_all or false
		broadcast( MessageCommand.VersionCheck )
	end

	---@param command string
	---@param data table
	---@param sender string

	-- ============================================================
	--  Raid Tracker : nouvelles fonctions de broadcast
	-- ============================================================

	local function raid_event( event_type, boss_name, duration, attempt, channel_id, raid_session )
		broadcast( MessageCommand.RaidEvent, {
			eventType   = event_type,
			bossName    = boss_name,
			duration    = duration,
			attempt     = attempt,
			channelId   = channel_id,
			raidSession = raid_session or "",
		} )
	end

	local function loot_assign( item_id, item_name, item_link, recipient, recipient_class, channel_id, raid_session )
		broadcast( MessageCommand.LootAssign, {
			itemId         = item_id or 0,
			itemName       = item_name,
			itemLink       = item_link,
			recipient      = recipient,
			recipientClass = recipient_class,
			channelId      = channel_id,
			raidSession    = raid_session or "",
		} )
	end

	local function raid_summary( raid_name, start_time, end_time, bosses_killed, total_wipes, loots, channel_id, raid_session )
		broadcast( MessageCommand.RaidSummary, {
			raidName     = raid_name,
			startTime    = start_time,
			endTime      = end_time,
			bossesKilled = bosses_killed,
			totalWipes   = total_wipes,
			loots        = loots,
			channelId    = channel_id,
			raidSession  = raid_session or "",
		} )
	end

	local function check_raid_role( user_id )
		broadcast( MessageCommand.RaidRoleCheck, { userId = user_id } )
	end


	-- ============================================================
	--  Gestion evenements : fonctions de broadcast
	-- ============================================================

	local function check_raider_role( user_id )
		broadcast( MessageCommand.RaiderRoleCheck, { userId = user_id } )
	end

	local function check_member_role( user_id )
		broadcast( MessageCommand.MemberRoleCheck, { userId = user_id } )
	end

	local function announce_local_event( data )
		broadcast( MessageCommand.LocalEventAnnounce, {
			title       = data.title,
			startTime   = data.startTime,
			description = data.description,
			location    = data.location,
			creator     = data.creator,
			eventKey    = data.eventKey or "",
		} )
	end

	local function local_event_create( data )
		broadcast( MessageCommand.LocalEventCreate, {
			title       = data.title,
			startTime   = data.startTime,
			description = data.description or "",
			location    = data.location or "",
			limit       = data.limit or 0,
			userId      = ( m.db and m.db.user_settings and m.db.user_settings.discord_id ) or "",
		} )
	end

	local function local_event_edit( data )
		broadcast( MessageCommand.LocalEventEdit, {
			id          = data.id,
			title       = data.title,
			startTime   = data.startTime,
			description = data.description,
			location    = data.location,
			limit       = data.limit or 0,
			userId      = ( m.db and m.db.user_settings and m.db.user_settings.discord_id ) or "",
		} )
	end

	local function local_event_delete( data )
		broadcast( MessageCommand.LocalEventDelete, {
			id     = data.id,
			userId = ( m.db and m.db.user_settings and m.db.user_settings.discord_id ) or "",
		} )
	end

	local function request_local_events()
		broadcast( MessageCommand.LocalEventList, {} )
	end

	local function local_event_signup( data )
		broadcast( MessageCommand.LocalEventSignup, {
			id        = data.id,
			className = data.className or "",
			specName  = data.specName  or "",
			status    = data.status    or "Signup",
			userId    = data.userId or ( m.db and m.db.user_settings and m.db.user_settings.discord_id ) or "",
		} )
	end

	local function local_event_unsignup( data )
		broadcast( MessageCommand.LocalEventUnsignup, {
			id           = data.id,
			targetPlayer = data.targetPlayer or "",
			userId       = data.userId or ( m.db and m.db.user_settings and m.db.user_settings.discord_id ) or "",
		} )
	end

	local function rf_data_request( url )
		broadcast( MessageCommand.RfDataRequest, {
			url = url,
		} )
	end

	local function raidres_create( data )
		broadcast( MessageCommand.RaidresCreate, {
			title       = data.title,
			raidId      = data.raidId,
			startTime   = data.startTime,
			description = data.description,
			limit             = data.limit,
			reservationLimit  = data.reservationLimit,
			channelId   = data.channelId,
		} )
	end

		local function create_event( data )
		broadcast( MessageCommand.CreateEvent, {
			title       = data.title,
			startTime   = data.startTime,
			description = data.description,
			channelId   = data.channelId,
			templateId  = data.templateId,
			limit             = data.limit,
			reservationLimit  = data.reservationLimit,
			locale      = data.locale,
		} )
	end

	local function edit_event( event_id, data )
		broadcast( MessageCommand.EditEvent, {
			eventId     = event_id,
			title       = data.title,
			startTime   = data.startTime,
			description = data.description,
			locale      = data.locale,
			limit             = data.limit,
			reservationLimit  = data.reservationLimit,
		} )
	end

	local function delete_event( event_id )
		broadcast( MessageCommand.DeleteEvent, {
			eventId = event_id,
		} )
	end


	local function group_plan_get( event_id, user_id )
		broadcast( MessageCommand.GroupPlanGet, {
			eventId = event_id,
			userId = user_id or "",
		} )
	end

	local function group_plan_save( event_id, user_id, plan )
		local encoded = encode_group_plan( plan )
		send_group_plan_chunks( event_id, user_id, encoded )
	end

	local function group_plan_clear( event_id, user_id )
		broadcast( MessageCommand.GroupPlanClear, {
			eventId = event_id,
			userId = user_id or "",
		} )
	end

	local function group_plan_watch( event_id, user_id, active )
		broadcast( MessageCommand.GroupPlanWatch, {
			eventId = event_id,
			userId = user_id or "",
			active = active and true or false,
		} )
	end

	local function on_command( command, data, sender )
		if command == MessageCommand.DiscordId then
			--
			-- Discord ID response
			--
			if data.player == m.player then
				if data.success then
					m.debug( "Saving Discord ID: " .. data.userId )
					m.db.user_settings.discord_id = data.userId
				end
				m.calendar_popup.discord_response( data.success, data.userId )
				m.welcome_popup.discord_response( data.success, data.userId )
			end
		elseif command == MessageCommand.ChannelCheckResult then
			--
			-- Channel access result
			--
			if data.player == m.player then
				m.db.user_settings.channel_access[ data.channelId ] = data.success
				m.event_popup.update()
			end
		elseif command == MessageCommand.DiscordAuth then
			--
			-- Discord authentication response
			--
			if data.player == m.player then
				m.debug( "Saving Discord ID: " .. data.userId )
				m.db.user_settings.discord_id = data.userId
				m.welcome_popup.auth_response( data.userId, data.success )
				-- Mettre a jour l'UI du calendar popup si visible
				if m.calendar_popup and m.calendar_popup.auth_response then
					m.calendar_popup.auth_response( data.userId, data.success )
				end
			end
		elseif command == MessageCommand.SR then
			--
			-- SR
			--
			data = decode( data, key_map, value_map )

			if data.success and data.success == false then
				m.error( data.status )
				return
			end

			local _, event_id = m.find( data.reference, m.db.events, "srId" )
			if event_id then
				m.db.events[ event_id ].sr = data
				m.db.events[ event_id ].sr.lastUpdated = time()
				m.sr_popup.update( event_id )
				m.calendar_popup.update()
			end
		elseif command == MessageCommand.AddSRResult then
			--
			-- SR Added
			--
			data = decode( data, key_map, value_map )

			if data.success then
				m.debug( "SR Added" )
				local _, event_id = m.find( data.srId, m.db.events, "srId" )
				if not event_id then
					m.debug( "SR added but no event found for it!" )
					return
				end

				if data.addedSRs and type( data.addedSRs ) == "table" then
					if m.db.events[ event_id ].sr and m.db.events[ event_id ].sr.reservations then
						for _, res in pairs( data.addedSRs ) do
							if not m.find( res.id, m.db.events[ event_id ].sr.reservations, "id" ) then
								table.insert( m.db.events[ event_id ].sr.reservations, {
									id = res.id,
									raidItemId = res.raidItemId,
									srPlus = res.srPlus,
									comment = res.comment,
									character = res.character
								} )
							end
						end
					end
				end

				m.sr_popup.update( event_id )
				m.calendar_popup.update()
			elseif data.player == m.player then
				m.error( "Adding SR failed: " .. (data.status or "Unknown error") )
			end
		elseif command == MessageCommand.DeleteSRResult then
			--
			-- SR Deleted
			--
			data = decode( data, key_map, value_map )

			if data.success == true then
				for event_id, event in pairs( m.db.events ) do
					if event.sr then
						local _, k = m.find( data.id, event.sr.reservations, "id" )
						if k then
							m.debug( "Delete entry: " .. tostring( k ) .. " in " .. event_id )
							table.remove( event.sr.reservations, k )
							m.sr_popup.update()
							m.calendar_popup.update()
							return
						end
					end
				end
			elseif data.player == m.player then
				m.error( "Delete SR failed: " .. (data.status or "Unknown error") )
			end
		elseif command == MessageCommand.LockSRResult then
			--
			-- SRLOCK_RESULT
			--
			data = decode( data, key_map, value_map )
			if data.success == true then
				local _, eventId = m.find( data.srId, m.db.events, "srId")
				if m.db.events[ eventId ] and m.db.events[ eventId ].sr then
					m.db.events[ eventId ].sr.locked = data.locked
				end

				m.sr_popup.update()
			elseif data.player == m.player then
				m.error( "Lock SR failed: " .. (data.status or "Unknown error") )
			end
		elseif command == MessageCommand.Event then
			--
			-- EVENT
			--
			data = decode( data, key_map, value_map )
			m.debug( "Got event id: " .. data.id )

			if m.db.events[ data.id ] and m.db.events[ data.id ].sr then
				local sr = m.db.events[ data.id ].sr
				m.db.events[ data.id ] = data
				m.db.events[ data.id ].sr = sr
			else
				m.db.events[ data.id ] = data
			end

			local sr_ref = string.match( m.db.events[ data.id ].description, "https://raidres%.top/res/(%w+)%s?" )
			m.db.events[ data.id ].srId = sr_ref
			m.db.events[ data.id ].title = string.gsub( m.db.events[ data.id ].title, "<:.*>", "" )

			m.event_popup.update( data.id )
			if m.GroupPopup then m.GroupPopup.update( data.id ) end
			m.calendar_popup.update()
		elseif command == MessageCommand.EventsUpdate then
			if data and data.version then
				local version = tonumber( data.version ) or 0
				local current_version = tonumber( m.db.user_settings.events_version ) or 0
				if version > current_version then
					m.db.user_settings.events_version = version
					request_events( true )
				end
			else
				request_events( true )
			end
		elseif command == MessageCommand.Events then
			--
			-- EVENTS
			--
			events_request_in_flight = false
			data = decode( data, key_map, value_map )
			if data.version then
				m.db.user_settings.events_version = tonumber( data.version ) or m.db.user_settings.events_version
			end
			if data.error then
				m.error( data.error )
				return
			end

			if data.events then
				m.debug( "Receiving events requested by " .. (data.player or "UNKNOWN") )
				for _, event in pairs( data.events ) do
					if not event or not event.id then
						-- skip malformed entries
					elseif m.db.events[ event.id ] then
						-- Only send event update request from player who requested it if needed
						if event.lastUpdated and m.db.events[ event.id ].lastUpdated and
						   event.lastUpdated > m.db.events[ event.id ].lastUpdated and
						   data.player == m.player then
							m.debug( "Update event: " .. tostring( event.title ) )
							request_event( event.id )
						end
					else
						m.debug( "New event: " .. tostring( event.title ) )
						event.title = event.title and string.gsub( event.title, "<:.*>", "" ) or ""
						m.db.events[ event.id ] = event
					end
				end
			end

			-- Remove old and deleted raids.
			-- Build a O(1) lookup set first so the removal scan is O(n) instead of O(n²).
			-- Collect IDs to remove, then delete — never modify a table while iterating it.
			local incoming_ids = {}
			for _, ev in pairs( data.events or {} ) do
				if ev.id then incoming_ids[ ev.id ] = true end
			end
			local to_remove = {}
			for id, event in pairs( m.db.events ) do
				if not incoming_ids[ id ] then
					m.debug( "Remove event: " .. tostring( event.title ) )
					to_remove[ id ] = true
				end
			end
			for id in pairs( to_remove ) do
				m.db.events[ id ] = nil
			end

			m.db.user_settings.last_updated = time()
			m.calendar_popup.update()
		elseif command == MessageCommand.SignupResult then
			--
			-- SIGNUP_RESULT
			--
			data = decode( data, key_map, value_map )
			if data.success and m.db.events[ data.eventId ] then
				if data.signUp then
					local _, index = m.find( data.signUp.id, m.db.events[ data.eventId ].signUps, "id" )

					m.db.events[ data.eventId ].lastUpdated = tonumber( data.lastUpdated )
					if index then
						m.db.events[ data.eventId ].signUps[ index ] = data.signUp
					else
						table.insert( m.db.events[ data.eventId ].signUps, data.signUp )
					end
				else
					-- signUp absent dans la réponse, on redemande l'event complet
					request_event( data.eventId )
				end

				m.calendar_popup.update()
				m.event_popup.update( data.eventId )
			elseif data.player == m.player then
				m.error( "Signup failed: " .. ( data.status or "Unknown error" ) )
			end
		elseif command == MessageCommand.BotStatus then
			--
			-- Receive bot status
			--
			if data.player == m.player then
				m.db.user_settings.bot_name = data.botName
				m.db.user_settings.discord_bot = data.discordBot
				m.db.user_settings.sr_admins = data.srAdmins
				m.welcome_popup.bot_response( data.botName )
				-- Bot just responded = it's online. Set immediately, no roster lookup needed.
				if m.set_bot_online then m.set_bot_online( true ) end
				-- Update online indicator in calendar popup if it's open
				if m.calendar_popup and m.calendar_popup.update then
					m.calendar_popup.update()
				end
			end
		elseif command == MessageCommand.VersionCheck then
			--
			-- Receive version request
			--
			broadcast( MessageCommand.Version, { requester = sender, version = m.version, class = m.player_class } )
		elseif command == MessageCommand.RaidresCreateResult then
		if data.player == m.player then
			if m.EventManagePopup then
				m.EventManagePopup.on_create_result( data.success == true, data.eventId, data.status )
			end
			if data.success then m.msg.request_events( true ) end
		end
	elseif command == MessageCommand.RfDataResult then
		--
		-- RF_DATA_RESULT
		--
		if data.player == m.player then
			if m.GroupPopup and m.GroupPopup.on_rf_data_result then
				m.GroupPopup.on_rf_data_result( data.success == true, data.rfData, data.status )
			end
		end
	elseif command == MessageCommand.CreateEventResult then
		--
		-- CREATE_EVENT_RESULT
		--
		if data.player == m.player then
			if m.EventManagePopup then
				m.EventManagePopup.on_create_result( data.success == true, data.eventId, data.status )
			end
			if data.success then
				m.msg.request_events( true )
			end
		end
	elseif command == MessageCommand.EditEventResult then
		--
		-- EDIT_EVENT_RESULT
		--
		if data.player == m.player then
			if m.EventManagePopup then
				m.EventManagePopup.on_edit_result( data.success == true, data.eventId, data.status )
			end
		end
	elseif command == MessageCommand.DeleteEventResult then
		--
		-- DELETE_EVENT_RESULT
		--
		if data.player == m.player then
			if m.EventManagePopup then
				m.EventManagePopup.on_delete_result( data.success == true, data.eventId, data.status )
			end
		end
	elseif command == MessageCommand.CleanupLocalEvents then
		--
		-- CLEANUP_LOCAL_EVENTS - demande de nettoyage des anciens events locaux
		-- Seul un manager peut déclencher ceci
		--
		if data.player == m.player then
			if m.LocalEventManager then
				m.LocalEventManager.cleanup_old()
				m.info( "|cffFFD700[RaidCalendar]|r " .. ( m.L and m.L( "ui.cleanup_done" ) or "Old local events cleaned up." ) )
				m.calendar_popup.update()
			end
		end

	elseif command == MessageCommand.LocalSignupResult then
		--
		-- LOCAL_SIGNUP_RESULT — réponse à signup / unsignup
		-- Supporte :
		--   1) ancien format avec data.eventData
		--   2) format léger avec seulement eventId + action
		--
		data = decode( data, key_map, value_map )
		if type( data.eventData ) == "string" then
			local parsed_event, parse_error = safe_eval_lua_data( data.eventData )
			if parsed_event ~= nil then
				data.eventData = parsed_event
			elseif m.debug then
				m.debug( "LOCAL_SIGNUP_RESULT eventData parse error: " .. tostring( parse_error ) )
			end
		end
		if type( data.eventData ) == "table" then
			data.eventData = decode( data.eventData, key_map, value_map )
		end

		if data.success then
			if type( data.eventData ) == "table" then
				if m.LocalEventManager then
					m.LocalEventManager.cache_upsert( data.eventData )
				end
			else
				if m.msg and m.msg.request_local_events then
					m.msg.request_local_events()
				end
			end

			if m.LocalEventPopup then
				m.LocalEventPopup.update( data.eventId or ( data.eventData and data.eventData.id ) )
			end
			if m.calendar_popup then
				m.calendar_popup.update()
			end
		elseif data.player == m.player then
			m.error( "|cffFF4444[Local]|r " .. ( data.status or ( m.L and m.L( "event_manage.unknown_error" ) ) or "Unknown error" ) )
			if m.LocalEventPopup then
				m.LocalEventPopup.on_signup_error( data.status )
			end
		end

	elseif command == MessageCommand.LocalEventsList then
		--
		-- LOCAL_EVENTS_LIST — liste complète des événements actifs reçue du bot
		-- Remplace le cache local et rafraîchit le calendrier
		--
		data = decode( data, key_map, value_map )
		if m.LocalEventManager and data.events and ( not data.player or data.player == m.player ) then
			local list = {}
			for _, ev in pairs( data.events or {} ) do
				local decoded_event = decode( ev, key_map, value_map )
				if decoded_event then
					table.insert( list, decoded_event )
				end
			end
			m.LocalEventManager.load_from_bot( list )
			if m.calendar_popup then
				m.calendar_popup.update()
			end
			-- Rafraîchir la popup locale si elle est ouverte
			if m.LocalEventPopup and m.LocalEventPopup.refresh_current then
				m.LocalEventPopup.refresh_current()
			end
		end

	elseif command == MessageCommand.LocalEventResult then
		--
		-- LOCAL_EVENT_RESULT — réponse à create / edit / delete
		--
		data = decode( data, key_map, value_map )
		if not data.player or data.player == m.player then
			if data.success then
				local action = data.action or ""

				if action == "created" or action == "edited" then
					-- Mettre à jour le cache local avec les données retournées
					if m.LocalEventManager then
						m.LocalEventManager.cache_upsert({
							id          = data.eventId,
							title       = data.title,
							startTime   = data.startTime,
							description = data.description or "",
							location    = data.location or "",
							creator     = data.creator,
							createdAt   = data.createdAt or time(),
						})
					end
					if m.calendar_popup then m.calendar_popup.update() end
					if m.EventManagePopup then
						local status = action == "created"
							and m.L( "event_manage.status_created" )
							or  m.L( "event_manage.status_saved" )
						m.EventManagePopup.on_local_result( true, action, data.eventId, status )
					end

				elseif action == "deleted" then
					if m.LocalEventManager then
						m.LocalEventManager.cache_remove( data.eventId )
					end
					if m.calendar_popup then m.calendar_popup.update() end
					if m.EventManagePopup then
						m.EventManagePopup.on_local_result( true, action, data.eventId,
							m.L( "event_manage.status_deleted" ) )
					end
				end
			else
				-- Erreur retournée par le bot
				if m.EventManagePopup then
					m.EventManagePopup.on_local_result( false, nil, nil, data.status or ( m.L and m.L( "event_manage.unknown_error" ) ) or "Unknown error" )
				end
				m.error( "|cffFF4444[Local]|r " .. ( data.status or ( m.L and m.L( "event_manage.unknown_error" ) ) or "Unknown error" ) )
			end
		end
	elseif command == MessageCommand.MemberRoleResult then
		--
		-- MEMBER_ROLE_RESULT - role de creation d'evenement local
		--
		if data.player == m.player then
			if m.db then
				m.db.user_settings.has_member_role = data.success == true
				-- Rafraîchir LocalEventPopup si ouvert
				if m.LocalEventPopup and m.LocalEventPopup.refresh_current then
					m.LocalEventPopup.refresh_current()
				end
				m.db.user_settings.role_check_debug = {
					character = data.character,
					linked_user_id = data.linkedUserId,
					requested_user_id = data.requestedUserId,
					status = data.status,
				}
			end
			if m.EventManagePopup and m.EventManagePopup.on_member_role_result then
				m.EventManagePopup.on_member_role_result( data.success == true, data.status, data.linkedUserId, data.requestedUserId, data.character )
			end
		end
	elseif command == MessageCommand.RaiderRoleResult then
		--
		-- RAIDER_ROLE_RESULT — rôle inscription events Raid-Helper
		--
		if data.player == m.player then
			if m.db then
				m.db.user_settings.has_raider_role = data.success == true
			end
			-- Rafraîchir EventPopup si ouvert
			if m.EventPopup and m.EventPopup.refresh_current then
				m.EventPopup.refresh_current()
			end
		end

	elseif command == MessageCommand.RaidRoleResult then
		--
		-- RAID_ROLE_RESULT
		--
		if data.player == m.player then
			if m.db then
				m.db.user_settings.role_check_debug = {
					character = data.character,
					linked_user_id = data.linkedUserId,
					requested_user_id = data.requestedUserId,
					status = data.status,
				}
			end
			if m.RaidTracker then
				m.RaidTracker.on_role_result( data.success == true, data.status, data.linkedUserId, data.requestedUserId, data.character )
			end
		end

	elseif command == MessageCommand.GroupPlanResult then
		data = decode( data, key_map, value_map )
		if data.eventId then
			data.plan = decode_group_plan( data.planEncoded or "" )
			m.db.group_plans = m.db.group_plans or {}
			m.db.group_plans[ data.eventId ] = data.plan or {}

			if m.GroupPopup and m.GroupPopup.on_remote_result then
				m.GroupPopup.on_remote_result( data )
			end
		end
	elseif command == MessageCommand.GroupThreadResult then
		data = decode( data, key_map, value_map )
		m.db.group_thread_contexts = m.db.group_thread_contexts or {}
		if data.eventId then
			local group_key = data.groupKey or data.managerDiscordUserId or data.threadId or "__default__"
			m.db.group_thread_contexts[ data.eventId ] = m.db.group_thread_contexts[ data.eventId ] or {}
			m.db.group_thread_contexts[ data.eventId ][ group_key ] = {
				groupKey = group_key,
				managerPlayer = data.managerPlayer,
				managerDiscordUserId = data.managerDiscordUserId,
				assistantPlayer = data.assistantPlayer,
				assistantDiscordUserId = data.assistantDiscordUserId,
				threadId = data.threadId,
				threadTitle = data.threadTitle,
			}
		end
		if m.GroupPopup and m.GroupPopup.on_group_thread_result then
			m.GroupPopup.on_group_thread_result( data )
		end
	elseif command == MessageCommand.Version then
			--
			-- Receive version
			--
			if data.requester == m.player and m.version_show_all then
				m.info( string.format( "%s [v%s]", m.colorize_player_by_class( sender, data.class ), data.version ), true )
				return
			end

			if not m.db.user_settings.last_versioncheck or time() - m.db.user_settings.last_versioncheck > 3600 * 24 then
				m.db.user_settings.last_versioncheck = time()
				if m.is_new_version( m.version, data.version ) then
					m.info( string.format( "New version (%s) is available!", data.version ) )
					m.info( "https://github.com/sica42/RaidCalendar" )
				end
			end
		end
	end

	local function safe_eval_lua_data( source )
		-- Un payload vide (commande sortante d'un autre joueur) retourne une table vide
		if not source or source == "" then
			return {}, nil
		end

		local loader = loadstring or load
		if not loader then
			return nil, "No loader available"
		end

		local fn, err = loader( "return " .. source )
		if not fn then
			return nil, err
		end

		local ok, result = pcall( fn )
		if not ok then
			return nil, result
		end

		return result, nil
	end

	local function get_chunk_state( sender )
		if not sender or sender == "" then
			sender = "__unknown__"
		end
		if not chunk_state_by_sender[ sender ] then
			chunk_state_by_sender[ sender ] = {
				total = 0,
				data = nil,
			}
		end
		return chunk_state_by_sender[ sender ]
	end

	local function should_refresh_bot_heartbeat( command, sender )
	local bot_name = m.db and m.db.user_settings and m.db.user_settings.bot_name or nil
	if sender and bot_name and string.lower( sender ) == string.lower( bot_name ) then
		return true
	end

	if command == "RC_BOT_ONLINE" or command == MessageCommand.BotStatus then
		return true
	end

	if command == MessageCommand.DiscordId or command == MessageCommand.DiscordAuth
		or command == MessageCommand.ChannelCheckResult
		or command == MessageCommand.Event or command == MessageCommand.Events
		or command == MessageCommand.EventsUpdate
		or command == MessageCommand.SignupResult or command == MessageCommand.SR
		or command == MessageCommand.AddSRResult or command == MessageCommand.DeleteSRResult
		or command == MessageCommand.LockSRResult or command == MessageCommand.Version
		or command == MessageCommand.RaidRoleResult or command == MessageCommand.RaiderRoleResult
		or command == MessageCommand.MemberRoleResult
		or command == MessageCommand.LocalEventResult or command == MessageCommand.LocalEventsList
		or command == MessageCommand.LocalSignupResult or command == MessageCommand.RaidresCreateResult
		or command == MessageCommand.CreateEventResult or command == MessageCommand.EditEventResult
		or command == MessageCommand.DeleteEventResult or command == MessageCommand.GroupPlanResult
		or command == MessageCommand.GroupThreadResult then
		return true
	end

	return false
end

	local function on_comm_received( prefix, data_str, _, sender )
		local state
		if prefix ~= m.prefix or sender == m.player then return end
		if not data_str or type( data_str ) ~= "string" then return end
		local cmd_pat = "^([_%u%d]-)::"

		local command = string.match( data_str, cmd_pat )
		data_str = string.gsub( data_str, cmd_pat, "" )

		if command then
			if should_refresh_bot_heartbeat( command, sender ) and m.touch_bot_heartbeat then
				m.touch_bot_heartbeat()
			end
			-- Bot heartbeat — handle directly, no data parsing needed
			if command == "RC_BOT_ONLINE" then
				if m.set_bot_online then m.set_bot_online( true ) end
				if m.calendar_popup and m.calendar_popup.update then m.calendar_popup.update() end
				return
			elseif command == "RC_BOT_OFFLINE" then
				if m.set_bot_online then m.set_bot_online( false ) end
				if m.calendar_popup and m.calendar_popup.update then m.calendar_popup.update() end
				return
			end
			state = get_chunk_state( sender )
			if command == "CT" then
				state.total = tonumber( data_str ) or 0
				state.data = nil
			elseif string.find( command, "^C%d+$" ) then
				local chunk_number = tonumber( string.match( command, "C(%d+)" ) ) or 0
				if chunk_number <= 1 then
					state.data = data_str
				else
					state.data = ( state.data or "" ) .. data_str
				end

				if state.total > 0 and chunk_number == state.total then
					local payload = state.data or ""
					local cmd = string.match( payload, cmd_pat )
					payload = string.gsub( payload, cmd_pat, "" )
					state.total = 0
					state.data = nil

					local lua_data, parse_error = safe_eval_lua_data( payload )
					if lua_data ~= nil and cmd then
						local ok_cmd, cmd_err = pcall( on_command, cmd, lua_data, sender )
						if not ok_cmd then m.debug( "RCERROR in handler [" .. tostring(cmd) .. "]: " .. tostring(cmd_err) ) end
					else
						m.error( "RCERROR [chunked " .. tostring(cmd) .. "]: Invalid data" )
						if parse_error then
							m.debug( "Parse error: " .. tostring( parse_error ) )
						end
						m.debug( "Payload (first 200): " .. string.sub( tostring(payload), 1, 200 ) )
					end
				end
			else
				local lua_data, parse_error = safe_eval_lua_data( data_str )
				if lua_data ~= nil then
					local ok_cmd, cmd_err = pcall( on_command, command, lua_data, sender )
					if not ok_cmd then m.debug( "RCERROR in handler [" .. tostring(command) .. "]: " .. tostring(cmd_err) ) end
				else
					m.error( "RCERROR [" .. tostring(command) .. "]: Invalid data" )
					if parse_error then
						m.debug( "Parse error: " .. tostring( parse_error ) )
					end
					m.debug( "Data (first 200): " .. string.sub( tostring(data_str), 1, 200 ) )
				end
			end
		else
			m.debug( "No command, wtf?" )
		end
	end

	ace_comm.RegisterComm( M, m.prefix, on_comm_received )

	---@type MessageHandler
	return {
		find_discord_id = find_discord_id,
		check_channel_access = check_channel_access,
		authorize_user = authorize_user,
		add_sr = add_sr,
		delete_sr = delete_sr,
		lock_sr = lock_sr,
		request_sr = request_sr,
		request_event = request_event,
		request_events = request_events,
		signup = signup,
		signup_edit = signup_edit,
		bot_status = bot_status,
		version_check   = version_check,
		raid_event      = raid_event,
		loot_assign     = loot_assign,
		raid_summary    = raid_summary,
		check_raid_role = check_raid_role,
		check_raider_role    = check_raider_role,
		check_member_role    = check_member_role,
		announce_local_event = announce_local_event,
		local_event_create   = local_event_create,
		local_event_edit     = local_event_edit,
		local_event_delete   = local_event_delete,
		request_local_events = request_local_events,
		local_event_signup   = local_event_signup,
		local_event_unsignup = local_event_unsignup,
		raidres_create  = raidres_create,
		rf_data_request = rf_data_request,
				create_event    = create_event,
		edit_event      = edit_event,
		delete_event    = delete_event,
		group_plan_get  = group_plan_get,
		group_plan_save = group_plan_save,
		group_plan_clear = group_plan_clear,
		group_plan_watch = group_plan_watch,
		group_thread_take_lead = group_thread_take_lead,
		group_thread_set_assistant = group_thread_set_assistant,
		group_thread_announce = group_thread_announce
	}
end

m.MessageHandler = M
return M