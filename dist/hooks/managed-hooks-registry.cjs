'use strict';

/**
 * Authoritative list of GAD-managed hook files.
 *
 * Extracted from the worker script into a shared CJS module so that:
 *  1. the upstream update-check worker (not shipped by go-and-do) could
 *     require() it directly (no source-level duplication).
 *  2. Tests can assert against the exported array instead of regex-parsing
 *     the worker source (retiring the pending-migration-to-typed-ir token
 *     on managed-hooks.test.cjs and orphaned-hooks.test.cjs, per #455).
 *
 * These are the files GAD ships into ~/.claude/hooks/ (or equivalent) and
 * checks for staleness after an update. Orphaned files from removed features
 * (e.g., gad-intel-*.js) must NOT be listed here — that would cause permanent
 * stale warnings for users who haven't cleaned up manually (#1750).
 */
const MANAGED_HOOKS = [
  'gad-agent-isolation-guard.js',
  'gad-config-reload.js',
  'gad-cursor-post-tool.js',
  'gad-cursor-pre-tool.js',
  'gad-cursor-session-start.js',
  'gad-cursor-stop.js',
  'gad-cursor-subagent-start.js',
  'gad-cursor-subagent-stop.js',
  'gad-ensure-canonical-path.js',
  'gad-graphify-update.sh',
  // #3662: portable node resolver (helper staged in hooks/; managed JS hook
  // commands route through it under --portable-hooks).
  'gad-node-runner.sh',
  'gad-phase-boundary.sh',
  'gad-prompt-guard.js',
  'gad-read-guard.js',
  'gad-read-injection-scanner.js',
  'gad-secret-read-guard.js',
  'gad-session-state.sh',
  'gad-validate-commit.sh',
  'gad-windsurf-pre-command.js',
  'gad-windsurf-pre-write.js',
  'gad-workflow-guard.js',
  'gad-worktree-path-guard.js',
  'gad-write-guard.js',
];

module.exports = { MANAGED_HOOKS };
