RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("nlNL", {
	days = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" },
	days_short = { "zo", "ma", "di", "wo", "do", "vr", "za" },
	months = {
		"januari", "februari", "maart", "april", "mei", "juni",
		"juli", "augustus", "september", "oktober", "november", "december"
	},
	months_short = { "jan", "feb", "maa", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" },
	options = {
		time_format_24 = "24-uurs",
		time_format_12 = "12-uurs",
		language_enUS = "English",
		language_frFR = "French",
		language_nlNL = "Nederlands"
	},
	classes = {
		Druid = "Druïde", Hunter = "Jager", Mage = "Magiër", Paladin = "Paladin", Priest = "Priester", Rogue = "Schurk", Shaman = "Sjamaan", Warlock = "Warlock", Warrior = "Krijger", Tank = "Tank", Healer = "Healer", Melee = "Melee", Ranged = "Ranged", Feral = "Feral"
	},
	ui = {
		tomorrow = "Morgen",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nee"
	},
})
