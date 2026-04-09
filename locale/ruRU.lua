RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("ruRU", {
	days = { "воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота" },
	days_short = { "вс", "пн", "вт", "ср", "чт", "пт", "сб" },
	months = {
		"январь", "февраль", "март", "апрель", "май", "июнь",
		"июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
	},
	months_short = { "янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек" },
	options = {
		time_format_24 = "24-часовой",
		time_format_12 = "12-часовой",
		language_enUS = "English",
		language_frFR = "French",
		language_ruRU = "Русский"
	},
	classes = {
		Druid = "Друид", Hunter = "Охотник", Mage = "Маг", Paladin = "Паладин", Priest = "Жрец", Rogue = "Разбойник", Shaman = "Шаман", Warlock = "Чернокнижник", Warrior = "Воин", Tank = "Танк", Healer = "Целитель", Melee = "Ближний бой", Ranged = "Дальний бой", Feral = "Фераль"
	},
	ui = {
		tomorrow = "Завтра",
		online = "онлайн",
		offline = "оффлайн"
	},
	common = {
		no = "Нет"
	},
})
