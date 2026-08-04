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

## Config Setup

Skills use a local config file for cluster hostnames, registry URLs, and token paths.

```bash
cp .claude/local/config.yaml.template .claude/local/config.yaml
# Edit config.yaml with your values (or leave defaults for RHWA lab clusters)
```

On first use, skills will ask for any missing values and offer to save them.

## Claude Integration

Claude commands, skills, scripts, and agents defined in sub-repos are automatically
symlinked into the top-level `.claude/` directory, prefixed by repo name.
This happens on every `clone`, `update`, or `sync` operation.
