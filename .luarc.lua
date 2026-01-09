return {
	runtime = {
		version = "LuaJIT",
		path = {
			"?.lua",
			"?/init.lua",
			"lua/?.lua",
			"lua/?/init.lua",
		},
	},
	diagnostics = {
		globals = { "vim", "MiniTest" },
		severity = {
			["param-type-mismatch"] = "Error",
			["assign-type-mismatch"] = "Error",
			["undefined-field"] = "Error",
			["missing-parameter"] = "Warning",
			["redundant-parameter"] = "Warning",
			["redundant-value"] = "Warning",
			["unbalanced-assignments"] = "Warning",
			["unused-local"] = "Warning",
			["unused-vararg"] = "Warning",
			["trailing-space"] = "Warning",
		},
		neededFileStatus = {
			["codestyle-check"] = "Any",
			["duplicate-index"] = "Any",
			["duplicate-set-field"] = "Any",
			["redundant-parameter"] = "Any",
			["redundant-value"] = "Any",
			["unbalanced-assignments"] = "Any",
			["unused-local"] = "Any",
			["unused-vararg"] = "Any",
		},
		unusedLocalExclude = { "_*" },
	},
	workspace = {
		checkThirdParty = false,
		library = {
			"${3rd}/luv/library",
		},
	},
	type = {
		castNumberToInteger = true,
		weakUnionCheck = true,
		weakNilCheck = true,
	},
	hint = {
		enable = true,
		paramType = true,
		setType = true,
		paramName = "Literal",
		semicolon = "SameLine",
		arrayIndex = "Enable",
	},
	format = {
		enable = true,
		defaultConfig = {
			indent_style = "tab",
			indent_size = "1",
		},
	},
}
