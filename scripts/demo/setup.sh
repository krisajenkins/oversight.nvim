#!/usr/bin/env bash
#
# Build the throwaway repository and Neovim configuration that
# scripts/demo/screenshot.tape records. Prints the working directory on stdout;
# everything else goes to stderr, because the tape captures stdout.
#
# Run it through the tape rather than by hand:
#
#     nix shell nixpkgs#vhs -c vhs scripts/demo/screenshot.tape
#
# The repository is disposable and rebuilt from scratch every run, so the
# screenshot only ever moves when the plugin's rendering does.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"

# Pin everything a screenshot could otherwise pick up from the machine it was
# taken on: the developer's git identity, their global config, their commit
# dates.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="Demo" GIT_AUTHOR_EMAIL="demo@example.com"
export GIT_COMMITTER_NAME="Demo" GIT_COMMITTER_EMAIL="demo@example.com"
export GIT_AUTHOR_DATE="2020-01-01T00:00:00+0000"
export GIT_COMMITTER_DATE="2020-01-01T00:00:00+0000"

# ---------------------------------------------------------------------------
# Terminfo: truecolor with semicolons.
#
# Neovim emits truecolor in the ITU colon form (ESC[38:2::r:g:b m), and the
# terminal VHS records in misparses it — colours come out dim with the blue
# channel crushed, which reads as a bad colorscheme rather than as a bug.
# Neovim honours setrgbf/setrgbb from terminfo, so this is an xterm that spells
# them with semicolons.
# ---------------------------------------------------------------------------

cat >"$WORK/truecolor.src" <<'SRC'
xterm-256color-semi|xterm 256 color with semicolon truecolor,
    use=xterm-256color,
    setrgbf=\E[38;2;%p1%d;%p2%d;%p3%dm,
    setrgbb=\E[48;2;%p1%d;%p2%d;%p3%dm,
SRC
tic -x -o "$WORK/terminfo" "$WORK/truecolor.src" 2>/dev/null

# ---------------------------------------------------------------------------
# The repository. One commit, then the sort of change an agent leaves behind.
# ---------------------------------------------------------------------------

REPO="$WORK/repo"
mkdir -p "$REPO/src"
cd "$REPO"
git init --quiet --initial-branch=main

cat >src/tableau.ts <<'EOF'
import { onMount, onDestroy } from "./lifecycle";
import { parseCards } from "./card-parser";
import { SAVE_DEBOUNCE_MS } from "./constants";

import { reorderDocument } from "./reorder-document";
import { TableauStore, defaultData } from "./store";
import * as actions from "./tableau-actions";

export function createTableau(container: HTMLElement) {
  const store = new TableauStore(defaultData());
  let placedCount = 0;

  function applyAction(build: (data: TableauData) => Action) {
    const action = build(store.data);
    store.dispatch(action);
    scheduleSave();
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => store.persist(), SAVE_DEBOUNCE_MS);
  }

  function reorder() {
    const placed = reorderDocument(store.data, container);
    placedCount = placed.length;
    new Notice(`Reordered ${placedCount} sections`);
  }

  function handleKeydown(e: KeyboardEvent) {
    const num = parseInt(e.key);
    if (num >= 1 && num <= 9) {
      const names = store.data.tableaux.map((t) => t.name);
      if (num <= names.length) {
        applyAction((d) => actions.selectTableau(d, names[num - 1]));
      }
    }
  }

  onMount(() => container.addEventListener("keydown", handleKeydown));
  onDestroy(() => container.removeEventListener("keydown", handleKeydown));
}
EOF

cat >src/canvas.ts <<'EOF'
export function draw(ctx: CanvasRenderingContext2D, cards: Card[]) {
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  for (const card of cards) {
    ctx.fillRect(card.x, card.y, card.width, card.height);
  }
}
EOF

cat >styles.css <<'EOF'
.tableau {
  display: grid;
  gap: 0.5rem;
}
EOF

cat >README.md <<'EOF'
# Tableau

A small card tableau, for demonstrating a code review plugin.
EOF

git add -A
git commit --quiet -m "Initial commit"

# --- the uncommitted work under review -------------------------------------

# M, two hunks: a new import at the top, and a keymap extracted out of the
# hand-rolled keydown handler at the bottom.
cat >src/tableau.ts <<'EOF'
import { onMount, onDestroy } from "./lifecycle";
import { parseCards } from "./card-parser";
import { SAVE_DEBOUNCE_MS } from "./constants";
import { dispatchKeymap, type Keymap } from "./keymap";

import { reorderDocument } from "./reorder-document";
import { TableauStore, defaultData } from "./store";
import * as actions from "./tableau-actions";

export function createTableau(container: HTMLElement) {
  const store = new TableauStore(defaultData());
  let placedCount = 0;

  function applyAction(build: (data: TableauData) => Action) {
    const action = build(store.data);
    store.dispatch(action);
    scheduleSave();
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => store.persist(), SAVE_DEBOUNCE_MS);
  }

  function reorder() {
    const placed = reorderDocument(store.data, container);
    placedCount = placed.length;
    new Notice(`Reordered ${placedCount} sections`);
  }

  function switchToTableau(num: number) {
    const names = store.data.tableaux.map((t) => t.name);
    if (num <= names.length) {
      applyAction((d) => actions.selectTableau(d, names[num - 1]));
    }
  }

  const appKeymap: Keymap = new Map(
    Array.from({ length: 9 }, (_, i) => [
      String(i + 1),
      {
        description: `Switch to tableau ${i + 1}`,
        handler() {
          switchToTableau(i + 1);
        },
      },
    ] as const),
  );

  function handleKeydown(e: KeyboardEvent) {
    dispatchKeymap(appKeymap, e);
  }

  onMount(() => container.addEventListener("keydown", handleKeydown));
  onDestroy(() => container.removeEventListener("keydown", handleKeydown));
}
EOF

# A
cat >src/keymap.ts <<'EOF'
export type Binding = {
  description: string;
  handler(): void;
};

export type Keymap = Map<string, Binding>;

export function dispatchKeymap(keymap: Keymap, event: KeyboardEvent) {
  const binding = keymap.get(event.key);
  if (!binding) return;
  event.preventDefault();
  binding.handler();
}
EOF

# M
cat >styles.css <<'EOF'
.tableau {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(auto-fill, minmax(12rem, 1fr));
}
EOF

# M
cat >README.md <<'EOF'
# Tableau

A small card tableau, for demonstrating a code review plugin.

Keyboard shortcuts are declared in `src/keymap.ts`.
EOF

git add -A

# ---------------------------------------------------------------------------
# Neovim configuration: this plugin, plenary, a dark colorscheme, and the
# 'diffopt' the README recommends.
# ---------------------------------------------------------------------------

cat >"$WORK/init.lua" <<EOF
vim.opt.runtimepath:append("$PLUGIN_ROOT")
vim.opt.runtimepath:append("$PLUGIN_ROOT/deps/plenary.nvim")

vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.ruler = false
vim.o.cmdheight = 1
vim.cmd.colorscheme("habamax")

-- What the README recommends. \`linematch\` is what turns a rewritten line into
-- a highlighted word rather than a wholly-red line beside a wholly-green one.
vim.opt.diffopt = "internal,filler,closeoff,linematch:60"

require("oversight").setup({ watch = false })
EOF

echo "$WORK"
