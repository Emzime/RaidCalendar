RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("csCZ", {
	days = { "neděle", "pondělí", "úterý", "středa", "čtvrtek", "pátek", "sobota" },
	days_short = { "ne", "po", "út", "st", "čt", "pá", "so" },
	months = {
		"leden", "únor", "březen", "duben", "květen", "červen",
		"červenec", "srpen", "září", "říjen", "listopad", "prosinec"
	},
	months_short = { "led", "úno", "bře", "dub", "kvě", "čvn", "čvc", "srp", "zář", "říj", "lis", "pro" },
	options = {
		time_format_24 = "24 hodin",
		time_format_12 = "12 hodin",
		language_enUS = "English",
		language_frFR = "French",
		language_csCZ = "Čeština"
	},
	classes = {
		Druid = "Druid", Hunter = "Lovec", Mage = "Mág", Paladin = "Paladin", Priest = "Kněz", Rogue = "Loupežník", Shaman = "Šaman", Warlock = "Čaroděj", Warrior = "Válečník", Tank = "Tank", Healer = "Léčitel", Melee = "Blízký boj", Ranged = "Dálkový boj", Feral = "Feral"
	},
	ui = {
		tomorrow = "Zítra",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Ne"
	},
})
