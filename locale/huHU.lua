RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("huHU", {
	days = { "vasárnap", "hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat" },
	days_short = { "vas", "hét", "ked", "sze", "csü", "pén", "szo" },
	months = {
		"január", "február", "március", "április", "május", "június",
		"július", "augusztus", "szeptember", "október", "november", "december"
	},
	months_short = { "jan", "feb", "már", "ápr", "máj", "jún", "júl", "aug", "sze", "okt", "nov", "dec" },
	options = {
		time_format_24 = "24 órás",
		time_format_12 = "12 órás",
		language_enUS = "English",
		language_frFR = "French",
		language_huHU = "Magyar"
	},
	classes = {
		Druid = "Druida", Hunter = "Vadász", Mage = "Mágus", Paladin = "Paladin", Priest = "Pap", Rogue = "Gazfickó", Shaman = "Sámán", Warlock = "Boszorkánymester", Warrior = "Harcos", Tank = "Tank", Healer = "Gyógyító", Melee = "Közelharc", Ranged = "Távolsági", Feral = "Feral"
	},
	ui = {
		tomorrow = "Holnap",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nem"
	},
})
