Apply response_language to all user-facing prose — narration between tool calls, status updates, progress notes, and findings included; preserve code, paths, and identifiers.

# --chain mode — interactive discuss, then auto-advance

> **Lazy-loaded.** Read this file from `workflows/discuss-phase.md` when
> `--chain` is present in `$ARGUMENTS`, or when `workflow.auto_advance` /
> `workflow._auto_chain_active` is true. **`--auto` alone does not load this file**
> (fork: the /go-and-do chains the commands itself).

## Effect

- Discussion is **fully interactive** — questions, gray-area selection, and
  follow-ups behave exactly the same as default mode.
- After discussion completes, **auto-advance to plan-phase → execute-phase**
  (same downstream behavior as `--auto`).
- This is the middle ground: the user controls the discuss decisions, then
  plan and execute run autonomously.

## auto_advance step (executed by the parent file)

1. Parse `--auto` and `--chain` flags from `$ARGUMENTS`. **Note:** `--all`
   is NOT an auto-advance trigger — it only affects area selection. A
   session with `--all` but without `--auto` or `--chain` returns to manual
   next-steps after discussion completes.

2. **Sync chain flag with intent** — if user invoked manually (no `--auto`
   and no `--chain`), clear the ephemeral chain flag from any previous
   interrupted `--auto` chain. This does NOT touch `workflow.auto_advance`
   (the user's persistent settings preference):
   ```bash
_GAD_HOME=""; for _c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gad-core/bin/gad-tools.cjs"; do [ -n "$_c" ] && [ -f "$_c" ] && _GAD_HOME="$(readlink -f "$(dirname "$(dirname "$(dirname "$(readlink -f "$_c")")")")" 2>/dev/null)" && break; done
[ -n "$_GAD_HOME" ] || { echo "ERROR: go-and-do engine (gad-core) not found under ${CLAUDE_CONFIG_DIR:-$HOME/.claude} — run the go-and-do installer (go-and-do install)" >&2; exit 1; }
_GAD_STATE="${TMPDIR:-/tmp}/gad-tools-path.$(id -u).$(printf '%s' "$_GAD_HOME" | md5sum | cut -c1-8)"; GAD_TOOLS="$(cat "$_GAD_STATE" 2>/dev/null)"
if [ -n "$GAD_TOOLS" ] && [ -f "$GAD_TOOLS" ]; then case "$GAD_TOOLS" in *.cjs) gad_run() { node "$GAD_TOOLS" "$@"; } ;; *) gad_run() { "$GAD_TOOLS" "$@"; } ;; esac; else echo "ERROR: gad-tools state file missing — re-run the Step 1 preamble." >&2; exit 1; fi
   if [[ ! "$ARGUMENTS" =~ --auto ]] && [[ ! "$ARGUMENTS" =~ --chain ]]; then
     gad_run query config-set workflow._auto_chain_active false || true
   fi
   ```

3. Read consolidated auto-mode (`active` = chain flag OR user preference):
   ```bash
   AUTO_MODE=$(gad_run query check auto-mode --pick active 2>/dev/null)
   AUTO_MODE="${AUTO_MODE:-false}"
   ```

4. **If `--auto` or `--chain` flag present AND `AUTO_MODE` is not true:**
   Persist chain flag to config (handles direct usage without new-project):
   ```bash
   gad_run query config-set workflow._auto_chain_active true
   ```

5. **If `--auto` flag present OR `--chain` flag present OR `AUTO_MODE` is
   true:** display banner and launch plan-phase.

   Banner (2 lines): `Context: ${phase_dir}/${padded_phase}-CONTEXT.md — {N} decisions` /
   `Auto-advancing to plan-phase…`

   Launch plan-phase using the Skill tool to avoid nested Task sessions
   (which cause runtime freezes due to deep agent nesting — see #686):
   ```
   Skill(skill="gad-plan-phase", args="${PHASE} --auto ${GAD_WS}")
   ```

   This keeps the auto-advance chain flat — discuss, plan, and execute all
   run at the same nesting level rather than spawning increasingly deep
   Task agents.

6. **Handle plan-phase return:**

   - **PHASE COMPLETE** → Full chain succeeded. Display:
     ```
### GAD ► PHASE ${PHASE} COMPLETE

     Auto-advance pipeline finished: discuss → plan → execute

     /clear then:

     Next: /gad-discuss-phase ${NEXT_PHASE} ${WAS_CHAIN ? "--chain" : "--auto"} ${GAD_WS}
     ```
   - **PLANNING COMPLETE** → Planning done, execution didn't complete:
     ```
     Auto-advance partial: Planning complete, execution did not finish.
     Continue: /gad-execute-phase ${PHASE} ${GAD_WS}
     ```
   - **PLANNING INCONCLUSIVE / CHECKPOINT** → Stop chain:
     ```
     Auto-advance stopped: Planning needs input.
     Continue: /gad-plan-phase ${PHASE} ${GAD_WS}
     ```
   - **GAPS FOUND** → Stop chain:
     ```
     Auto-advance stopped: Gaps found during execution.
     Continue: /gad-plan-phase ${PHASE} --gaps ${GAD_WS}
     ```

7. **If none of `--auto`, `--chain`, nor config enabled:** route to
   `confirm_creation` step (existing behavior — show manual next steps).
