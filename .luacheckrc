-- Luacheck configuration for oversight-nvim
std = "luajit"

-- Global variables that are allowed
globals = {
    "vim",
    "MiniTest",
}

-- Read-only globals
read_globals = {
    "vim",
    "MiniTest",
}

-- Ignore unused self arguments
self = false

-- Maximum line length
max_line_length = 120

-- Exclude patterns
exclude_files = {
    "deps/**",
    ".luarocks/**",
}

-- Warning codes to ignore
ignore = {
    "212", -- Unused argument (for callbacks with unused parameters)
    "213", -- Unused loop variable
    "631", -- Line is too long (we handle this with max_line_length)
}

-- Files-specific configuration
files["tests/"] = {
    globals = {"MiniTest"}
}

files["scripts/"] = {
    globals = {"vim"}
}
