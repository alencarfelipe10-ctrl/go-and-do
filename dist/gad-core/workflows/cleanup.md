<purpose>

Archive accumulated phase directories from completed milestones into `.planning/milestones/v{X.Y}-phases/`. Identifies which phases belong to each completed milestone, shows a dry-run summary, and moves directories on confirmation. Also offers retroactive archival of `.planning/quick/` (#2142) when it is non-empty.

</purpose>

<required_reading>

1. `.planning/MILESTONES.md`
2. `.planning/milestones/` directory listing
3. `.planning/phases/` directory listing
4. `.planning/quick/` directory listing

</required_reading>

<process>
```bash
_GAD_SHIM_NAME="gad-tools.cjs"; _GAD_RUNTIME_ROOT="${GAD_RUNTIME_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; GAD_TOOLS="${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}"; _gad_at() { for _p; do if [ -f "$_p" ]; then GAD_TOOLS="$_p"; return 0; fi; done; return 1; }; if _gad_at "${_GAD_RUNTIME_ROOT}/gad-core/bin/${_GAD_SHIM_NAME}" "${_GAD_RUNTIME_ROOT}/.claude/gad-core/bin/${_GAD_SHIM_NAME}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/${_GAD_SHIM_NAME}"; then gad_run() { node "$GAD_TOOLS" "$@"; }; else echo "ERRO: motor do go-and-do (gad-core) não encontrado — rode o instalador do go-and-do (go-and-do install) e reinicie a sessão" >&2; exit 1; fi; GAD_IDENTITY_STATUS=unverified; case "$(gad_run runtime-identity --raw 2>/dev/null || true)" in '{"packageName":"go-and-do"'*'}') GAD_IDENTITY_STATUS=ok;; esac; export GAD_IDENTITY_STATUS; [ "$GAD_IDENTITY_STATUS" = ok ] || { echo "ERRO: \"$GAD_TOOLS\" não é o motor do go-and-do (runtime-identity divergente ou ausente) — rode o instalador do go-and-do (go-and-do install)" >&2; exit 1; }; if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${GAD_TOOLS:-}" ]; then printf "export PATH='%s':\"\$PATH\"\n" "${GAD_TOOLS%/*}" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true; fi
RESPONSE_LANGUAGE=$(gad_run query config-get response_language --raw --default "" 2>/dev/null || echo "")
```

**If `response_language` is set:** All user-facing output of this workflow — narration between tool calls, status updates, progress notes, findings, questions, prompts, and explanations — MUST be presented in `{response_language}`. Technical terms, code, file paths, and subagent prompts stay in English — only user-facing output is translated.


<step name="identify_completed_milestones">

Read `.planning/MILESTONES.md` to identify completed milestones and their versions.

```bash
cat .planning/MILESTONES.md
```

Extract each milestone version (e.g., v1.0, v1.1, v2.0).

Check which milestone archive dirs already exist:

```bash
ls -d .planning/milestones/v*-phases 2>/dev/null || true
```

Filter to milestones that do NOT already have a `-phases` archive directory.

If all milestones already have phase archives:

```
All completed milestones already have phase directories archived. Nothing to clean up.
```

Stop here.

</step>

<step name="determine_phase_membership">

For each completed milestone without a `-phases` archive, read the archived ROADMAP snapshot to determine which phases belong to it:

```bash
cat .planning/milestones/v{X.Y}-ROADMAP.md
```

Extract phase numbers and names from the archived roadmap (e.g., Phase 1: Foundation, Phase 2: Auth).

Check which of those phase directories still exist in `.planning/phases/`:

```bash
ls -d .planning/phases/*/ 2>/dev/null || true
```

Match phase directories to milestone membership. Only include directories that still exist in `.planning/phases/`.

</step>

<step name="identify_quick_tasks">

Check whether `.planning/quick/` has anything to retroactively archive (#2142):

```bash
ls -d .planning/quick/*/ 2>/dev/null || true
```

**If no directories are found:** `.planning/quick/` is empty (or absent) — say nothing about quick-task archival and do not offer the step. Skip straight to `show_dry_run` with no quick-task summary or prompt.

**If at least one directory is found:** determine the target milestone. Unlike phase directories — whose milestone membership is derivable from the archived ROADMAP snapshot each completed milestone already has — quick tasks carry **no on-disk provenance** at all; there is no way to tell which milestone any given quick task directory belongs to. The target is therefore the single most recent completed milestone (from `.planning/MILESTONES.md`, already read in `identify_completed_milestones`, listed newest-first) that does not yet have a `-quick` archive directory:

```bash
ls -d .planning/milestones/v*-quick 2>/dev/null || true
```

Walk `.planning/MILESTONES.md`'s entries newest-first and pick the first version with no matching `v{version}-quick` directory above. If every completed milestone already has a `-quick` archive, or `.planning/MILESTONES.md` has no entries, there is no valid target — say so and skip the quick-task step entirely (do not prompt).

</step>

<step name="show_dry_run">

Present a dry-run summary for each milestone:

```
## Cleanup Summary

### v{X.Y} — {Milestone Name}
These phase directories will be archived:
- 01-foundation/
- 02-auth/
- 03-core-features/

Destination: .planning/milestones/v{X.Y}-phases/

### v{X.Z} — {Milestone Name}
These phase directories will be archived:
- 04-security/
- 05-hardening/

Destination: .planning/milestones/v{X.Z}-phases/
```

**If a quick-task target milestone was determined in `identify_quick_tasks`**, add:

```
### Quick tasks — bucket-all into v{X.Y}
{N} directories under .planning/quick/ will ALL be archived into this ONE milestone
(v{X.Y} — {Milestone Name}), regardless of when each was actually completed.
Quick tasks carry no on-disk record of which milestone they belong to, so this is
a bucket-all, not a per-milestone split — unlike the phase archival above, which
is derived per-milestone from each archived ROADMAP snapshot.

Destination: .planning/milestones/v{X.Y}-quick/
```

**Stale local branches (upstream gone):**

First, update remote-tracking refs so the candidate list matches the execution list exactly:

```bash
git fetch --prune 2>/dev/null || true
```

Then enumerate candidates (protected branch names are excluded even if their upstream is gone):

```bash
git branch -vv | awk '/: gone\]/ { if ($1 !~ /^\*$|^main$|^next$|^trunk$|^develop$/) print $1 }'
```

Show each branch name. If none, show:

```
No stale local branches detected.
```

If no phase directories remain to archive (all already moved or deleted) AND no stale branches exist AND no quick-task target milestone was determined:

```
No phase directories found to archive. Phases may have been removed or archived previously.
No stale local branches detected either.
No quick tasks to archive either.
```

Stop here.


**Text mode (`workflow.text_mode: true` in config or `--text` flag):** Set `TEXT_MODE=true` if `--text` is present in `$ARGUMENTS` OR `text_mode` from init JSON is `true`. When TEXT_MODE is active, replace every `AskUserQuestion` call with a plain-text numbered list and ask the user to type their choice number. This is required for non-Claude runtimes (OpenAI Codex, Gemini CLI, etc.) where `AskUserQuestion` is not available.
AskUserQuestion: "Proceed with archiving and pruning?" with options: "Yes — archive phases and prune stale branches" | "Cancel"

If "Cancel": Stop.

**If a quick-task target milestone was determined in `identify_quick_tasks`**, ask a separate, explicit question — this is a distinct, bucket-all action and must not be silently folded into the "Yes" above:

AskUserQuestion: "Archive ALL {N} quick-task directories into v{X.Y} — {Milestone Name}? This buckets every remaining quick task into this ONE milestone; there is no way to split them per-milestone." with options: "Yes — archive quick tasks into v{X.Y}" | "Skip"

If "Skip": do not run `archive_quick_tasks` — proceed to `archive_phases` (or `report`, if there were no phase directories to archive) with quick-task archival omitted.

</step>

<step name="archive_phases">

For each milestone, move phase directories:

```bash
mkdir -p .planning/milestones/v{X.Y}-phases
```

For each phase directory belonging to this milestone:

```bash
mv .planning/phases/{dir} .planning/milestones/v{X.Y}-phases/
```

Repeat for all milestones in the cleanup set.

</step>

<step name="archive_quick_tasks">

Only run this step when the "Yes — archive quick tasks into v{X.Y}" option was confirmed in `show_dry_run`.

Uses the narrow `milestone.archive-quick` command (#2142 escalation) rather than `milestone.complete --archive-quick`: cleanup runs against milestones that are typically ALREADY completed, and `milestone.complete` is the full close-out — it archives ROADMAP/REQUIREMENTS and writes a MILESTONES.md entry, so re-running it against an already-completed milestone would clobber that milestone's archived ROADMAP/REQUIREMENTS snapshot (the very snapshot this cleanup depends on) and duplicate its MILESTONES.md entry. `milestone.archive-quick` shares the same move/README-index/table-reset logic as `milestone.complete --archive-quick` (same underlying helper) without any of that.

```bash
gad_run query milestone.archive-quick "v{X.Y}"
```

This moves every directory under `.planning/quick/` into `.planning/milestones/v{X.Y}-quick/`, (re)writes that directory's `README.md` index, and clears STATE.md's `### Quick Tasks Completed` table rows — identical move/index/reset behavior to the `--archive-quick` flag documented in `complete-milestone.md`'s `archive_milestone` step, without touching ROADMAP.md, REQUIREMENTS.md, MILESTONES.md, or milestone-completion guards. Extract `archived` from the result to confirm.

</step>

<step name="prune_local_branches">

After phase archival, prune local branches whose upstream has been deleted. Use the same filter as the dry-run so the execution list matches exactly what the user confirmed:

```bash
git branch -vv | awk '/: gone\]/ { if ($1 !~ /^\*$|^main$|^next$|^trunk$|^develop$/) print $1 }' | xargs -r git branch -D
```

Notes:
- `git fetch --prune` already ran in `show_dry_run` — the tracking refs are current and this step enumerates from the same state the user confirmed.
- `!~ /^\*$/` skips the currently checked-out branch (prefixed with `* ` in `git branch -vv` output, so `$1` yields `*`).
- `!~ /^main$|^next$|^trunk$|^develop$/` excludes protected branch names even if their upstream is gone — matches the dry-run exclusion exactly.
- `xargs -r` prevents `git branch -D` from running with no arguments when no stale branches exist.

</step>

<step name="commit">

Commit the changes:

```bash
gad_run query commit "chore: archive phase directories from completed milestones" --files .planning/milestones/ .planning/STATE.md --files-removed .planning/phases/ .planning/quick/
```

`.planning/phases/` and `.planning/quick/` go under `--files-removed`, not `--files` (#4208): a `--files` directory entry stages everything under it, so it would also commit any in-flight phase or quick-task file a concurrent session had written there. `--files-removed` stages only the tracked files under those directories that the archival `mv` moved away, and leaves everything still present untouched.

</step>

<step name="report">

```
Archived:
{For each milestone}
- v{X.Y}: {N} phase directories → .planning/milestones/v{X.Y}-phases/
{If quick-task archival ran}
- v{X.Y}: {N} quick-task directories → .planning/milestones/v{X.Y}-quick/ (bucket-all — see known limit)

Pruned: {N} local branches whose upstream is gone.

.planning/phases/ cleaned up.
```

</step>

</process>

<success_criteria>

- [ ] All completed milestones without existing phase archives identified
- [ ] Phase membership determined from archived ROADMAP snapshots
- [ ] Dry-run summary shown and user confirmed (covers both archival and pruning)
- [ ] Phase directories moved to `.planning/milestones/v{X.Y}-phases/`
- [ ] Stale local branches pruned (branches whose upstream is gone)
- [ ] `.planning/quick/` checked; quick-task archival offered only when non-empty
- [ ] When offered and confirmed, ALL remaining quick-task directories archived into the single named target milestone (bucket-all, not per-milestone) via `milestone.archive-quick`
- [ ] Changes committed

</success_criteria>
