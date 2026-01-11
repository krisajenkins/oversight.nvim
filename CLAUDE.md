# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

oversight-nvim is a Neovim plugin for interactive code review. It provides a two-panel interface (file list + diff view) for reviewing uncommitted git changes, adding comments (note/suggestion/issue/praise), and exporting reviews to markdown.

## Commands

```bash
# Run all tests and static analysis
make

# Run just tests
make test

# Run a single test file
FILE=tests/test_buffer.lua make test_file

# Run static analysis (luacheck)
make typecheck

# Format code with stylua
make format
```

Dependencies (`deps/mini.nvim` and `deps/plenary.nvim`) are auto-cloned by make. The Nix flake provides dev tools: `lua-language-server`, `luacheck`, `stylua`, `neovim`, `git`.

## Architecture

### Entry Points

- `lua/oversight/init.lua` - Public API: `setup()`, `open_review()`, `:Oversight` command
- `plugin/oversight.lua` - Plugin initialization, auto-loaded by Neovim

### Core Abstractions

**Buffer** (`lib/buffer.lua`): Base class for all plugin buffers. Handles buffer creation, keymapping setup, and component rendering via the Renderer.

**UI Components** (`lib/ui/`):

- `component.lua` - Component factory for creating render-able elements
- `renderer.lua` - Renders component trees to buffer lines with highlights
- `init.lua` - Pre-built components: `Ui.text()`, `Ui.row()`, `Ui.col()`, `Ui.file_item()`, `Ui.diff_line()`, etc.

**Git** (`lib/git/`):

- `cli.lua` - Fluent builder for git commands: `git.diff():flag("name-status"):arg("HEAD"):cwd(dir):call()`
- `repository.lua` - Singleton per-directory Repository instances with caching
- `diff.lua` - Diff parsing and hunk extraction

**Storage** (`lib/storage/`):

- `session.lua` - ReviewSession: tracks file review status and comments
- `json.lua` - JSON persistence to `$XDG_DATA_HOME/oversight/sessions/`

### Buffer Types (`buffers/`)

- `review/init.lua` - ReviewBuffer: orchestrates the two-panel layout, singleton per repo
- `file_list/` - Left panel showing changed files with review status
- `diff_view/` - Right panel showing side-by-side diffs with comments
- `comment/init.lua` - Floating window for adding comments
- `help/init.lua` - Help overlay

### Data Flow

1. `ReviewBuffer.open()` creates Repository instance and loads/creates Session
2. FileListBuffer and DiffViewBuffer receive session reference
3. User actions (toggle reviewed, add comment) update Session
4. Session auto-saves to JSON on changes
5. Export converts Session comments to markdown for clipboard

## Testing

Tests use `mini.test` from mini.nvim. Test files in `tests/` follow pattern `test_*.lua`. Tests are run headless via `scripts/minimal_init.lua`.

```lua
-- Example test structure
local T = MiniTest.new_set()
T["ModuleName"] = MiniTest.new_set()
T["ModuleName"]["describes behavior"] = function()
    local expect = MiniTest.expect
    expect.equality(actual, expected)
end
return T
```

## Type Annotations

The codebase uses LuaCATS annotations (`---@class`, `---@field`, `---@param`, `---@return`). The `.luarc.lua` configures lua-language-server for type checking. Key types are defined in `lib/storage/session.lua` (Comment, FileStatus, ReviewSession).

## Version Control

This is a jj (Jujutsu) repository (`.jj/` present). Use `jj` commands for commits.
