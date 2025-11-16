# Claude Code Configuration

This directory contains Claude Code configuration for the xray-fusion project.

## SessionStart Hook

The SessionStart hook automatically runs when a new Claude Code session starts, ensuring development tools are ready.

### Configuration

Hooks are defined in `.claude/settings.json` following the [official documentation](https://code.claude.com/docs/en/hooks):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/session-start.sh"
          }
        ]
      }
    ]
  }
}
```

The `"matcher": "startup"` ensures the hook only runs on new session initialization, not on resume/clear/compact events.

### What it Does

The SessionStart hook automatically installs development tools in **web/iOS environments only**:

- **shfmt v3.8.0** - Shell script formatter
- **shellcheck v0.10.0** - Shell script linter
- **bats-core v1.11.0** - Bash Automated Testing System

**Matcher-Based Triggering**:
- **startup**: New session initialization → **Hook runs** (auto-install tools)
- **resume**: Resume from `/resume` or `--resume` → **Hook does NOT run**
- **clear**: After `/clear` command → **Hook does NOT run**
- **compact**: Auto/manual compaction → **Hook does NOT run**

**Environment Detection**:
- **Web/iOS** (`CLAUDE_CODE_REMOTE=true`): Auto-install tools to `~/.local/bin/`
- **Desktop** (`CLAUDE_CODE_REMOTE=false` or unset): Skip auto-install, show manual installation instructions

These tools are installed to `~/.local/bin/` (and `~/.local/share/bats-core/` for bats) and only downloaded if not already present.

### File Structure

```
.claude/
├── settings.json              # Hook configuration (committed)
├── settings.local.json        # User-specific overrides (gitignored)
├── scripts/
│   └── session-start.sh      # SessionStart hook script (committed)
└── README.md                  # This file
```

### Customization

To customize hook behavior:

1. **For personal use**: Create `.claude/settings.local.json` (gitignored)
2. **For team-wide changes**: Edit `.claude/settings.json` and commit

Example `.claude/settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/my-custom-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### Testing

Test the hook script manually:

```bash
./.claude/scripts/session-start.sh
```

### How It Works

When you start a new Claude Code session:

1. Claude Code reads `.claude/settings.json` (and `.claude/settings.local.json` if exists)
2. **Only on `startup` events**: SessionStart hook is triggered (matcher: `"startup"`)
3. **On `resume/clear/compact` events**: Hook does NOT run (filtered by matcher)
4. Hook script installs missing tools to `~/.local/bin/` (web/iOS only)
5. Tools are ready for `make fmt`, `make lint`, etc.

### Optimization Benefits

**Performance**: Matcher-based filtering ensures installation tasks only run once at first startup, not on every session resume/clear/compact.

**Reliability**: Existing tools remain available across session operations without redundant reinstallation.

**Simplicity**: No need for complex JSON parsing logic - Claude Code's matcher system handles event filtering natively.

### Notes

- **Committed files**: `settings.json`, `scripts/session-start.sh` (project-wide automation)
- **Gitignored files**: `settings.local.json` (user-specific overrides)
- **Installation**: Tools are installed per-user to `~/.local/bin/` (no sudo required)
- **Idempotent**: Safe to run multiple times, won't reinstall existing tools

### References

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [SessionStart Hook Guide](https://code.claude.com/docs/en/hooks#sessionstart)
