# RHWA Development Environment

Multi-repo workspace for Red Hat Workload Availability development.

## Quick Start

```bash
./setup.sh          # Clone all repos + sync Claude components
./setup.sh update   # Pull latest + re-sync Claude components
./setup.sh sync     # Re-sync Claude components only
./setup.sh status   # Show repo status
```

## Adding Repositories

1. Add entries to `repos.txt` (format: `url | directory | branch`)
2. Run `./setup.sh clone`
3. Update `CLAUDE.md` with repository descriptions

## Claude Integration

Claude commands, skills, scripts, and agents defined in sub-repos are automatically
symlinked into the top-level `.claude/` directory, prefixed by repo name.
This happens on every `clone`, `update`, or `sync` operation.
