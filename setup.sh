#!/bin/bash
#
# RHWA Repositories Setup Script
# ===============================
#
# Usage:
#   ./setup.sh              # Clone all repos (first time setup)
#   ./setup.sh clone        # Clone all repos
#   ./setup.sh update       # Update all repos (git pull)
#   ./setup.sh clone <dir>  # Clone specific repo by directory name
#   ./setup.sh update <dir> # Update specific repo by directory name
#   ./setup.sh status       # Show status of all repos
#   ./setup.sh list         # List configured repos
#   ./setup.sh sync         # Sync Claude components from sub-repos
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/repos"
REPOS_FILE="$SCRIPT_DIR/repos.txt"
REPOS_TEMPLATE="$SCRIPT_DIR/repos.txt.template"
CLAUDE_DIR="$SCRIPT_DIR/.claude"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure repos.txt exists
ensure_repos_file() {
    if [[ ! -f "$REPOS_FILE" ]]; then
        if [[ -f "$REPOS_TEMPLATE" ]]; then
            log_info "Creating repos.txt from template..."
            cp "$REPOS_TEMPLATE" "$REPOS_FILE"
            log_success "Created repos.txt - edit it to customize repo branches/paths"
        else
            log_error "Neither repos.txt nor repos.txt.template found!"
            exit 1
        fi
    fi
}

# Parse a line from repos.txt
# Returns: url, dir, branch (in global variables)
parse_repo_line() {
    local line="$1"

    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && return 1
    [[ -z "${line// }" ]] && return 1

    # Parse pipe-separated fields
    IFS='|' read -r url dir branch <<< "$line"

    # Trim whitespace
    url="$(echo "$url" | xargs)"
    dir="$(echo "$dir" | xargs)"
    branch="$(echo "$branch" | xargs)"

    [[ -z "$url" ]] && return 1
    return 0
}

# Clone a single repository (blobless clone for faster downloads)
clone_repo() {
    local url="$1"
    local dir="$2"
    local branch="$3"

    local target="$REPOS_DIR/$dir"

    if [[ -d "$target/.git" ]]; then
        log_warn "$dir already exists, skipping (use 'update' to pull)"
        return 0
    fi

    # Ensure repos directory exists
    mkdir -p "$REPOS_DIR"

    log_info "Cloning $dir (blobless)..."

    # Blobless clone: all commits/trees downloaded, blobs fetched on-demand
    git clone --filter=blob:none --branch "$branch" "$url" "$target"

    log_success "Cloned $dir (branch: $branch)"
}

# Update a single repository
update_repo() {
    local dir="$1"
    local target="$REPOS_DIR/$dir"

    if [[ ! -d "$target/.git" ]]; then
        log_warn "$dir not cloned yet, skipping"
        return 0
    fi

    log_info "Updating $dir..."

    cd "$target"

    # Check for local changes
    if ! git diff --quiet HEAD 2>/dev/null; then
        log_warn "  $dir has local changes, stashing..."
        git stash
    fi

    git pull --rebase
    cd "$SCRIPT_DIR"

    log_success "Updated $dir"
}

# Sync Claude components (commands, skills, scripts, agents, etc.) from sub-repos
# into the top-level .claude/ directory with {repo}-{name} prefixed names.
#
# - Iterates all DIRECTORIES under each repos/*/.claude/ (future-proof)
# - Naturally skips files like settings.json, settings.local.json
# - Uses a .sync-manifest file per component dir to track synced items for cleanup
# - Preserves original file extensions so Claude Code recognizes all component types
# - Repo-name prefix prevents cross-repo naming conflicts
# - Skills get a patched SKILL.md (name: prefixed) for correct autocomplete
sync_claude_components() {
    log_info "Syncing Claude components from sub-repos..."

    local count=0
    local manifest_suffix=".sync-manifest"

    # Iterate each repo that has a .claude/ directory
    for repo_claude in "$REPOS_DIR"/*/.claude/; do
        [[ -d "$repo_claude" ]] || continue
        local repo
        repo=$(basename "$(dirname "$repo_claude")")

        # Iterate each component directory (commands/, skills/, scripts/, agents/, ...)
        for component_dir in "$repo_claude"/*/; do
            [[ -d "$component_dir" ]] || continue
            local component
            component=$(basename "$component_dir")

            # Create matching top-level directory
            mkdir -p "$CLAUDE_DIR/$component"

            local manifest="$CLAUDE_DIR/$component/${repo}${manifest_suffix}"

            # Remove previously synced items for this repo (from manifest)
            if [[ -f "$manifest" ]]; then
                while IFS= read -r old_item; do
                    [[ -z "$old_item" ]] && continue
                    local old_path="$CLAUDE_DIR/$component/$old_item"
                    if [[ -L "$old_path" ]]; then
                        rm -f "$old_path"
                    elif [[ -d "$old_path" ]]; then
                        rm -rf "$old_path"
                    fi
                done < "$manifest"
                rm -f "$manifest"
            fi
            # Also clean up legacy .link items from previous sync format
            find "$CLAUDE_DIR/$component" -maxdepth 1 -type l -name "${repo}-*.link" -delete
            for old_dir in "$CLAUDE_DIR/$component/${repo}-"*.link; do
                [[ -d "$old_dir" && ! -L "$old_dir" ]] && rm -rf "$old_dir"
            done

            # Sync each item with repo prefix, preserving original extensions
            local new_manifest=""
            for item in "$component_dir"/*; do
                [[ -e "$item" ]] || continue
                local name
                name=$(basename "$item")

                # Skip README files and non-functional docs
                [[ "$name" == "README.md" ]] && continue
                [[ "$name" == "OWNERS" ]] && continue

                local synced_name="${repo}-${name}"
                local synced_path="$CLAUDE_DIR/$component/$synced_name"

                if [[ "$component" == "skills" && -d "$item" && -f "$item/SKILL.md" ]]; then
                    # Skills: create real dir, patch SKILL.md name, symlink the rest
                    rm -rf "$synced_path"
                    mkdir -p "$synced_path"
                    local prefixed_name="${repo}-${name}"
                    sed "s/^name: .*/name: ${prefixed_name}/" "$item/SKILL.md" > "$synced_path/SKILL.md"
                    for subfile in "$item"/*; do
                        [[ -e "$subfile" ]] || continue
                        local subname
                        subname=$(basename "$subfile")
                        [[ "$subname" == "SKILL.md" ]] && continue
                        ln -sf "../../../repos/$repo/.claude/$component/$name/$subname" \
                               "$synced_path/$subname"
                    done
                else
                    ln -sf "../../repos/$repo/.claude/$component/$name" "$synced_path"
                fi
                new_manifest+="${synced_name}"$'\n'
                count=$((count + 1))
            done

            # Write manifest for future cleanup
            if [[ -n "$new_manifest" ]]; then
                printf '%s' "$new_manifest" > "$manifest"
            fi
        done
    done

    log_success "Synced $count Claude components from sub-repos"

    # Report what was synced
    if [[ $count -gt 0 ]]; then
        log_info "Synced components:"
        for component_dir in "$CLAUDE_DIR"/*/; do
            [[ -d "$component_dir" ]] || continue
            local component
            component=$(basename "$component_dir")
            local synced_count=0
            for m in "$component_dir"/*"$manifest_suffix"; do
                [[ -f "$m" ]] || continue
                synced_count=$((synced_count + $(wc -l < "$m")))
            done
            if [[ $synced_count -gt 0 ]]; then
                echo -e "  ${GREEN}$component${NC}: $synced_count items"
                for m in "$component_dir"/*"$manifest_suffix"; do
                    [[ -f "$m" ]] || continue
                    while IFS= read -r entry; do
                        [[ -n "$entry" ]] && echo "    $entry"
                    done < "$m"
                done | sort
            fi
        done
    fi

    # Check for broken symlinks
    local broken
    broken=$(find "$CLAUDE_DIR" -type l ! -exec test -e {} \; -print 2>/dev/null)
    if [[ -n "$broken" ]]; then
        log_warn "Broken symlinks detected (repo may need update):"
        echo "$broken" | while read -r link; do
            echo -e "  ${YELLOW}$link${NC}"
        done
    fi
}

# Clone all repositories
clone_all() {
    log_info "Cloning all repositories..."
    echo

    while IFS= read -r line || [[ -n "$line" ]]; do
        if parse_repo_line "$line"; then
            clone_repo "$url" "$dir" "$branch"
        fi
    done < "$REPOS_FILE"

    echo
    log_success "All repositories cloned!"

    sync_claude_components
}

# Update all repositories
update_all() {
    log_info "Updating all repositories..."
    echo

    while IFS= read -r line || [[ -n "$line" ]]; do
        if parse_repo_line "$line"; then
            if [[ -d "$REPOS_DIR/$dir/.git" ]]; then
                update_repo "$dir"
            fi
        fi
    done < "$REPOS_FILE"

    echo
    log_success "All repositories updated!"

    sync_claude_components
}

# Clone or update a specific repo
handle_specific_repo() {
    local action="$1"
    local target_dir="$2"
    local found=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if parse_repo_line "$line"; then
            if [[ "$dir" == "$target_dir" ]]; then
                found=true
                if [[ "$action" == "clone" ]]; then
                    clone_repo "$url" "$dir" "$branch"
                else
                    update_repo "$dir"
                fi
                break
            fi
        fi
    done < "$REPOS_FILE"

    if [[ "$found" == "false" ]]; then
        log_error "Repository '$target_dir' not found in repos.txt"
        echo "Available repositories:"
        list_repos
        exit 1
    fi

    sync_claude_components
}

# Show status of all repos
show_status() {
    log_info "Repository status:"
    echo
    printf "%-30s %-12s %-20s %s\n" "DIRECTORY" "STATUS" "BRANCH" "LAST COMMIT"
    printf "%-30s %-12s %-20s %s\n" "---------" "------" "------" "-----------"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if parse_repo_line "$line"; then
            local target="$REPOS_DIR/$dir"
            local status branch_info last_commit

            if [[ -d "$target/.git" ]]; then
                cd "$target"
                status="${GREEN}cloned${NC}"
                branch_info="$(git branch --show-current 2>/dev/null || echo 'detached')"
                last_commit="$(git log -1 --format='%h %s' 2>/dev/null | cut -c1-40)"
                cd "$REPOS_DIR"
            else
                status="${YELLOW}not cloned${NC}"
                branch_info="-"
                last_commit="-"
            fi

            printf "%-30s $(echo -e $status)%-1s %-20s %s\n" "$dir" "" "$branch_info" "$last_commit"
        fi
    done < "$REPOS_FILE"
}

# List configured repos
list_repos() {
    echo
    printf "%-30s %-50s %-12s\n" "DIRECTORY" "URL" "BRANCH"
    printf "%-30s %-50s %-12s\n" "---------" "---" "------"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if parse_repo_line "$line"; then
            local short_url="${url#https://github.com/}"
            printf "%-30s %-50s %-12s\n" "$dir" "$short_url" "$branch"
        fi
    done < "$REPOS_FILE"
}

# Print usage
usage() {
    echo "RHWA Repositories Setup Script"
    echo
    echo "Usage:"
    echo "  ./setup.sh              Clone all repos (first time setup)"
    echo "  ./setup.sh clone        Clone all repos"
    echo "  ./setup.sh update       Update all repos (git pull)"
    echo "  ./setup.sh clone <dir>  Clone specific repo by directory name"
    echo "  ./setup.sh update <dir> Update specific repo by directory name"
    echo "  ./setup.sh status       Show status of all repos"
    echo "  ./setup.sh list         List configured repos"
    echo "  ./setup.sh sync         Sync Claude components from sub-repos"
    echo "  ./setup.sh help         Show this help"
    echo
    echo "Configuration:"
    echo "  Edit repos.txt to customize which repos to clone"
    echo "  and which branches to use."
    echo
    echo "Notes:"
    echo "  All repos are cloned with --filter=blob:none (blobless)."
    echo "  Full structure is visible, blobs fetched on-demand."
    echo "  Claude components (commands, skills, etc.) are auto-synced"
    echo "  from sub-repos on clone, update, and sync."
}

# Main
main() {
    ensure_repos_file

    local action="${1:-clone}"
    local target="${2:-}"

    case "$action" in
        clone)
            if [[ -n "$target" ]]; then
                handle_specific_repo "clone" "$target"
            else
                clone_all
            fi
            ;;
        update)
            if [[ -n "$target" ]]; then
                handle_specific_repo "update" "$target"
            else
                update_all
            fi
            ;;
        sync)
            sync_claude_components
            ;;
        status)
            show_status
            ;;
        list)
            list_repos
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown action: $action"
            usage
            exit 1
            ;;
    esac
}

main "$@"
