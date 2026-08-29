#!/usr/bin/env bash
#
# Regenerate the frozen VCS output fixtures in tests/fixtures/.
#
# Run this DELIBERATELY, not casually. It re-baselines every captured fixture,
# and jj change IDs are random per repository, so a regeneration rewrites the
# jj captures even when nothing about the plugin changed. Review the diff.
#
#   ./scripts/generate-fixtures.sh
#
# The disposable demo repositories are built in a temp directory and removed on
# exit; nothing outside tests/fixtures/ is touched.
#
# Hand-authored fixtures (see tests/fixtures/README.md) are NOT generated here
# and must not be deleted by this script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"
GIT_OUT="$FIXTURES/git-outputs"
JJ_OUT="$FIXTURES/jj-outputs"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$GIT_OUT" "$JJ_OUT"

# Pin every input that would otherwise vary between machines: identity, dates
# (so git SHAs are reproducible across regenerations), and config discovery.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="Fixture Bot"
export GIT_AUTHOR_EMAIL="fixtures@example.com"
export GIT_COMMITTER_NAME="Fixture Bot"
export GIT_COMMITTER_EMAIL="fixtures@example.com"
export GIT_AUTHOR_DATE="2020-01-01T00:00:00+0000"
export GIT_COMMITTER_DATE="2020-01-01T00:00:00+0000"

cat >"$WORK/jj.toml" <<'EOF'
[user]
name = "Fixture Bot"
email = "fixtures@example.com"
EOF
export JJ_CONFIG="$WORK/jj.toml"

# ---------------------------------------------------------------------------
# The demo repository's committed state, then the working-copy changes made on
# top of it. Both VCSs get byte-identical content so their captures are directly
# comparable.
# ---------------------------------------------------------------------------

seed_committed_state() {
	local dir="$1"
	mkdir -p "$dir/src" "$dir/docs" "$dir/assets"

	cat >"$dir/README.md" <<'EOF'
# Demo

A repository that exists only to produce test fixtures.
EOF

	cat >"$dir/src/app.lua" <<'EOF'
local M = {}

function M.greet(name)
	return "Hello, " .. name
end

function M.farewell(name)
	return "Goodbye, " .. name
end

function M.shout(text)
	return text:upper()
end

return M
EOF

	cat >"$dir/src/util.lua" <<'EOF'
local M = {}

function M.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

return M
EOF

	cat >"$dir/docs/guide.md" <<'EOF'
# Guide

Read this first.
EOF

	cat >"$dir/notes.txt" <<'EOF'
Scratch notes.
Delete me.
EOF

	printf 'no trailing newline here' >"$dir/no-newline.txt"

	# A deliberately non-UTF-8 payload so both VCSs classify it as binary.
	printf '\x00\x01\x02\x03BINARY\xff\xfe\x00' >"$dir/assets/logo.bin"
}

apply_working_changes() {
	local dir="$1"

	# M, single hunk.
	cat >"$dir/README.md" <<'EOF'
# Demo

A repository that exists only to produce test fixtures for oversight.
EOF

	# M, two separate hunks (top and bottom of the file).
	cat >"$dir/src/app.lua" <<'EOF'
local M = {}

function M.greet(name)
	return "Hello there, " .. name
end

function M.farewell(name)
	return "Goodbye, " .. name
end

function M.shout(text)
	return text:upper()
end

function M.whisper(text)
	return text:lower()
end

return M
EOF

	# A
	cat >"$dir/src/new_feature.lua" <<'EOF'
local M = {}

function M.enabled()
	return true
end

return M
EOF

	# D
	rm "$dir/notes.txt"

	# R
	mv "$dir/docs/guide.md" "$dir/docs/manual.md"

	# M, and the new content has no trailing newline either.
	printf 'still no trailing newline' >"$dir/no-newline.txt"

	# M, binary.
	printf '\x00\x01\x02\x03CHANGED\xff\xfe\x00' >"$dir/assets/logo.bin"
}

# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------

echo "==> git"
GIT_REPO="$WORK/git-demo"
mkdir -p "$GIT_REPO"
git -C "$GIT_REPO" init --quiet --initial-branch=main
seed_committed_state "$GIT_REPO"
git -C "$GIT_REPO" add -A
git -C "$GIT_REPO" commit --quiet -m "Initial commit"

# Clean state, before any working-copy changes.
git -C "$GIT_REPO" diff --no-color --name-status HEAD >"$GIT_OUT/name-status-clean.txt"

apply_working_changes "$GIT_REPO"
# Stage everything: `git diff HEAD` reports added and renamed files only once
# they are in the index, and the plugin's changed-file listing is exactly that
# command.
git -C "$GIT_REPO" add -A

capture_git() {
	local name="$1"
	shift
	git -C "$GIT_REPO" "$@" >"$GIT_OUT/$name"
	echo "    $name"
}

capture_git name-status-mixed.txt diff --no-color --name-status HEAD
capture_git diff-modified.txt diff --no-color HEAD -- README.md
capture_git diff-multiple-hunks.txt diff --no-color HEAD -- src/app.lua
capture_git diff-added.txt diff --no-color HEAD -- src/new_feature.lua
capture_git diff-deleted.txt diff --no-color HEAD -- notes.txt
capture_git diff-renamed.txt diff --no-color HEAD -- docs/manual.md
capture_git diff-no-trailing-newline.txt diff --no-color HEAD -- no-newline.txt
capture_git diff-binary.txt diff --no-color HEAD -- assets/logo.bin
# Whole-file content at HEAD. The diff view is handed these and the working
# copy, and lets Neovim compute the diff; nothing here is parsed. The renamed
# file is captured under its OLD name, because that is what the content was
# called at HEAD.
capture_git show-head-modified.txt show --no-color HEAD:README.md
capture_git show-head-multiple-hunks.txt show --no-color HEAD:src/app.lua
capture_git show-head-deleted.txt show --no-color HEAD:notes.txt
capture_git show-head-renamed.txt show --no-color HEAD:docs/guide.md
capture_git show-head-no-trailing-newline.txt show --no-color HEAD:no-newline.txt
capture_git show-head-binary.txt show --no-color HEAD:assets/logo.bin

capture_git ls-files.txt ls-files
capture_git rev-parse-head.txt rev-parse HEAD
capture_git branch-show-current.txt branch --show-current

# ---------------------------------------------------------------------------
# jj
# ---------------------------------------------------------------------------

echo "==> jj"
JJ_REPO="$WORK/jj-demo"
mkdir -p "$JJ_REPO"
(cd "$JJ_REPO" && jj git init . >/dev/null)
seed_committed_state "$JJ_REPO"
(cd "$JJ_REPO" && jj commit --quiet -m "Initial commit")
# `jj git init` leaves no bookmark, and an empty capture would not exercise the
# backend's bookmark parsing at all. It goes on @, because that is the revision
# the backend asks about.
(cd "$JJ_REPO" && jj bookmark create main --revision @ >/dev/null)

(cd "$JJ_REPO" && jj status --no-pager --color never) >"$JJ_OUT/status-clean.txt"

apply_working_changes "$JJ_REPO"

capture_jj() {
	local name="$1"
	shift
	(cd "$JJ_REPO" && jj "$@") >"$JJ_OUT/$name"
	echo "    $name"
}

capture_jj log-change-id.txt log --no-pager --no-graph --color never --revisions @ --template change_id --limit 1
capture_jj log-bookmarks.txt log --no-pager --no-graph --color never --revisions @ --template bookmarks --limit 1
capture_jj status-mixed.txt status --no-pager --color never
capture_jj diff-modified.txt diff --no-pager --color never --git 'file:"README.md"'
capture_jj diff-multiple-hunks.txt diff --no-pager --color never --git 'file:"src/app.lua"'
capture_jj diff-added.txt diff --no-pager --color never --git 'file:"src/new_feature.lua"'
capture_jj diff-deleted.txt diff --no-pager --color never --git 'file:"notes.txt"'
capture_jj diff-renamed.txt diff --no-pager --color never --git 'file:"docs/manual.md"'
capture_jj diff-no-trailing-newline.txt diff --no-pager --color never --git 'file:"no-newline.txt"'
capture_jj diff-binary.txt diff --no-pager --color never --git 'file:"assets/logo.bin"'
# Whole-file content at @-, the counterpart of the git captures above.
capture_jj file-show-modified.txt file show --no-pager --revision @- 'file:"README.md"'
capture_jj file-show-multiple-hunks.txt file show --no-pager --revision @- 'file:"src/app.lua"'
capture_jj file-show-deleted.txt file show --no-pager --revision @- 'file:"notes.txt"'
capture_jj file-show-renamed.txt file show --no-pager --revision @- 'file:"docs/guide.md"'
capture_jj file-show-no-trailing-newline.txt file show --no-pager --revision @- 'file:"no-newline.txt"'
capture_jj file-show-binary.txt file show --no-pager --revision @- 'file:"assets/logo.bin"'

capture_jj file-list.txt file list --no-pager

# ---------------------------------------------------------------------------
# Record the tools that produced all of the above. Output formats drift between
# releases; when a fixture stops describing reality this is the first thing to
# check.
# ---------------------------------------------------------------------------

{
	git --version
	jj --version
} >"$FIXTURES/VERSIONS"

echo
echo "Fixtures regenerated. Review the diff before committing:"
echo "    jj diff tests/fixtures"
