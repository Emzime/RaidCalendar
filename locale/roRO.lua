RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("roRO", {
	days = { "duminică", "luni", "marți", "miercuri", "joi", "vineri", "sâmbătă" },
	days_short = { "dum", "lun", "mar", "mie", "joi", "vin", "sâm" },
	months = {
		"ianuarie", "februarie", "martie", "aprilie", "mai", "iunie",
		"iulie", "august", "septembrie", "octombrie", "noiembrie", "decembrie"
	},
	months_short = { "ian", "feb", "mar", "apr", "mai", "iun", "iul", "aug", "sep", "oct", "nov", "dec" },
	options = {
		time_format_24 = "24 ore",
		time_format_12 = "12 ore",
		language_enUS = "English",
		language_frFR = "French",
		language_roRO = "Română"
	},
	classes = {
		Druid = "Druid", Hunter = "Vânător", Mage = "Mag", Paladin = "Paladin", Priest = "Preot", Rogue = "Hoț", Shaman = "Șaman", Warlock = "Vrăjitor", Warrior = "Războinic", Tank = "Tank", Healer = "Vindecător", Melee = "Corp la corp", Ranged = "La distanță", Feral = "Feral"
	},
	ui = {
		tomorrow = "Mâine",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Nu"
	},
})
