# The README screenshot.
#
#     nix shell nixpkgs#vhs -c vhs scripts/demo/screenshot.tape
#
# Run it from the repository root: VHS resolves Output and Source relative to
# the working directory, and an absolute path breaks its lexer.
#
# scripts/demo/setup.sh builds the repository being reviewed and the Neovim
# configuration, and prints its working directory. The tape depends on it; a
# missing helper fails silently and records a default-looking Neovim.

Output scripts/demo/demo.gif

Set FontSize 28
Set Width 3456
Set Height 1810
Set Padding 20
Set TypingSpeed 40ms
# Only the padding around the grid, really: Neovim paints its own colours over
# everything else. This is habamax's Normal background, so the border does not
# show as a frame.
Set Theme { "background": "#1c1c1c", "foreground": "#c7c7c7", "cursor": "#c7c7c7", "selection": "#3a3a3a", "black": "#1c1c1c", "red": "#d75f5f", "green": "#87af87", "yellow": "#d7af5f", "blue": "#5f87af", "magenta": "#af87af", "cyan": "#5fafaf", "white": "#c7c7c7", "brightBlack": "#5f5f5f", "brightRed": "#ff8787", "brightGreen": "#afd7af", "brightYellow": "#ffd787", "brightBlue": "#87afd7", "brightMagenta": "#d7afd7", "brightCyan": "#87d7d7", "brightWhite": "#eeeeee" }

Hide
Type "DEMO=$(bash scripts/demo/setup.sh)"
Enter
Sleep 2s

# See setup.sh: Neovim's colon-form truecolor is misparsed by the terminal VHS
# records in, and this terminfo spells the same sequences with semicolons.
Type "export TERMINFO=$DEMO/terminfo TERM=xterm-256color-semi"
Enter
Type "cd $DEMO/repo && clear"
Enter
Sleep 500ms

Type "nvim -u $DEMO/init.lua"
Enter
Sleep 3s
Type ":Oversight"
Enter
Sleep 3s
Show

# Down the file list to the file with the interesting change: README.md,
# src/keymap.ts, src/tableau.ts. Moving the cursor selects, so the diff follows.
Type "jj"
Sleep 1s

# Into the working-copy pane. Three ordinary windows, so this is just Vim.
Ctrl+W
Type "l"
Sleep 500ms
Ctrl+W
Type "l"
Sleep 1s

# To the second hunk, and a comment on the extracted keymap.
Type "]]"
Sleep 1s
Type "c"
Sleep 1s
# The comment window opens in insert mode, so this is just typing, and Esc
# saves it. (Ctrl-S also submits, but Ctrl-S is XOFF to a PTY and VHS's
# terminal swallows it.)
Type "Much clearer than the old switch."
Sleep 500ms
Escape
Sleep 1s

# And one on the base side, about the code that went away. Ctrl+t cycles the
# comment type; one press takes it from suggestion to issue.
Ctrl+W
Type "h"
Sleep 500ms
Type "32G"
Sleep 500ms
Type "c"
Sleep 1s
Ctrl+T
Sleep 500ms
Type "Was this bounds check load-bearing?"
Sleep 500ms
Escape
Sleep 1s

Ctrl+W
Type "l"
Sleep 2s

Screenshot screenshot.png
