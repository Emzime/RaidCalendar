RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("itIT", {
	days = { "domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato" },
	days_short = { "dom", "lun", "mar", "mer", "gio", "ven", "sab" },
	months = {
		"gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
		"luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"
	},
	months_short = { "gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic" },
	options = {
		time_format_24 = "24 ore",
		time_format_12 = "12 ore",
		language_enUS = "English",
		language_frFR = "French",
		language_itIT = "Italiano"
	},
	classes = {
		Druid = "Druido", Hunter = "Cacciatore", Mage = "Mago", Paladin = "Paladino", Priest = "Sacerdote", Rogue = "Ladro", Shaman = "Sciamano", Warlock = "Stregone", Warrior = "Guerriero", Tank = "Tank", Healer = "Guaritore", Melee = "Mischia", Ranged = "A distanza", Feral = "Feral"
	},
	ui = {
		tomorrow = "Domani",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "No"
	},
})
