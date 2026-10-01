# plan-phase — auto-advance (step 15)

Lazy block of `workflows/plan-phase.md`. Read it at step 14 only when `--auto` or `--chain` is in `$ARGUMENTS`, or `auto_chain_active` / `auto_advance` from the init JSON is true; a manual run routes to `<offer_next>` without opening this file (the chain-flag clean-up for manual runs lives in the core's step 14).

## 15. Auto-Advance Check

Check for auto-advance trigger using values already loaded in step 1:

1. Parse `--auto` and `--chain` flags from $ARGUMENTS
2. Use `auto_chain_active` and `auto_advance` from the INIT JSON parsed in step 1 — **do not issue additional `config-get` calls for these values** (they are already present in the init output). Issuing redundant `config-get` calls for values already in INIT can cause infinite read loops on some runtimes.
3. **Sync chain flag with intent** — if user invoked manually (no `--auto` and no `--chain`), clear the ephemeral chain flag from any previous interrupted `--auto` chain. This does NOT touch `workflow.auto_advance` (the user's persistent settings preference):
   ```bash
   if [[ ! "$ARGUMENTS" =~ --auto ]] && [[ ! "$ARGUMENTS" =~ --chain ]]; then
     gad_run query config-set workflow._auto_chain_active false || true
   fi
   ```

Set local variables from INIT (parsed once in step 1):
- `AUTO_CHAIN` = `auto_chain_active` from INIT JSON (boolean, default false)
- `AUTO_CFG` = `auto_advance` from INIT JSON (boolean, default false)

**If `--auto` or `--chain` flag present AND `AUTO_CHAIN` is not true:** Persist chain flag to config (handles direct invocation without prior discuss-phase):
```bash
if ([[ "$ARGUMENTS" =~ --auto ]] || [[ "$ARGUMENTS" =~ --chain ]]) && [[ "$AUTO_CHAIN" != "true" ]]; then
  gad_run query config-set workflow._auto_chain_active true
fi
```

**If `--auto` or `--chain` flag present OR `AUTO_CHAIN` is true OR `AUTO_CFG` is true:**

Display banner:
```
### GAD ► AUTO-ADVANCING TO EXECUTE

Plans ready. Launching execute-phase...
```

Launch execute-phase using the Skill tool to avoid nested Task sessions (which cause runtime freezes due to deep agent nesting):
```
Skill(skill="gad-execute-phase", args="${PHASE} --auto --no-transition ${GAD_WS}")
```

The `--no-transition` flag tells execute-phase to return status after verification instead of chaining further. This keeps the auto-advance chain flat — each phase runs at the same nesting level rather than spawning deeper Task agents.

**Handle execute-phase return:**
- **PHASE COMPLETE** → Display final summary:
  ```
### GAD ► PHASE ${PHASE} COMPLETE ✓

  Auto-advance pipeline finished.

  Next: /gad-discuss-phase ${NEXT_PHASE} --auto ${GAD_WS}
  ```
- **GAPS FOUND / VERIFICATION FAILED** → Display result, stop chain:
  ```
  Auto-advance stopped: Execution needs review.

  Review the output above and continue manually:
  /gad-execute-phase ${PHASE} ${GAD_WS}
  ```

**If neither `--auto` nor config enabled:**
Route to `<offer_next>` (existing behavior).

