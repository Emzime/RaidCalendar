RaidCalendar = RaidCalendar or {}
local m = RaidCalendar

m.register_locale("ptBR", {
	days = { "domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado" },
	days_short = { "dom", "seg", "ter", "qua", "qui", "sex", "sáb" },
	months = {
		"janeiro", "fevereiro", "março", "abril", "maio", "junho",
		"julho", "agosto", "setembro", "outubro", "novembro", "dezembro"
	},
	months_short = { "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez" },
	options = {
		time_format_24 = "24 horas",
		time_format_12 = "12 horas",
		language_enUS = "English",
		language_frFR = "French",
		language_ptBR = "Português (BR)"
	},
	classes = {
		Druid = "Druida", Hunter = "Caçador", Mage = "Mago", Paladin = "Paladino", Priest = "Sacerdote", Rogue = "Ladino", Shaman = "Xamã", Warlock = "Bruxo", Warrior = "Guerreiro", Tank = "Tanque", Healer = "Curandeiro", Melee = "Corpo a corpo", Ranged = "Distância", Feral = "Feral"
	},
	ui = {
		tomorrow = "Amanhã",
		online = "online",
		offline = "offline"
	},
	common = {
		no = "Não"
	},
})
