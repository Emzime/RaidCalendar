RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.MinimapIcon then return end

---@class MinimapIcon


local M = {}

function M.new()
	local ldb = LibStub:GetLibrary( "LibDataBroker-1.1" )
	local icon = LibStub:GetLibrary( "LibDBIcon-1.0" )

	local data = {
		type = "data source",
		label = m.name,
		icon = "Interface\\AddOns\\RaidCalendar\\assets\\icon.tga",
		tocname = m.name
	}

	local obj = ldb:NewDataObject( "Broker_RaidCalendar", data ) ---[[@as LibDataBroker.DataDisplay]]

	local function group_by_day( sorted_events )
		local grouped = {}
		local now = time()
		local today = date( "*t", now )
		local tomorrow = date( "*t", now + 86400 )

		for _, event in ipairs( sorted_events ) do
			local eventTime = event.startTime
			local dt = date( "*t", eventTime )

			local label
			if dt.year == today.year and dt.yday == today.yday then
				label = m.L and m.L( "actions.today" ) or "Today"
			elseif dt.year == tomorrow.year and dt.yday == tomorrow.yday then
				label = m.L and m.L( "ui.tomorrow" ) or "Tomorrow"
			elseif eventTime - now > 604800 then
				label = m.L and m.L( "ui.in_distant_future" ) or "In the distant future"
			else
				local day = m.get_day_name( (tonumber( date( "%w", eventTime ) ) or 0) + 1, false )
				label = day and (string.upper( string.sub( day, 1, 1 ) ) .. string.sub( day, 2 )) or day
			end

			-- O(1) lookup via direct table key instead of m.find() O(n) scan
			if not grouped[ label ] then
				grouped[ label ] = { label = label, entries = {}, _order = getn( grouped ) + 1 }
				table.insert( grouped, grouped[ label ] )
			end

			table.insert( grouped[ label ].entries, event )
		end

		return grouped
	end

	-- Cache the tooltip grouping for 5 seconds.
	-- OnTooltipShow fires on every mouse-over — recomputing group_by_day each time
	-- means iterating all events + O(n) find() per event on every hover.
	local _tooltip_cache = nil
	local _tooltip_cache_time = 0

	function obj.OnTooltipShow( self )
		local events = {}
		local now = time( date( "*t" ) )

		for k, v in pairs( m.db.events ) do
			if v.startTime - now > 0 then
				table.insert( events, { key = k, startTime = v.startTime } )
			end
		end

		table.sort( events, function( a, b )
			return a.startTime < b.startTime
		end )

		-- Rebuild grouped data only when stale (> 5s) or event list changed size
		local n = getn( events )
		if not _tooltip_cache or GetTime() - _tooltip_cache_time > 5 or _tooltip_cache._n ~= n then
			_tooltip_cache = group_by_day( events )
			_tooltip_cache._n = n
			_tooltip_cache_time = GetTime()
		end

		self:AddLine( m.L and m.L( "ui.upcoming_raids" ) or "Upcoming raids" )
		self:AddLine( " " )

		for _, group in ipairs( _tooltip_cache ) do
			self:AddLine( group.label )
			for _, e in ipairs( group.entries ) do
				local event = m.db.events[ e.key ]
				if event then
					local start_time = date( m.time_format, event.startTime )
					self:AddLine( string.format( "  - %s |cffffffff[%s]|r", m.capitalize_words( event.title ), start_time ) )
				end
			end
		end
	end

	function obj:OnClick( button )
		if button == "LeftButton" then
			if m.api.IsShiftKeyDown() then
				m.event_popup.toggle()
			elseif m.api.IsControlKeyDown() then
				m.sr_popup.toggle()
			else
				m.calendar_popup.toggle()
			end
		end
	end

	icon:Register( m.name, obj, m.db.minimap_icon )

	---@type MinimapIcon
	return {
	}
end

m.MinimapIcon = M
return M
