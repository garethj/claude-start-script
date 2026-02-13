# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a simple bash utility (`ccp` - Claude Code Project launcher) that helps manage and launch Claude Code sessions for different projects. It supports both personal and work project directories with automatic directory creation.

## Deployment

The production version lives at `~/bin/ccp`. After testing changes, copy to production:
```bash
cp ccp "$HOME/bin/ccp"
```

**Note:** The project source path contains spaces, so always use quoted paths when copying.

## Usage

Arguments can be provided in any order:
```bash
ccp                           # Menu of all existing projects (fzf or select)
ccp -p                        # Menu filtered to personal projects only
ccp -w                        # Menu filtered to work projects only
ccp <project-name> -p         # Open/create personal project
ccp -w -chrome <project-name> # Work project in Chrome
ccp <project-name>            # Prompts for type if project is new
```

## Configuration

The script uses two base directories (hardcoded):
- **Personal**: `~/personal/projects/`
- **Work**: `~/work/projects/`
