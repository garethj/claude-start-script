#!/bin/bash
# ccp - Claude Code Project launcher
# Usage: ccp <project-name> [-p|-w] [-chrome] [-finder] [-cd]
#   -p      Personal project
#   -w      Work project
#   -chrome Open in Chrome browser
#   -finder Open project directory in Finder
#   -cd     Change to project directory (use with: cd $(ccp -cd ...))

# Defaults (override in .env next to this script, or ~/.ccp.env)
PERSONAL_DIR="$HOME/personal"
WORK_DIR="$HOME/work"

# Load .env overrides
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
[ -f "$HOME/.ccp.env" ] && source "$HOME/.ccp.env"

HISTORY_FILE="$HOME/.ccp_history"
MAX_RECENT=5
DASHBOARD_MODE=false

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Colorize project prefix: [P] in blue, [W] in magenta
# Uses $'...' for real ANSI bytes (sed doesn't interpret \033 notation)
colorize_prefix() {
    local blue_b=$'\033[0;34m\033[1m'
    local mag_b=$'\033[0;35m\033[1m'
    local nc=$'\033[0m'
    sed -e "s/\[P\]/${blue_b}[P]${nc}/g" -e "s/\[W\]/${mag_b}[W]${nc}/g"
}

# Open a command in a new iTerm2 tab
open_in_iterm_tab() {
    local cmd="$1"
    osascript - "$cmd" <<'APPLESCRIPT'
on run argv
    set cmd to item 1 of argv
    tell application "iTerm2"
        tell current window
            create tab with default profile
            tell current session of current tab
                write text cmd
            end tell
        end tell
    end tell
end run
APPLESCRIPT
}

# Show dashboard header
show_dashboard_header() {
    echo -e "${CYAN}━━━ ccp ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Claude Code Project Launcher"
    echo -e "${DIM}  Press Esc to quit${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Record project access in history file
record_access() {
    local type="$1"
    local name="$2"
    local prefix="P"
    [ "$type" = "work" ] && prefix="W"
    local entry="[$prefix] $name"

    # Remove existing entry and add to top (use fixed string, exact line match)
    if [ -f "$HISTORY_FILE" ]; then
        grep -vxF "$entry" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" 2>/dev/null || true
        mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
    fi
    echo "$entry" | cat - "$HISTORY_FILE" 2>/dev/null > "$HISTORY_FILE.tmp" || echo "$entry" > "$HISTORY_FILE.tmp"
    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# Get recent projects from history (only ones that still exist)
get_recent_projects() {
    local filter="$1"
    [ ! -f "$HISTORY_FILE" ] && return

    local count=0
    while IFS= read -r entry && [ $count -lt $MAX_RECENT ]; do
        local prefix="${entry:1:1}"
        local name="${entry:4}"

        # Apply filter
        if [ "$filter" = "personal" ] && [ "$prefix" = "W" ]; then
            continue
        elif [ "$filter" = "work" ] && [ "$prefix" = "P" ]; then
            continue
        fi

        # Check if project still exists
        local dir
        if [ "$prefix" = "P" ]; then
            dir="$PERSONAL_DIR/$name"
        else
            dir="$WORK_DIR/$name"
        fi

        if [ -d "$dir" ]; then
            echo "$entry"
            ((count++))
        fi
    done < "$HISTORY_FILE"
}

# List existing projects with [P] or [W] prefix
list_projects() {
    local filter="$1"  # "personal", "work", or empty for both

    if [ "$filter" != "work" ] && [ -d "$PERSONAL_DIR" ]; then
        for dir in "$PERSONAL_DIR"/*/; do
            [ -d "$dir" ] && echo "[P] $(basename "$dir")"
        done
    fi

    if [ "$filter" != "personal" ] && [ -d "$WORK_DIR" ]; then
        for dir in "$WORK_DIR"/*/; do
            [ -d "$dir" ] && echo "[W] $(basename "$dir")"
        done
    fi
}

# Build hybrid project list: recent first, then separator, then all alphabetically
build_project_list() {
    local filter="$1"
    local use_markers="$2"  # "markers" to add ● prefix to recent items
    local recent
    recent=$(get_recent_projects "$filter")
    local all_projects
    all_projects=$(list_projects "$filter" | sort -t']' -k2)

    if [ -n "$recent" ]; then
        # Remove recent entries from the full list to avoid duplicates
        local filtered_projects="$all_projects"
        while IFS= read -r entry; do
            filtered_projects=$(echo "$filtered_projects" | grep -vxF "$entry")
        done <<< "$recent"

        if [ "$use_markers" = "markers" ]; then
            # Add bullet marker to recent items for non-fzf display
            echo "$recent" | colorize_prefix | sed 's/^/● /'
            echo "$filtered_projects" | colorize_prefix
        else
            echo "$recent" | colorize_prefix
            echo "─────────────"
            echo "$filtered_projects" | colorize_prefix
        fi
    else
        echo "$all_projects" | colorize_prefix
    fi
}

# Interactive project selection menu
select_project() {
    local filter="$1"
    local projects
    projects=$(build_project_list "$filter")

    if [ -z "$projects" ] || [ "$projects" = "─────────────" ]; then
        echo -e "${YELLOW}No existing projects found.${NC}" >&2
        return 1
    fi

    local selected
    if command -v fzf &> /dev/null; then
        selected=$(echo "$projects" | fzf --ansi --prompt="Select project: " --height=80% --reverse --no-sort \
            --header="Recent projects:" \
            --color="header:dim")
    else
        # Use markers for non-fzf display
        local projects_marked
        projects_marked=$(build_project_list "$filter" "markers")
        echo -e "${CYAN}Select a project:${NC}" >&2
        PS3="Enter number: "
        local -a project_array
        while IFS= read -r line; do
            project_array+=("$line")
        done <<< "$projects_marked"
        select project in "${project_array[@]}"; do
            if [ -n "$project" ]; then
                selected="$project"
                break
            fi
        done
    fi

    # Strip ANSI escape codes for parsing
    selected=$(echo "$selected" | sed 's/\x1b\[[0-9;]*m//g')

    # Handle separator selection or empty
    if [ -z "$selected" ] || [[ "$selected" == ─* ]]; then
        return 1
    fi

    # Strip marker prefix (●) if present
    selected="${selected#● }"  # Remove bullet marker
    local prefix="${selected:1:1}"
    PROJECT_NAME="${selected:4}"

    if [ "$prefix" = "P" ]; then
        TYPE="personal"
    else
        TYPE="work"
    fi
}

show_usage() {
    echo -e "${CYAN}ccp${NC} - Claude Code Project launcher"
    echo ""
    echo "Usage: ccp [project-name] [-p|-w] [-chrome] [-finder] [-cd]"
    echo "  -p      Personal project (or filter menu to personal)"
    echo "  -w      Work project (or filter menu to work)"
    echo "  -chrome Open in Chrome browser"
    echo "  -finder Open project directory in Finder"
    echo "  -cd     Output project path for cd (use: cd \$(ccp -cd ...))"
    echo ""
    echo "Examples:"
    echo "  ccp                   # Menu of all existing projects"
    echo "  ccp -p                # Menu of personal projects only"
    echo "  ccp my-app -p         # Open/create personal project"
    echo "  ccp -w my-app -chrome # Work project in Chrome"
    echo "  ccp -finder my-app    # Open project in Finder"
    echo "  cd \$(ccp -cd my-app)  # cd to project directory"
}

PROJECT_NAME=""
TYPE=""
CHROME_FLAG=""
ACTION="claude"  # default: launch claude. alternatives: "finder", "cd"

# Parse all arguments in any order
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -p) TYPE="personal" ;;
        -w) TYPE="work" ;;
        -chrome) CHROME_FLAG="--chrome" ;;
        -finder) ACTION="finder" ;;
        -cd) ACTION="cd" ;;
        -*) echo "Unknown option: $1"; show_usage; exit 1 ;;
        *) PROJECT_NAME="$1" ;;
    esac
    shift
done

# Resolve project path and execute action
# Sets PROJECT_PATH, EXISTING_PROJECT and performs the action
resolve_and_execute() {
    local project_name="$1"
    local type="$2"
    local action="$3"
    local chrome_flag="$4"
    local dashboard="$5"  # "true" if running from dashboard loop

    # Interactive type selection if no type specified
    if [ -z "$type" ]; then
        local local_personal="$PERSONAL_DIR/$project_name"
        local local_work="$WORK_DIR/$project_name"
        local exists_personal=false
        local exists_work=false
        [ -d "$local_personal" ] && exists_personal=true
        [ -d "$local_work" ] && exists_work=true

        if $exists_personal && ! $exists_work; then
            echo -e "${GREEN}Found existing personal project:${NC} $local_personal"
            echo ""
            echo "  [P] Personal  ~/personal/projects/ (exists - default)"
            echo "  [w] Work      ~/work/projects/"
            echo ""
            read -p "Choice (P/w): " choice
            case "$choice" in
                w|W) type="work" ;;
                *) type="personal" ;;
            esac
        elif $exists_work && ! $exists_personal; then
            echo -e "${GREEN}Found existing work project:${NC} $local_work"
            echo ""
            echo "  [p] Personal  ~/personal/projects/"
            echo "  [W] Work      ~/work/projects/ (exists - default)"
            echo ""
            read -p "Choice (p/W): " choice
            case "$choice" in
                p|P) type="personal" ;;
                *) type="work" ;;
            esac
        elif $exists_personal && $exists_work; then
            echo -e "${GREEN}Project exists in both locations:${NC}"
            echo -e "  Personal: $local_personal"
            echo -e "  Work:     $local_work"
            echo ""
            echo "  [p] Personal  ~/personal/projects/"
            echo "  [W] Work      ~/work/projects/ (default)"
            echo ""
            read -p "Choice (p/W): " choice
            case "$choice" in
                p|P) type="personal" ;;
                *) type="work" ;;
            esac
        else
            echo -e "${CYAN}Select project type for '${project_name}':${NC}"
            echo ""
            echo "  [p] Personal  ~/personal/projects/"
            echo "  [W] Work      ~/work/projects/ (default)"
            echo ""
            read -p "Choice (p/W): " choice
            case "$choice" in
                p|P) type="personal" ;;
                *) type="work" ;;
            esac
        fi
    fi

    # Set base directory
    local base_dir
    if [ "$type" = "personal" ]; then
        base_dir="$PERSONAL_DIR"
    else
        base_dir="$WORK_DIR"
    fi

    local project_path="$base_dir/$project_name"

    # Create directory if it doesn't exist
    local existing_project=false
    if [ -d "$project_path" ]; then
        existing_project=true
        [ "$action" != "cd" ] && echo -e "${GREEN}Opening existing project:${NC} $project_path"
    else
        [ "$action" != "cd" ] && echo -e "${YELLOW}Creating new project:${NC} $project_path"
        mkdir -p "$project_path"
    fi

    # Perform the requested action
    case "$action" in
        finder)
            echo -e "${GREEN}Opening in Finder:${NC} $project_path"
            open "$project_path"
            ;;
        cd)
            if [ "$dashboard" = "true" ]; then
                echo -e "${DIM}Skipping -cd in dashboard mode${NC}"
            else
                echo "$project_path"
                cd "$project_path"
            fi
            ;;
        *)
            record_access "$type" "$project_name"
            local continue_flag=""
            $existing_project && continue_flag="--continue"

            if [ "$dashboard" = "true" ]; then
                local cmd="cd $(printf '%q' "$project_path") && claude $continue_flag $chrome_flag"
                if ! open_in_iterm_tab "$cmd"; then
                    echo -e "${YELLOW}Failed to open iTerm2 tab. Is iTerm2 running?${NC}"
                else
                    echo -e "${GREEN}Launched in new tab:${NC} $project_name"
                fi
            else
                cd "$project_path" && claude $continue_flag $chrome_flag
            fi
            ;;
    esac
}

# If no project name, enter dashboard mode (persistent loop)
if [ -z "$PROJECT_NAME" ]; then
    DASHBOARD_MODE=true

    # Save the original type filter (from -p/-w flags)
    TYPE_FILTER="$TYPE"

    # Clean exit on Ctrl-C
    trap 'echo ""; echo -e "${DIM}Exiting ccp dashboard.${NC}"; exit 0' INT

    while true; do
        clear
        show_dashboard_header

        # select_project sets PROJECT_NAME and TYPE from the selection
        if ! select_project "$TYPE_FILTER"; then
            echo ""
            echo -e "${DIM}Exiting ccp dashboard.${NC}"
            break
        fi

        resolve_and_execute "$PROJECT_NAME" "$TYPE" "$ACTION" "$CHROME_FLAG" "true"

        # Reset for next loop iteration
        PROJECT_NAME=""
        TYPE="$TYPE_FILTER"
        # Brief pause so user can see the confirmation
        sleep 1
    done
    exit 0
fi

# Direct invocation (project name given on command line) — unchanged behavior
resolve_and_execute "$PROJECT_NAME" "$TYPE" "$ACTION" "$CHROME_FLAG" "false"
