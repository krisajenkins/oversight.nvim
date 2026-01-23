# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

oversight-nvim is a Neovim plugin for interactive code review. It has two modes:

- **Review mode** (`:Oversight` or `:Oversight review`) - Two-panel interface (file list + diff view) for reviewing uncommitted VCS changes
- **Browse mode** (`:Oversight browse`) - Two-panel interface (file tree + file viewer) for browsing the full codebase and leaving notes on any file

Both modes support adding comments (note/suggestion/issue/praise) and exporting reviews to markdown. Supports both Git and Jujutsu (jj) with automatic detection.

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

- `lua/oversight/init.lua` - Public API: `setup()`, `open_review()`, `open_browse()`, `:Oversight [review|browse]` command
- `plugin/oversight.lua` - Plugin initialization, auto-loaded by Neovim

### Core Abstractions

**Buffer** (`lib/buffer.lua`): Base class for all plugin buffers. Handles buffer creation, keymapping setup, and component rendering via the Renderer.

**UI Components** (`lib/ui/`):

- `component.lua` - Component factory for creating render-able elements
- `renderer.lua` - Renders component trees to buffer lines with highlights
- `init.lua` - Pre-built components: `Ui.text()`, `Ui.row()`, `Ui.col()`, `Ui.file_item()`, `Ui.diff_line()`, etc.

**VCS Backends** (`lib/vcs/`):

- `base.lua` - Shared base class for VCS backends (defines `create_backend()`, shared `read_file()`)
- `git/cli.lua` - Fluent builder for git commands: `git.diff():flag("name-status"):arg("HEAD"):cwd(dir):call()`
- `git/init.lua` - GitBackend: `get_diff_files()`, `get_tracked_files()`, `get_file_diff()`, etc.
- `jj/cli.lua` - Fluent builder for jj commands (same pattern as git)
- `jj/init.lua` - JjBackend: same interface as GitBackend
- `diff.lua` - Diff parsing and hunk extraction

**Session** (`lib/session.lua`): ReviewSession tracks file review status and comments (ephemeral, not persisted between Neovim sessions).

### Buffer Types (`buffers/`)

**Review mode:**

- `review/init.lua` - ReviewBuffer: orchestrates the review two-panel layout, singleton per repo
- `file_list/` - Left panel showing changed files with review status
- `diff_view/` - Right panel showing side-by-side diffs with comments

**Browse mode:**

- `browse/init.lua` - BrowseBuffer: orchestrates the browse two-panel layout, singleton per repo
- `file_tree/` - Left panel: directory tree navigator with unreviewed/reviewed sections
- `file_view/` - Right panel: full file content viewer with treesitter syntax highlighting and inline comments

**Shared:**

- `comment/init.lua` - Floating window for adding comments
- `help/init.lua` - Help overlay

### Data Flow

**Review mode:**

1. `ReviewBuffer.open()` creates VCS backend and loads/creates Session
2. FileListBuffer and DiffViewBuffer receive session reference
3. User actions (toggle reviewed, add comment) update Session
4. Export converts Session comments to markdown for clipboard

**Browse mode:**

1. `BrowseBuffer.open()` creates VCS backend and calls `get_tracked_files()`
2. FileTreeBuffer and FileViewBuffer receive session reference
3. Same comment/review/export flow as review mode
4. Export uses "Codebase Notes" title instead of "Code Review"

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

The codebase uses LuaCATS annotations (`---@class`, `---@field`, `---@param`, `---@return`). The `.luarc.lua` configures lua-language-server for type checking. Key types are defined in `lib/session.lua` (Comment, FileStatus, ReviewSession).

## Version Control

This is a jj (Jujutsu) repository (`.jj/` present). Use `jj` commands for commits.
