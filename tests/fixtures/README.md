# VCS output fixtures

Frozen captures of real `git` and `jj` output. The backends' parsers are tested
against these bytes rather than against whatever this working copy happens to
contain today, which is what the VCS tests used to do — a test that reads the
repository it lives in changes its answer every commit.

`tests/helpers/mock_cli.lua` replays them: it stands in for
`oversight.lib.cli`, so both backends run their real parsing code over real tool
output without a subprocess in sight.

## Regenerating

    ./scripts/generate-fixtures.sh

**Do this deliberately, not casually.** It rebuilds a throwaway demo repository
from scratch and re-baselines every captured file below. git SHAs are pinned
(the generator fixes the author and committer dates), so a regeneration that
changes nothing about the demo repo leaves the git captures byte-identical —
but jj change IDs are random per repository, so the jj captures churn on every
run. Read the diff before committing it.

`VERSIONS` records the tools that produced the captures. Output formats drift
between releases; when a fixture stops describing reality, check that first.

## The demo repository

One commit, then uncommitted working-copy changes covering every status the
plugin models:

| Path | Change |
|------|--------|
| `README.md` | modified, one hunk |
| `src/app.lua` | modified, two separate hunks |
| `src/new_feature.lua` | added |
| `notes.txt` | deleted |
| `docs/guide.md` → `docs/manual.md` | renamed |
| `no-newline.txt` | modified, no trailing newline either side |
| `assets/logo.bin` | modified, binary |
| `src/util.lua` | untouched (so `ls-files` is wider than the change list) |

The changes are **staged** in the git repository. `git diff HEAD` — which is
what the backend runs — only reports added and renamed files once they are in
the index, so an unstaged capture would silently lose the `A` and `R` cases.

## Hand-authored fixtures

These are **not** produced by the generator and must not be deleted by it. Each
covers a case the demo repository cannot reach:

- `git-outputs/name-status-spaces.txt` — paths containing spaces, including a
  rename. Real git output, but only reachable with filenames we would rather not
  commit to the demo repo. Regression fixture: the rename parser used to split
  these fields on whitespace and produced two nonsense paths.
- `git-outputs/name-status-copied.txt` — a `C` (copied) status. git only emits
  `C` when asked with `--find-copies-harder`, which the plugin does not pass, so
  no genuine capture can contain one. The parser handles it, so it is tested.
