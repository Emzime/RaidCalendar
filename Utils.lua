RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local M = RaidCalendar

local bot_online
local bot_check_time = 0
local bot_last_seen = 0
local bot_poll_time = 0
local bot_heartbeat_interval_seconds = 10
local bot_online_threshold_seconds = 15
local bot_degraded_threshold_seconds = 25
local bot_timeout_seconds = bot_degraded_threshold_seconds

function M.reset_bot_status_cache()
	bot_check_time = 0
	bot_last_seen = 0
	bot_poll_time = 0
	bot_online = nil
end

-- Called when RC_BOT_ONLINE is received (BSTATUS or heartbeat).
function M.set_bot_online( online )
	bot_online = online and true or false
	if bot_online then
		bot_last_seen = time()
	elseif not bot_online then
		bot_last_seen = 0
	end
end

function M.mark_bot_status_poll()
	bot_poll_time = time()
end

function M.get_bot_status_poll_time()
	return bot_poll_time or 0
end

function M.get_bot_last_seen()
	return bot_last_seen or 0
end

function M.get_bot_timeout_seconds()
	return bot_timeout_seconds
end

function M.get_bot_heartbeat_interval_seconds()
	return bot_heartbeat_interval_seconds
end

function M.touch_bot_heartbeat()
	bot_online = true
	bot_last_seen = time()
end

function M.get_bot_state()
	if bot_online == false then
		return "OFFLINE"
	end

	if bot_last_seen <= 0 then
		return "OFFLINE"
	end

	local elapsed = time() - bot_last_seen

	if elapsed <= bot_online_threshold_seconds then
		return "ONLINE"
	elseif elapsed <= bot_degraded_threshold_seconds then
		return "DEGRADED"
	else
		bot_online = false
		return "OFFLINE"
	end
end

function M.get_bot_status_label_key()
	local state = M.get_bot_state()
	if state == "ONLINE" then
		return "ui.online"
	elseif state == "DEGRADED" then
		return "ui.degraded"
	end
	return "ui.offline"
end

--- @param hex string
--- @return number r
--- @return number g
--- @return number b
--- @return number a
function M.hex_to_rgba( hex )
	local r, g, b, a = string.match( hex, "^#?(%x%x)(%x%x)(%x%x)(%x?%x?)$" )

	r, g, b = tonumber( r, 16 ) / 255, tonumber( g, 16 ) / 255, tonumber( b, 16 ) / 255
	a = a ~= "" and tonumber( a, 16 ) / 255 or 1
	return r, g, b, a
end

---@param name string
---@param class string
---@return string
function M.colorize_player_by_class( name, class )
	if not class then return name end
	local color = RAID_CLASS_COLORS[ string.upper( class ) ]
	if not color.colorStr then
		color.colorStr = string.format( "ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255 )
	end
	return "|c" .. color.colorStr .. name .. "|r"
end

---@param diff number
---@return string
function M.format_time_difference( diff )
	local abs_diff = math.abs( diff )

	if abs_diff >= 86400 then
		local count = math.floor( abs_diff / 86400 )
		if diff < 0 then
			return RaidCalendar.L( count == 1 and "time.days_ago_one" or "time.days_ago_many", { count = count } )
		else
			return RaidCalendar.L( count == 1 and "time.in_days_one" or "time.in_days_many", { count = count } )
		end
	elseif abs_diff >= 3600 then
		local count = math.floor( (abs_diff + 1800) / 3600 )
		if diff < 0 then
			return RaidCalendar.L( count == 1 and "time.hours_ago_one" or "time.hours_ago_many", { count = count } )
		else
			return RaidCalendar.L( count == 1 and "time.in_hours_one" or "time.in_hours_many", { count = count } )
		end
	else
		local count = math.floor( (abs_diff + 30) / 60 )
		if diff < 0 then
			return RaidCalendar.L( count == 1 and "time.minutes_ago_one" or "time.minutes_ago_many", { count = count } )
		else
			return RaidCalendar.L( count == 1 and "time.in_minutes_one" or "time.in_minutes_many", { count = count } )
		end
	end
end

---@return number r
---@return number g
---@return number b
---@return number a
---@nodiscard
function M.bot_online_status()
	local state = M.get_bot_state()

	if state == "ONLINE" then
		return 0, 1, 0, 0.9
	elseif state == "DEGRADED" then
		return 1, 0.65, 0, 0.9
	end

	return 1, 0, 0, 0.9
end

---@param value string|number
---@param t table
---@param extract_field string?
function M.find( value, t, extract_field )
	-- Simple nil/type guard only — M.count() would iterate the whole table
	-- just to check emptiness, which is wasteful before the loop that follows.
	if type( t ) ~= "table" then return nil end

	for i, v in pairs( t ) do
		local val = extract_field and v[ extract_field ] or v
		if val == value then return v, i end
	end

	return nil
end

function M.wipe( tbl )
	if type( tbl ) ~= "table" then return end

	for k in pairs( tbl ) do
		tbl[ k ] = nil
	end
end

---@param t table
---@return number
function M.count( t )
	local count = 0
	for _ in pairs( t ) do
		count = count + 1
	end

	return count
end

---@param item_name string
---@param item_quality string
---@return string
function M.get_item_name_colorized( item_name, item_quality )
	local color = ITEM_QUALITY_COLORS[ item_quality ]
	local link = color.hex .. item_name .. "|r"

	return link
end

function M.capitalize_words( str )
	return string.gsub( str, "(%w)(%w*)", function( first, rest )
		return string.upper( first ) .. string.lower( rest )
	end )
end

--- Parse a "r, g, b" color string and cache the result on the event object.
--- Prevents repeated string.gmatch allocation on every render call.
--- Result is stored in ev._rgb and auto-invalidated when the event object is replaced.
---@param ev table
---@return table rgb  {[1]=r, [2]=g, [3]=b}  each in [0,1]
function M.get_event_color( ev )
	if ev._rgb then return ev._rgb end
	local parts = {}
	for c in string.gmatch( ev.color or "", "%s*([^,]+)%s*" ) do
		table.insert( parts, c )
	end
	ev._rgb = {
		(tonumber( parts[1] ) or 120) / 255,
		(tonumber( parts[2] ) or 120) / 255,
		(tonumber( parts[3] ) or 120) / 255,
	}
	return ev._rgb
end

function M.is_new_version( mine, theirs )
  local function parse_version( v )
    local parts = {}

    for part in string.gmatch( v, "%d+" ) do
      table.insert( parts, tonumber( part ) )
    end

    return parts
  end

  local my_version = parse_version( mine )
  local their_version = parse_version( theirs )

  for i = 1, math.max( getn( my_version ), getn( their_version ) ) do
    local my_part = my_version[ i ] or 0
    local their_part = their_version[ i ] or 0

    if their_part > my_part then
      return true
    elseif their_part < my_part then
      return false
    end
  end

  return false
end

---@param message string
---@param short boolean?
function M.info( message, short )
	local tag = string.format( "|c%s%s|r", M.tagcolor, short and "RC" or "RaidCalendar" )
	DEFAULT_CHAT_FRAME:AddMessage( string.format( "%s: %s", tag, message ) )
end

---@param message string
function M.error( message )
	local tag = string.format( "|c%s%s|r|cffff0000%s|r", M.tagcolor, "RC", "ERROR" )
	DEFAULT_CHAT_FRAME:AddMessage( string.format( "%s: %s", tag, message ) )
end

---@param message string
function M.debug( message )
	if M.debug_enabled then
		M.info( message, true )
	end
end

---@param o any
---@return string
function M.dump( o )
	--if not o then return "nil" end
	if type( o ) ~= 'table' then return tostring( o ) end

	local entries = 0
	local s = "{"

	for k, v in pairs( o ) do
		if (entries == 0) then s = s .. " " end

		local key = type( k ) ~= "number" and '"' .. k .. '"' or k

		if (entries > 0) then s = s .. ", " end

		s = s .. "[" .. key .. "] = " .. M.dump( v )
		entries = entries + 1
	end

	if (entries > 0) then s = s .. " " end
	return s .. "}"
end

function M.is_array( t )
	local count = 0
	for k, _ in pairs( t ) do
		if type( k ) ~= "number" then return false end
		count = count + 1
	end
	for i = 1, count do
		if t[ i ] == nil then return false end
	end
	return true
end

function M.flatten( value )
	local value_type = type( value )

	if value_type == "table" then
		if M.is_array( value ) then
			-- JSON array
			local items = {}
			for i = 1, getn(value) do
				table.insert( items, M.flatten( value[ i ] ) )
			end
			return "{" .. table.concat( items, ",	" ) .. "}"
		else
			-- JSON object
			local items = {}
			for k, v in pairs( value ) do
				table.insert( items, '["' .. tostring( k ) .. '"]=' .. M.flatten( v ) )
			end
			return "{" .. table.concat( items, "," ) .. "}"
		end
	elseif value_type == "string" then
		return '"' .. string.gsub(value, '"', '\\"' ) .. '"'
	elseif value_type == "number" or value_type == "boolean" then
		return tostring( value )
	elseif value_type == "nil" then
		return "null"
	end

	error( "Unsupported type: " .. value_type )
end

---@diagnostic disable-next-line: undefined-field
if not string.gmatch then string.gmatch = string.gfind end

---@diagnostic disable-next-line: duplicate-set-field
string.match = function( str, pattern )
	if not str then return nil end

	local _, _, r1, r2, r3, r4, r5, r6, r7, r8, r9 = string.find( str, pattern )
	return r1, r2, r3, r4, r5, r6, r7, r8, r9
end

---@diagnostic disable-next-line: lowercase-global
---@return string
strtrim = strtrim or function( s )
	if type( s ) ~= "string" then
		return ""
	end
	return string.match( s, "^%s*(.-)%s*$" )
end

math.huge = 1e99
