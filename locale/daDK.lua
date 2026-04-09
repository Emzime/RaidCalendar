RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("daDK", {
	days = { "søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag" },
	days_short = { "søn", "man", "tir", "ons", "tor", "fre", "lør" },
	months = {
		"januar", "februar", "marts", "april", "maj", "juni",
		"juli", "august", "september", "oktober", "november", "december"
	},
	months_short = { "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec" },
	options = {
		time_format_24 = "24-timers",
		time_format_12 = "12-timers",
		language_enUS = "English",
		language_frFR = "French",
		language_daDK = "Dansk"
	},
	classes = {
		Druid = "Druide", Hunter = "Jæger", Mage = "Magiker", Paladin = "Paladin", Priest = "Præst", Rogue = "Skurk", Shaman = "Shaman", Warlock = "Heksemester", Warrior = "Kriger", Tank = "Tank", Healer = "Healer", Melee = "Nærkamp", Ranged = "Afstandskamp", Feral = "Feral"
	},
	ui = {
		tomorrow = "I morgen",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nej"
	},
})
