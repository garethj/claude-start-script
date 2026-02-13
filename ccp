#!/bin/bash
# ccp - Claude Code Project launcher
# Usage: ccp <project-name> [-p|-w] [-chrome] [-finder] [-cd]
#   -p      Personal project
#   -w      Work project
#   -chrome Open in Chrome browser
#   -finder Open project directory in Finder
#   -cd     Change to project directory (use with: cd $(ccp -cd ...))

PERSONAL_DIR="$HOME/personal/projects"
WORK_DIR="$HOME/work/projects"
HISTORY_FILE="$HOME/.ccp_history"
MAX_RECENT=5

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
DIM='\033[2m'
NC='\033[0m' # No Color

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
        if [ "$use_markers" = "markers" ]; then
            # Add bullet marker to recent items for non-fzf display
            echo "$recent" | sed 's/^/● /'
            echo "$all_projects"
        else
            echo "$recent"
            echo "─────────────"
            echo "$all_projects"
        fi
    else
        echo "$all_projects"
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
        selected=$(echo "$projects" | fzf --prompt="Select project: " --height=40% --reverse --no-sort \
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

# If no project name, show interactive menu
if [ -z "$PROJECT_NAME" ]; then
    if ! select_project "$TYPE"; then
        exit 1
    fi
fi

# Interactive selection if no type specified
if [ -z "$TYPE" ]; then
    local_personal="$PERSONAL_DIR/$PROJECT_NAME"
    local_work="$WORK_DIR/$PROJECT_NAME"
    exists_personal=false
    exists_work=false
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
            w|W) TYPE="work" ;;
            *) TYPE="personal" ;;
        esac
    elif $exists_work && ! $exists_personal; then
        echo -e "${GREEN}Found existing work project:${NC} $local_work"
        echo ""
        echo "  [p] Personal  ~/personal/projects/"
        echo "  [W] Work      ~/work/projects/ (exists - default)"
        echo ""
        read -p "Choice (p/W): " choice
        case "$choice" in
            p|P) TYPE="personal" ;;
            *) TYPE="work" ;;
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
            p|P) TYPE="personal" ;;
            *) TYPE="work" ;;
        esac
    else
        echo -e "${CYAN}Select project type for '${PROJECT_NAME}':${NC}"
        echo ""
        echo "  [p] Personal  ~/personal/projects/"
        echo "  [W] Work      ~/work/projects/ (default)"
        echo ""
        read -p "Choice (p/W): " choice
        case "$choice" in
            p|P) TYPE="personal" ;;
            *) TYPE="work" ;;
        esac
    fi
fi

# Set base directory
if [ "$TYPE" = "personal" ]; then
    BASE_DIR="$PERSONAL_DIR"
else
    BASE_DIR="$WORK_DIR"
fi

PROJECT_PATH="$BASE_DIR/$PROJECT_NAME"

# Create directory if it doesn't exist
EXISTING_PROJECT=false
if [ -d "$PROJECT_PATH" ]; then
    EXISTING_PROJECT=true
    [ "$ACTION" != "cd" ] && echo -e "${GREEN}Opening existing project:${NC} $PROJECT_PATH"
else
    [ "$ACTION" != "cd" ] && echo -e "${YELLOW}Creating new project:${NC} $PROJECT_PATH"
    mkdir -p "$PROJECT_PATH"
fi

# Perform the requested action
case "$ACTION" in
    finder)
        echo -e "${GREEN}Opening in Finder:${NC} $PROJECT_PATH"
        open "$PROJECT_PATH"
        ;;
    cd)
        echo "$PROJECT_PATH"
        cd "$PROJECT_PATH"
        ;;
    *)
        record_access "$TYPE" "$PROJECT_NAME"
        CONTINUE_FLAG=""
        $EXISTING_PROJECT && CONTINUE_FLAG="--continue"
        cd "$PROJECT_PATH" && claude $CONTINUE_FLAG $CHROME_FLAG
        ;;
esac
