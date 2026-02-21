# ccp

A launcher for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that organises projects into personal and work directories.

Run `ccp` to get an interactive project picker. Pick a project and it opens Claude Code in that directory, resuming any previous conversation.

## Install

Copy the script somewhere on your `$PATH`:

```bash
cp ccp ~/bin/ccp
```

Requires bash. Optional: [fzf](https://github.com/junegunn/fzf) for a better selection menu.

## Usage

Arguments work in any order:

```bash
ccp                           # Interactive project picker
ccp my-app -p                 # Open/create a personal project
ccp -w my-app                 # Open/create a work project
ccp -w my-app -chrome         # Work project with Chrome integration
ccp my-app -finder            # Open project directory in Finder
cd $(ccp -cd my-app)          # cd to a project directory
```

### Flags

| Flag      | Description                              |
|-----------|------------------------------------------|
| `-p`      | Personal project (or filter menu)        |
| `-w`      | Work project (or filter menu)            |
| `-chrome` | Pass `--chrome` to Claude Code           |
| `-finder` | Open directory in Finder instead         |
| `-cd`     | Output project path (for use with `cd`)  |

### Dashboard mode

Run `ccp` with no project name to enter a persistent dashboard. It shows a menu of all projects, sorted with recent projects first. Select one and it launches in a new iTerm2 tab, then returns to the menu.

With fzf installed, you get extra key bindings:

- **Enter**: Launch Claude Code
- **T**: Open a terminal tab in the project directory
- **F**: Open in Finder

### New projects

If you name a project that doesn't exist, `ccp` creates the directory and starts a fresh Claude Code session. If you don't specify `-p` or `-w`, it asks you to choose.

## Configuration

Projects live in two base directories. Defaults:

- **Personal**: `~/personal`
- **Work**: `~/work`

Override these by setting `PERSONAL_DIR` and `WORK_DIR` in either:

- A `.env` file next to the script
- `~/.ccp.env`

## How it works

`ccp` keeps a history of recently accessed projects in `~/.ccp_history`. The dashboard shows these at the top for quick access. When opening an existing project, it passes `--continue` to Claude Code to resume the last conversation.
