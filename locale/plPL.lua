RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("plPL", {
	days = { "niedziela", "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota" },
	days_short = { "nd", "pn", "wt", "śr", "cz", "pt", "so" },
	months = {
		"styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec",
		"lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"
	},
	months_short = { "sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru" },
	options = {
		time_format_24 = "24-godzinny",
		time_format_12 = "12-godzinny",
		language_enUS = "English",
		language_frFR = "French",
		language_plPL = "Polski"
	},
	classes = {
		Druid = "Druid", Hunter = "Łowca", Mage = "Mag", Paladin = "Paladyn", Priest = "Kapłan", Rogue = "Łotrzyk", Shaman = "Szaman", Warlock = "Czarnoksiężnik", Warrior = "Wojownik", Tank = "Czołg", Healer = "Uzdrowiciel", Melee = "Walka wręcz", Ranged = "Dystansowy", Feral = "Feral"
	},
	ui = {
		tomorrow = "Jutro",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nie"
	},
})
