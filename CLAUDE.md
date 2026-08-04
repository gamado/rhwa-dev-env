# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Environment Purpose

This workspace serves as an **RHWA (Red Hat Workload Availability) development environment template**. It aggregates relevant source repositories under `repos/` so developers and QA can work with Claude across the full project context.

**Workflow:**
1. Developers/QA clone this repo as their workspace root
2. All RHWA-relevant source repositories are cloned under the `repos/` folder
3. Work with Claude from this top-level directory to get full context across all repos
4. Navigate into specific `repos/<repo-name>/` directories to implement changes

**The `repos/` folder contains all source code.** This CLAUDE.md provides a summary of each repository's relevance to RHWA.

## Multi-repo Claude Discovery

Each repo under `repos/` may have its own `.claude/` directory with commands, skills, scripts, agents, and other components. Running `./setup.sh sync` (also runs automatically on clone/update) symlinks them into the top-level `.claude/` with `{repo}-{name}` prefix.

- Use `/help` to see all available commands from all sub-repos
- Commands are prefixed by repo name: e.g. `/two-node-toolbox-etcd`
- When working on a specific sub-repo, also check for and read its root-level `CLAUDE.md` and `AGENTS.md` for repo-specific instructions

### Source of Truth Priority

**IMPORTANT**: When answering questions or implementing changes:
1. **Always look at repos in this workspace FIRST** before using internal knowledge or web searches
2. If a component has a repo here, that repo is the **authoritative source of truth**
3. Code in `repos/` reflects the latest development state, which may differ from public documentation

### Fork Model

All repositories use a fork model for contributions unless noted otherwise:
- Push changes to your personal fork first, not directly to upstream
- Create pull requests from your fork to the upstream repository

## Config Resolution

Config file: `.claude/local/config.yaml` (gitignored, auto-populated by skills)

When any skill needs infrastructure details (cluster hostnames, kubeconfig paths,
registry URLs, token file paths, internal URLs), check `.claude/local/config.yaml` first.
If a needed value is missing, ask the user and offer to save it for next time.

Skills must never contain hardcoded hostnames, passwords, or local paths.
SSH key-based auth is recommended. If SSH keys are not set up, the user may
optionally store a password in config (not recommended).

Supported keys:

    clusters.<name>.host        -- FQDN of the cluster server
    clusters.<name>.arch        -- arm64 or x86
    clusters.<name>.kubeconfig  -- path to kubeconfig on that server
    clusters.<name>.auth        -- "ssh-key" (default) or "sshpass"
    clusters.<name>.password    -- only if auth=sshpass (not recommended)
    registries.iib              -- IIB registry base URL
    registries.iib_fallback     -- fallback IIB registry URL
    tokens.github               -- path to GitHub token file
    tokens.jira                 -- path to Jira token file
    urls.polarion               -- Polarion base URL
    urls.build_doc              -- build location doc URL
    urls.test_tutorial          -- testing team tutorial URL
    urls.gitlab_qe              -- QE automation repo URL

---

## Repositories

All repositories are located in the `repos/` folder.

### two-node-toolbox (`repos/two-node-toolbox/`)
**Category**: Deployment / Tooling

**Purpose**: Deployment automation framework for two-node OpenShift clusters in development and testing environments

**Commands**: See `./setup.sh sync` output or `/help` for available Claude commands from this repo.

---

*Add more repositories to `repos.txt` and re-run `./setup.sh clone` to expand this workspace.*
