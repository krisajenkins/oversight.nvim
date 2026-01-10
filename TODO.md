- [x] When you tab across to the main window, the cursor should start on the first file header, not on the keyboard reminder.
- [x] In the main window, the usual keybindings should apply. So pressing `r` should mark the file reviewed (instead I think it enters replace mode).
- [x] File headers should be a single line. `=== [tick if reviewed] FILENAME  (VCS STATUS M/R/D) ===`
- [x] When a file is reviewed, it should be folded away in the main window, just showing the header.
- [x] The key bindings aren't very vim-ish. For example, 'Ctrl+E' for export should really be 'y' for yank.

# Features

In the file list, pressing enter should open the file as a regular buffer.

# Bugs

- [x] You can enter insert mode in the main window, and start entering arbitrary text. That makes no sense. These buffers shouldn't be editable.
- [x] When you're entering a comment, escape shouldn't discard it. It should save it. Only discard the comment if it's empty (or all-whitespace).

# Refactoring Tasks

## Type Safety

- [x] Fix the `make typecheck` warnings.
- [x] Add lua-language-server type checking to Makefile (currently only runs luacheck, which is a linter not a type checker)
- [ ] Define proper type aliases for UI components instead of generic `table` types
- [ ] Add typed callback signatures (e.g., `fun(file: FileInfo, index: number): nil` instead of `function`)

## DRY Improvements

- [x] Extract git status → highlight mapping to shared function (duplicated in 4 places: `lib/ui/init.lua`, `buffers/file_list/ui.lua`, `buffers/diff_view/ui.lua`)
- [x] Extract comment type → highlight/label mapping to shared function (duplicated in 3 places)
- [x] Add missing "C" (copied) status handling in `buffers/diff_view/ui.lua:47-54`

## Architecture

- [ ] Extract HelpOverlay from ReviewBuffer into its own component
- [ ] Fix encapsulation: ReviewBuffer directly mutates FileListBuffer's internal `files` array
- [ ] Add health check module (`lua/tuicr/health.lua`) per nvim best practices

## Testing

- [ ] Add tests for Buffer abstraction (`lib/buffer.lua`)
- [ ] Add tests for Git CLI/Repository modules (`lib/git/*.lua`)
- [ ] Add integration tests for ReviewBuffer workflow

## Documentation

- [ ] Add vimdoc in `doc/` directory
