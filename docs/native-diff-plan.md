# Plan: native Neovim diff mode for review view

Date: 2026-08-28. Status: proposed, not started.

## Summary

Review mode currently *paints* a side-by-side diff into one scratch buffer:
`lib/diff.lua` parses unified diff output and hand-pairs deletions with
additions, `diff_view/ui.lua` pads, truncates and tab-expands every line into
two fixed-width columns, and browse mode re-applies treesitter highlights over
the result by hand.

Neovim already does all of this. The plan is to hand it the two whole files —
the version at the base revision and the working copy — in two buffers,
`:diffthis` both windows, and let Neovim compute and render the diff. We never
produce or parse a diff ourselves. The layout becomes three windows:

    file list | old (base) | new (working copy)

Everything outside the diff view is unchanged: `Session`, the comment model
(`file`, `line`, `side`), export, the watcher, the file list, and browse mode.
Comments already store real per-side file line numbers, which is exactly what a
cursor position in one of the two buffers gives us, so commenting gets simpler.

## Design decisions

**Two persistent scratch buffers**, `oversight://old` and `oversight://new`
(`buftype=nofile`, readonly), whose contents are swapped per file. Not a fresh
buffer pair per file: persistent buffers keep the `Buffer` class, the per-buffer
keymaps, the `BufEnter` tab-map installer and the watcher story working as they
are, and `diffthis` is per-window so it is set once at layout time.

*Rejected alternative:* `:edit` the real file into the new-side window. It is
editable, but fights the readonly/keymap model and pollutes the buffer list.
`o`/`<CR>` already opens the real file in a tab; that stays the edit path.

**Syntax highlighting comes from `filetype`.** Set it on both buffers from
`vim.filetype.match({ filename = path })` and let treesitter attach normally.
Review mode's hand-rolled re-highlighting goes away.

**`diffopt` is left alone.** It is a global option; a plugin should not
overwrite the user's. The README's recommended config suggests
`internal,filler,closeoff,linematch:60`; `health.lua` can warn if `internal`
is missing.

**Focus.** `Tab` keeps toggling file list ↔ diff, returning to whichever side
was last focused. `<C-w>h`/`<C-w>l` move between old and new, because that is
the native thing to do. `[`/`]` become thin wrappers over `normal! [c`/`]c`,
with wraparound to match today's behaviour.

**Per-status handling.** `A` → old buffer empty. `D` → new buffer empty. `R` →
old side read from `old_path`. Binary → both buffers show a notice and
`diffoff` for that file. Empty-vs-content diffs render fine natively.

**Binary detection** stops grepping diff output for `Binary files ... differ`
and uses the null-byte check `file_view` already has, so both modes share one
code path.

**No diff data anywhere.** `lib/diff.lua` is deleted outright, along with
`get_file_diff`/`get_all_diffs` in `vcs/base.lua` and `tests/test_diff.lua`.
The only VCS questions the diff view asks are "the file at base" and "the file
now". `get_file_diff_raw` survives because `Session:ensure_file` hashes it for
change detection; it does not feed the display.

## Comments: mirrored virtual lines

Neovim's diff-mode scrollbind aligns the two windows by line number plus its
own filler lines. It does **not** count `virt_lines`. A comment rendered as
two virtual lines under line 20 of the new buffer therefore pushes everything
below it down by two rows on that side only, and the panes drift.

Verified headless on 2026-08-28 (two 40-line buffers, two inserted lines on the
new side, `screenpos()` of a matching pair of lines):

    diff only                     old 20 -> row 20 | new 22 -> row 20   aligned
    + 2 virt_lines in new only    old 20 -> row 20 | new 22 -> row 22   MISALIGNED
    + mirrored blank in old       old 20 -> row 22 | new 22 -> row 22   aligned

So every comment is placed twice: the real text as `virt_lines` under its own
line in its own buffer, and an equal-height block of blank `virt_lines` at the
counterpart line in the other buffer. Vim already knows the counterpart line —
set the cursor to the anchor line in one window and read the cursorbound
cursor in the other, or use `diff_filler()` — so no diff parsing is needed.

File-level comments anchor as `virt_lines_above` on line 1 of the new buffer,
mirrored the same way.

## Steps

### 1. VCS backend: `get_file_at_base(path) → string[]|nil`

- git: `git show HEAD:<path>`. `git/cli.lua` already has `show()`.
- jj: `jj file show -r @- <fileset_literal(path)>`. New builder in
  `jj/cli.lua`.
- Renames pass `old_path`.
- A file that does not exist at base (status `A`) returns `{}`; `nil` is
  reserved for errors.
- Trailing-newline semantics must match between `readfile` on the working copy
  and the split of the CLI output, or every file gets a spurious last-line
  diff. Cover it with the existing no-newline demo file.
- Fixtures: add `show-head-*.txt` / `file-show-*.txt` captures (modified,
  renamed, no-trailing-newline, binary) to `scripts/generate-fixtures.sh` and
  `tests/helpers/mock_cli.lua`; extend `test_git.lua` and `test_jj.lua`;
  `test_vcs_hermetic.lua` exercises the real binaries.

### 2. Rewrite `DiffViewBuffer`

- Owns two `Buffer`s and two windows, `old_win` and `new_win`.
- `show_file(file)`: read base and working copy, `nvim_buf_set_lines` into
  each, set `filetype`, `diffupdate`, cursor to the first hunk
  (`normal! gg]c`).
- `ReviewBuffer:_create_layout` builds three windows; `_toggle_focus`,
  `is_valid` and `close` (`diffoff!`, wipe both buffers) follow.
- The `=== [✓] path (M) ===` header moves to `winbar` on both windows. The
  keybinding hint line goes; `?` covers it.

### 3. Comments via extmarks

- One namespace. `render_comments()` clears it and places each comment on its
  side plus the mirror block, per the section above.
- `_get_line_at_cursor` becomes: current window → side; cursor row → line;
  `nvim_buf_get_extmarks` on that row → the comment under the cursor, for
  `c` (edit) and `dd`.
- `Session`, `CommentInput` and `export.lua` are untouched. Export's
  "Line ~N (deleted)" wording for old-side comments still holds.

### 4. Refresh and the watcher

`refresh()` re-reads both sides, `set_lines`, `diffupdate`, re-places the
extmarks and restores the cursor. `while_refreshing` and `sync_probe` are
unchanged. The session's diff-hash reset already drops comments when a file's
diff moves under them.

### 5. Remove and document

- Delete `lib/diff.lua`, `diff_view/ui.lua`'s padding/truncation/tab code,
  `get_file_diff`/`get_all_diffs`, `tests/test_diff.lua`.
- `highlights.lua`: the `OversightDiff*` groups go; native `DiffAdd`,
  `DiffChange`, `DiffDelete`, `DiffText` take over.
- Keybindings, in the order CLAUDE.md prescribes: code, then
  `help/init.lua` review text, then README tables, then `doc/oversight.txt`
  §6. `test_help.lua` must be updated for the new map set (two diff buffers
  now share the diff-view maps).
- Regenerate the four `test_diff_view_screenshot.lua` screenshots —
  mini.test's child screenshots capture diff highlighting — and update
  `test_review_integration.lua` for the three-window layout.

## Size and ordering

Steps 1 and 3 are the bulk; 2 is mostly deletion. Net, the diff view should
shrink by a few hundred lines. Step 1 has no dependencies and can go first on
its own commit; 2 → 3 → 4 → 5 in order.
