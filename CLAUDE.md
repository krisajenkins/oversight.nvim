# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

oversight-nvim is a Neovim plugin for interactive code review. It has two modes:

- **Review mode** (`:Oversight` or `:Oversight review`) - Three-window interface (file list + the two sides of a native Neovim diff) for reviewing uncommitted VCS changes
- **Browse mode** (`:Oversight browse`) - Two-panel interface (file tree + file viewer) for browsing the full codebase and leaving notes on any file

Both modes support adding comments (suggestion/issue/question) and exporting reviews to markdown. Supports both Git and Jujutsu (jj) with automatic detection.

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
- `init.lua` - Pre-built components: `Ui.text()`, `Ui.row()`, `Ui.col()`, `Ui.file_item()`, etc.

**VCS Backends** (`lib/vcs/`):

- `base.lua` - Shared base class for VCS backends (defines `create_backend()`, shared `read_file()` and `file_content_lines()`)
- `git/cli.lua` - Fluent builder for git commands: `git.diff():flag("name-status"):arg("HEAD"):cwd(dir):call()`
- `git/init.lua` - GitBackend: `get_changed_files()`, `get_tracked_files()`, `get_file_at_base()`, `get_file_diff_raw()`
- `jj/cli.lua` - Fluent builder for jj commands (same pattern as git)
- `jj/init.lua` - JjBackend: same interface as GitBackend

**Nothing parses a diff.** `get_file_at_base()` returns the whole file at the
base revision (`git show HEAD:<path>`, `jj file show -r @-`), `read_file()`
returns the whole working copy, and Neovim's own diff does the rest.
`get_file_diff_raw()` survives only because `Session:ensure_file` hashes it to
notice a file's changes moving under an open review.

Both sides must split lines the same way, or every file shows a spurious
last-line change. See the note on `file_content_lines` in `base.lua`.

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

- `review/init.lua` - ReviewBuffer: orchestrates the three-window layout, singleton per repo
- `file_list/` - Left panel showing changed files with review status
- `diff_view/` - The two right-hand panels: `oversight://old` holds the file at
  the base revision, `oversight://new` the working copy, and both windows are
  `:diffthis`. Syntax highlighting comes from setting `filetype`; the header is
  a `winbar`.

Three things about the diff view are load-bearing:

- **`foldenable` is off.** Diff mode folds unchanged regions by default, and a
  folded comment is an invisible comment. `]c` is how you skip context here.
- **Every comment is placed twice.** Neovim's diff aligns the two windows with
  filler lines and does not count `virt_lines`, so a comment on one side alone
  pushes that side down and the panes drift. An equal-height blank block goes at
  the counterpart line on the other side. `tests/test_diff_view.lua` asserts the
  invariant, with a negative control.
- **The counterpart is found from `diff_filler`, not from a diff.** A line's
  display row is its number plus every filler above it, and two lines sharing a
  display row are counterparts. A line with none — one side of a pure addition
  or deletion — falls back to the nearest line above, which puts the mirror a
  row or two early inside that hunk and back in step below it.

A file-level comment hangs off the *last* line, not above the first:
`virt_lines_above` on line 1 has no screen row to draw in, and Neovim omits it
in silence.

**Browse mode:**

- `browse/init.lua` - BrowseBuffer: orchestrates the browse two-panel layout, singleton per repo
- `file_tree/` - Left panel: directory tree navigator with unreviewed/reviewed sections
- `file_view/` - Right panel: full file content viewer with treesitter syntax highlighting and inline comments

**Shared:**

- `comment/init.lua` - Floating window for adding comments
- `help/init.lua` - Help overlay
- `lib/binary.lua` - Binary detection, shared by both modes. Note the trap it
  documents: `vim.fn.readfile` turns every NUL into a newline, so its output can
  never be asked whether a file was binary. Sniff the bytes on disk.

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

`tests/helpers/git_repo.lua` builds a throwaway git repository inside a child
Neovim, for the tests that need a real one: the help audit, the diff
screenshots, and the pane-alignment checks.

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

## The README screenshot

`screenshot.png` is generated, not captured:

```bash
nix shell nixpkgs#vhs -c vhs scripts/demo/screenshot.tape
```

`scripts/demo/setup.sh` builds a throwaway repository and a Neovim config, and
the tape drives review mode through real keystrokes. Two things in there are not
decoration:

- **The semicolon terminfo.** Neovim emits truecolor in the colon form, which
  VHS's terminal misparses — colours come out dim with the blue channel crushed,
  which reads as a bad colorscheme rather than as a bug.
- **Esc, not Ctrl-S, submits the comment.** Ctrl-S is XOFF to a PTY and the
  recording terminal swallows it. Esc saves a non-empty comment anyway.

## Keybindings

Keybindings exist in four places. Only one of them runs, so only one is the
source of truth:

1. **The code** — each panel's `_setup_mappings()` (`buffers/file_list`,
   `buffers/diff_view`, `buffers/file_tree`, `buffers/file_view`,
   `buffers/comment`), **plus** the tab-level maps in
   `buffers/review/init.lua:_setup_tab_mappings()` and the matching method in
   `buffers/browse`. **This is the source of truth.**
2. `lua/oversight/buffers/help/init.lua` — the `?` overlay, one text per mode.
3. `README.md` — the Keybindings tables.
4. `doc/oversight.txt` — section 6.

Change 1, then update 2-4 to match. `tests/test_help.lua` enforces the 1 → 2
half by reading the maps back off live buffers, so an undocumented key fails the
suite; 3 and 4 are prose and stay a manual step.

Two things make this easy to get wrong:

- **The panels of a mode do not share a map set.** `g`/`G` are file list/tree
  only; `[`/`]`, `c`, `C` and `dd` are diff/file view only. A flat "these are
  the review mode keys" table is wrong, and was. Review mode has *three*
  panels: both sides of the diff carry the same maps, and `test_help.lua`
  checks both.
- **Review mode binds no panel-switching key; browse mode binds `Tab`.** The
  review layout is three ordinary windows, so `<C-w>h`/`<C-w>l` already do it.
  Do not "restore" `Tab` there.
- **The tab-level maps install on `BufEnter`, not at open.** A panel you have
  never focused genuinely has no `{`, `}`, `y`, `X`, `R`, `?` or `q` yet, so
  reading its keymaps before visiting it under-reports. `test_help.lua` visits
  every panel first; do the same when investigating by hand.

Each mode must pass its own text to `HelpOverlay.show()`. The overlay's default
is the review text, and browse mode silently inherited it for a while — hunk
keys that do not exist there, no `l`/`h`, and "Quit review" at the bottom.

## Type Annotations

The codebase uses LuaCATS annotations (`---@class`, `---@field`, `---@param`, `---@return`). `.luarc.json` configures lua-language-server for type checking (see the Commands section — it must be `.json`, and passed as an absolute path). Key types are defined in `lib/session.lua` (Comment, FileStatus, ReviewSession).

## Version Control

This is a jj (Jujutsu) repository (`.jj/` present). Use `jj` commands for commits.
