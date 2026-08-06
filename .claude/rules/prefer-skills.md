When the user asks to perform an operational task (check cluster status, deploy
operators, run tests, investigate CI, etc.), ALWAYS scan the available skills
list FIRST before attempting manual commands (SSH, oc, kubectl, pytest, etc.).

Skills like check-cluster, deploy-rhwa, run-system-tests, run-rhwa-tests,
prow-investigate, and others encapsulate the correct access patterns, config
resolution, and output formatting for this project.

Only fall back to manual commands if no matching skill exists.

## Skill execution is mandatory and literal

When executing a skill, follow its steps **in order, one by one**. This is not
a suggestion -- it is a hard requirement.

**NEVER skip, merge, or short-circuit steps.** Specifically:

- NEVER skip a download/copy step because the artifact already exists on the
  target. An old artifact is NOT the same as a fresh one.
- NEVER jump ahead to "run tests" just because you see the test framework is
  already present.
- NEVER combine multiple skill steps into a single command to "save time".
- NEVER assume setup is done based on file existence checks.

If a step produces something that already exists on the target, you MUST:
1. Stop and tell the user what already exists (with timestamps if available)
2. Ask whether to re-do the step fresh or reuse the existing artifact
3. Wait for the user's answer before proceeding

Treat each skill step like a checklist item on an aircraft pre-flight: even if
you "know" it's fine, you run it anyway or you explicitly get sign-off to skip.

## Task tracking for multi-step skills

When a skill has numbered steps (Step 1, Step 2, ... or Phase 1, Phase 2, ...),
**immediately create a task for each step** using TaskCreate before executing
any of them. This makes the checklist visible and prevents skipping steps.

Mark each task as completed only after the step is fully done. Before starting
any step, check the task list -- if a previous step is still incomplete, finish
it first.

## Use the skill's exact commands

When a skill shows a specific command to run (SSH, oc, go test, etc.), **copy
and adapt that exact command**. Do not improvise an alternative command from
scratch. The skill's command was written and tested -- improvised alternatives
often miss critical details (cd to the right directory, correct quoting, etc.).
