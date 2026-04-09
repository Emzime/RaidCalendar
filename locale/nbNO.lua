RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("nbNO", {
	days = { "søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag" },
	days_short = { "søn", "man", "tir", "ons", "tor", "fre", "lør" },
	months = {
		"januar", "februar", "mars", "april", "mai", "juni",
		"juli", "august", "september", "oktober", "november", "desember"
	},
	months_short = { "jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des" },
	options = {
		time_format_24 = "24-timers",
		time_format_12 = "12-timers",
		language_enUS = "English",
		language_frFR = "French",
		language_nbNO = "Norsk"
	},
	classes = {
		Druid = "Druide", Hunter = "Jeger", Mage = "Magiker", Paladin = "Paladin", Priest = "Prest", Rogue = "Skurk", Shaman = "Sjaman", Warlock = "Trollmann", Warrior = "Kriger", Tank = "Tank", Healer = "Healer", Melee = "Nærkamp", Ranged = "Avstandskamp", Feral = "Feral"
	},
	ui = {
		tomorrow = "I morgen",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nei"
	},
})
