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

# Run both static analysis passes
make typecheck
make luacheck   # linting only
make lua-ls     # LuaCATS type checking only

# Format code with stylua
make format
make check-format   # fail instead of rewriting (used in CI)
```

`typecheck` runs two complementary tools: luacheck lints, and
lua-language-server verifies the LuaCATS annotations that luacheck ignores
entirely. lua_ls is configured by `.luarc.json` — note the extension: it does
**not** read a `.luarc.lua`, and the Makefile must pass `--configpath` as an
absolute path or lua_ls resolves it against `lua/` and silently ignores it,
leaving `vim` undefined and flooding the run with false positives.

Dependencies (`deps/mini.nvim` and `deps/plenary.nvim`) are auto-cloned by make. The Nix flake provides dev tools: `lua-language-server`, `luacheck`, `stylua`, `neovim`, `git`.

CI runs `nix develop -c make` plus `make check-format`, so it uses the same
toolchain as the dev shell.

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

**Watcher** (`lib/watcher.lua`): auto-refreshes open views when the repository
changes on disk. Refcounted per repository root; disable with
`setup({ watch = false })`.

It combines two signals and needs both. `fs_poll` (*not* `fs_event` — see the
module comment) on the VCS metadata path and on the files that already have
changes is fast but only ever sees what it is already watching; a VCS `probe`
every 2s compares the change list and is the only thing that notices a clean
file becoming a changed one. Dropping either leaves a hole — an end-to-end run
is what caught it the first time.

Three things are load-bearing and easy to undo by accident: it never inspects
the event payload (there is no trustworthy "what changed"), `while_refreshing`
suppresses events for the duration of a refresh — because reading a jj
repository *writes* to it, so a refresh otherwise triggers itself — and
`sync_probe` re-baselines afterwards so the next tick does not report our own
work back to us.

**Session** (`lib/session.lua`): ReviewSession tracks file review status and
comments. Sessions are **in-memory only** and do not survive a Neovim restart.
`to_json`/`from_json` exist and are round-trip tested, but nothing writes them
to disk; `Session:save()` is a no-op that only stamps `updated_at`.

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

1. `ReviewBuffer.open()` creates VCS backend and creates a fresh Session
2. FileListBuffer and DiffViewBuffer receive session reference
3. User actions (toggle reviewed, add comment) update Session
4. Re-opening a file whose diff hash changed resets its status and drops its comments
5. Export converts Session comments to markdown for clipboard

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

VCS behaviour is tested against **frozen captures** of real `git` and `jj`
output in `tests/fixtures/`, replayed by `tests/helpers/mock_cli.lua` — not
against the repository the tests happen to be living in.
`tests/test_vcs_hermetic.lua` is the one file that runs a real binary, and it is
what keeps those captures honest. Regenerate them deliberately with
`./scripts/generate-fixtures.sh`.

**Read `tests/CLAUDE.md` before writing tests.** It records the traps: why
swapping `package.loaded` is not enough to mock the CLI, why a test must never
skip by returning early, and why a real-binary test has to neutralise the
developer's own git/jj configuration.

## Type Annotations

The codebase uses LuaCATS annotations (`---@class`, `---@field`, `---@param`, `---@return`). `.luarc.json` configures lua-language-server for type checking (see the Commands section — it must be `.json`, and passed as an absolute path). Key types are defined in `lib/session.lua` (Comment, FileStatus, ReviewSession).

## Version Control

This is a jj (Jujutsu) repository (`.jj/` present). Use `jj` commands for commits.
