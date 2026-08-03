# Testing notes

Things that cost someone an afternoon. Not a mini.test tutorial — see
`deps/mini.nvim/doc/mini-test.txt` for that.

## Layout

| Path | What it is |
|------|------------|
| `fixtures/` | Frozen captures of real `git`/`jj` output. See `fixtures/README.md`. |
| `helpers/mock_cli.lua` | Stands in for `oversight.lib.cli` and replays those captures. |
| `helpers/notify.lua` | Captures `vim.notify` around a function. |
| `helpers/child.lua` | Child Neovim plus a set factory with the standard hooks. |
| `test_vcs_hermetic.lua` | The **only** file that runs a real VCS binary. |
| `screenshots/` | mini.test reference screenshots. |

## Never call `vim.wait` inside a case

This one is nasty, because it fails **green**.

`MiniTest.execute` schedules every case up front with `vim.schedule` (see
`mini/test.lua`). A `vim.wait` that lets the event loop run therefore flushes
that queue and starts the *following* cases nested inside the current one. When
the outer case eventually finishes, the runner has moved on and its result is
discarded — no pass, no fail, no warning. The run reports `Fails (0)` and you
are none the wiser.

Symptom: a group shows fewer `o`s than it has cases, while the summary still
claims to have run them all. Reproduce it with three cases where only the last
one omits `vim.wait`; only that one reports.

Two ways out:

- plenary's `Job:wait` passes `fast_only = true` to `vim.wait`, which does not
  run scheduled callbacks. That is why the *synchronous* CLI tests are safe.
  `fast_only` is no help when you are waiting for something that arrives via
  `vim.schedule` — which is everything asynchronous in this plugin.
- **Wait in a child Neovim instead.** The child's event loop is not the
  runner's, and the parent blocks on a plain RPC call. `test_cli.lua`'s async
  group and all of `test_watcher.lua` work this way.

## Child Neovim

`helpers/child.lua` supplies the child and a set factory:

```lua
local child, child_set = require("tests.helpers.child")()
local T = child_set({ columns = 120, pre_case = function() ... end })
```

The factory's `pre_case` restarts the child at fixed dimensions and loads the
plugin; anything you pass is *appended* to that, never replacing it. Screenshot
comparisons depend on those dimensions, so a test that sets its own is a test
nobody else can reproduce.

## Never skip silently

The VCS tests used to open with:

```lua
if vim.fn.isdirectory(vim.fn.getcwd() .. "/.jj") ~= 1 then
    return
end
```

A case that returns early **passes**. Thirty of them were green in CI while
asserting nothing at all. If a test genuinely cannot run, say so:

```lua
if vim.fn.executable("jj") ~= 1 then
    MiniTest.skip("jj is not on PATH")
end
```

And prefer not needing to: fixtures let the parser tests run everywhere.

## Mocking the CLI

`MockCli.install()` swaps the mock into `package.loaded["oversight.lib.cli"]`.
That alone is **not enough**. `lib/vcs/git/cli.lua` and `lib/vcs/jj/cli.lua`
each do `local Cli = require("oversight.lib.cli")` at module scope, so they hold
the real builder in an upvalue from their own first load. They have to be
dropped from `package.loaded` too, so the next `require` rebuilds them against
the mock. `install()` does this; anything else that swaps a module out must
think about the same thing.

The backends also cache one instance per directory, and those instances outlive
the swap — `install()`/`uninstall()` clear them.

A command with no matching route returns a **failure result**, not an `error()`.
`call()` runs inside the plugin's own `pcall` and failure paths, where a raised
error is swallowed and the miss then looks like a successful empty result. Call
`MockCli.assert_no_misses()` in `post_case` so an unrouted command fails the
test by name rather than surfacing as a confusing empty list three layers away.

Fixture text is handed back the way the real `call()` produces stdout:
`table.concat(job:result(), "\n")` — joined with newlines, no trailing one.

## Keep the developer's own config out of it

`lib/cli.lua` passes `env = nil` so child processes inherit this one's
environment. That is deliberate (git and jj need `HOME`, `SSH_AUTH_SOCK`,
`GIT_*`, `JJ_CONFIG`), but it means a test running a real binary sees whatever
the developer has configured.

This is not hypothetical. `jj diff` defaults to `color-words` output, which the
unified-diff parser reduces to zero hunks — and it went unnoticed because the
author's personal jj config sets `ui.diff-formatter = ":git"`. Any test that
runs a real binary must neutralise that: `GIT_CONFIG_GLOBAL=/dev/null`, a
purpose-written `JJ_CONFIG`. See `test_vcs_hermetic.lua`.

## Assertions

`MiniTest.expect.equality` is `vim.deep_equal`, so compare whole tables rather
than picking fields apart one assertion at a time — the failure message prints
both sides with `vim.inspect`, which is far more use than `Left: 3 Right: 4`.

## Stubbing vim functions

Give a stub the **full** signature of what it replaces. A one-argument
`vim.notify` stub makes lua-language-server re-infer `vim.notify` as taking one
argument, and `make lua-ls` then reports every real `vim.notify(msg, level)`
call in the plugin as passing a redundant parameter. `helpers/notify.lua` takes
`(msg, _level, _opts)` for exactly this reason.

## Screenshots

Each reference file holds two grids: the text, then the highlight attributes.
A change to a highlight group moves the attribute grid without touching a byte
of the text grid, which makes a re-baseline look far more alarming than it is —
diff the two halves separately before deciding.

Re-baseline by deleting the reference and re-running; do it deliberately, and
read what changed.
