RaidCalendar = RaidCalendar or {}

---@class RaidCalendar
local m = RaidCalendar

if m.Localization then return end

---@class LocalizationModule
local M = {}

local registry = {}
local default_locale = "enUS"

local builtin_locales = {

}

local legacy_key_map = {
	["Refresh"] = "ui.refresh",
	["Settings"] = "ui.settings",
	["Close Window"] = "ui.close_window",
	["Today"] = "actions.today",
	["Signup"] = "actions.signup",
	["Bench"] = "actions.bench",
	["Late"] = "actions.late",
	["Tentative"] = "actions.tentative",
	["Absence"] = "actions.absence",
	["Change Spec"] = "actions.change_spec",
	["Change"] = "actions.change",
	["Cancel"] = "actions.cancel",
	["Save"] = "actions.save",
	["Close"] = "actions.close",
	["Verify"] = "actions.verify",
	["Refresh Access"] = "actions.refresh_access",
	["Welcome popup"] = "actions.welcome_popup",
	["Reserve"] = "actions.reserve",
	["Lock raid"] = "actions.lock_raid",
	["Unlock raid"] = "actions.unlock_raid",
	["Check absentees"] = "actions.check_absentees",
	["Remove absentees"] = "actions.remove_absentees",
	["Show all"] = "actions.show_all",
	["24-hour"] = "options.time_format_24",
	["12-hour"] = "options.time_format_12",
	["English"] = "options.language_enUS",
	["Francais"] = "options.language_frFR",
}

local function deep_get(root, path)
	if type(root) ~= "table" or type(path) ~= "string" or path == "" then
		return nil
	end

	local value = root
	for segment in string.gmatch(path, "([^.]+)") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[segment]
		if value == nil then
			return nil
		end
	end

	return value
end

local function deep_merge(base, override)
	if type(base) ~= "table" then
		base = {}
	end

	if type(override) ~= "table" then
		return base
	end

	for key, value in pairs(override) do
		if type(value) == "table" then
			base[key] = deep_merge(type(base[key]) == "table" and base[key] or {}, value)
		else
			base[key] = value
		end
	end

	return base
end

local function copy_builtin_locales()
	for locale, data in pairs(builtin_locales) do
		if registry[locale] == nil then
			registry[locale] = deep_merge({}, data)
		end
	end
end

local function get_locale_table(locale)
	copy_builtin_locales()
	return registry[locale] or registry[default_locale] or builtin_locales[default_locale] or {}
end

local function resolve_key(key)
	if type(key) ~= "string" or key == "" then
		return nil
	end

	if deep_get(m.locale, key) or deep_get(get_locale_table(default_locale), key) then
		return key
	end

	if legacy_key_map[key] then
		return legacy_key_map[key]
	end

	return nil
end

--- Returns the display name of a locale in its OWN language (e.g. "Francais" for frFR, regardless of current locale)
function M.locale_native_name( locale_code )
	copy_builtin_locales()
	local t = registry[ locale_code ] or builtin_locales[ locale_code ] or {}
	-- Use the locale's own name for itself stored under options.language_<code>
	local options = t.options or {}
	local key = "language_" .. locale_code
	return options[ key ] or locale_code
end

function M.register(locale, data)
	if type(locale) ~= "string" or locale == "" or type(data) ~= "table" then
		return
	end

	registry[locale] = deep_merge(type(registry[locale]) == "table" and registry[locale] or {}, data)
end

function M.set_locale(locale)
	copy_builtin_locales()
	local selected = type(locale) == "string" and registry[locale] and locale or default_locale
	m.locale_flag = selected
	m.locale = get_locale_table(selected)
	return selected
end

function M.get_locale()
	return m.locale_flag or default_locale
end

function M.translate(key, vars)
	if key == nil then return nil end
	local resolved_key = resolve_key(key) or key
	local value = deep_get(m.locale, resolved_key) or deep_get(get_locale_table(default_locale), resolved_key)
	if type(value) ~= "string" then
		return key
	end

	if type(vars) == "table" then
		value = string.gsub(value, "{([%w_]+)}", function(name)
			local replacement = vars[name]
			if replacement == nil then
				return "{" .. name .. "}"
			end
			return tostring(replacement)
		end)
	end

	return value
end

function M.text(key, vars)
	local resolved_key = resolve_key(key)
	if resolved_key then
		return M.translate(resolved_key, vars)
	end
	return type(key) == "string" and key or ""
end

function M.translate_text(text)
	return M.text(text)
end

function M.term(text)
	return M.text(text)
end

function M.class_name(text)
	return M.translate("classes." .. tostring(text))
end

function M.spec_name(text)
	return M.translate("specs." .. tostring(text))
end

function M.get_day_name(index, short)
	local key = short and "days_short" or "days"
	local names = deep_get(m.locale, key) or deep_get(get_locale_table(default_locale), key) or {}
	return names[index] or tostring(index)
end

function M.get_month_name(index, short)
	local key = short and "months_short" or "months"
	local names = deep_get(m.locale, key) or deep_get(get_locale_table(default_locale), key) or {}
	return names[index] or tostring(index)
end

function M.format_date(timestamp, style)
	local info = date("*t", timestamp)
	if style == "weekday_day_month" then
		return string.format("%s %d. %s", M.get_day_name((tonumber(date("%w", timestamp)) or 0) + 1, false), info.day, M.get_month_name(info.month, false))
	elseif style == "day_month_year" then
		return string.format("%02d. %s %d", info.day, M.get_month_name(info.month, false), info.year)
	elseif style == "day_shortmonth_year_time" then
		return string.format("%02d. %s %d %s", info.day, M.get_month_name(info.month, true), info.year, date(m.time_format, timestamp))
	elseif style == "day_month_year_compact" then
		return string.format("%02d %s %d", info.day, M.get_month_name(info.month, false), info.year)
	elseif style == "month_year" then
		return string.format("%s %d", M.get_month_name(info.month, false), info.year)
	end

	return date("%c", timestamp)
end

copy_builtin_locales()

m.register_locale = M.register
m.set_locale = M.set_locale
m.L = M.translate
m.text = M.text
m.locale_native_name = M.locale_native_name
m.translate_text = M.translate_text
m.localize_term = M.term
m.class_name = M.class_name
m.spec_name = M.spec_name
m.localize_class = M.class_name
m.get_day_name = M.get_day_name
m.get_month_name = M.get_month_name
m.format_local_date = M.format_date
m.Localization = M

return M
