RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("svSE", {
	days = { "söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag" },
	days_short = { "sön", "mån", "tis", "ons", "tor", "fre", "lör" },
	months = {
		"januari", "februari", "mars", "april", "maj", "juni",
		"juli", "augusti", "september", "oktober", "november", "december"
	},
	months_short = { "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec" },
	options = {
		time_format_24 = "24-timmar",
		time_format_12 = "12-timmar",
		language_enUS = "English",
		language_frFR = "French",
		language_svSE = "Svenska"
	},
	classes = {
		Druid = "Druid", Hunter = "Jägare", Mage = "Magiker", Paladin = "Paladin", Priest = "Präst", Rogue = "Skurk", Shaman = "Shaman", Warlock = "Warlock", Warrior = "Krigare", Tank = "Tank", Healer = "Healer", Melee = "Närstrid", Ranged = "Avstånd", Feral = "Feral"
	},
	ui = {
		tomorrow = "Imorgon",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nej"
	},
})
