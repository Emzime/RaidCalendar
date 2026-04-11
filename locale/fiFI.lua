RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("fiFI", {
	days = { "sunnuntai", "maanantai", "tiistai", "keskiviikko", "torstai", "perjantai", "lauantai" },
	days_short = { "su", "ma", "ti", "ke", "to", "pe", "la" },
	months = {
		"tammikuu", "helmikuu", "maaliskuu", "huhtikuu", "toukokuu", "kesäkuu",
		"heinäkuu", "elokuu", "syyskuu", "lokakuu", "marraskuu", "joulukuu"
	},
	months_short = { "tam", "hel", "maa", "huh", "tou", "kes", "hei", "elo", "syy", "lok", "mar", "jou" },
	options = {
		time_format_24 = "24-tunnin",
		time_format_12 = "12-tunnin",
		language_enUS = "English",
		language_frFR = "French",
		language_fiFI = "Suomi"
	},
	classes = {
		Druid = "Druidi", Hunter = "Metsästäjä", Mage = "Taikuri", Paladin = "Paladin", Priest = "Pappi", Rogue = "Rosvo", Shaman = "Shamaani", Warlock = "Warlock", Warrior = "Soturi", Tank = "Tankki", Healer = "Parantaja", Melee = "Lähitaistelu", Ranged = "Kaukainen", Feral = "Feral"
	},
	ui = {
		tomorrow = "Huomenna",
		online = "verkossa",
		offline = "offline"
	},
	common = {
		no = "Ei"
	},
})
