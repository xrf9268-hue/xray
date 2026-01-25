# xray-fusion

Bash-based Xray proxy deployment tool with automated certificate management.

## Quick Reference

```bash
# Development (must pass before commit)
make fmt          # Format code (shfmt)
make lint         # Static analysis (shellcheck)
make test-unit    # Unit tests (bats)

# Run locally
bin/xrf install --topology reality-only
bin/xrf status
bin/xrf uninstall

# Debug mode
XRF_DEBUG=true bin/xrf install --topology reality-only
```

## Project Structure

```
bin/xrf           # CLI entrypoint
commands/         # High-level workflows (install.sh, status.sh)
lib/              # Core utilities (core.sh, args.sh, validators.sh)
modules/          # Helpers (io.sh, state.sh, fw/*, web/*)
services/xray/    # Xray install/configure/systemd
plugins/          # Plugin system
tests/unit/       # bats test files
```

## Code Style

- Bash with `set -euo pipefail`
- 2-space indentation (see `.editorconfig`)
- Namespacing: `namespace::function` (e.g., `core::log`, `io::atomic_write`)
- Variables: lowercase `local`, UPPER_SNAKE for exports (`XRF_*`, `XRAY_*`)

## Key APIs

Use these helpers instead of raw implementations:

| Function | Purpose |
|----------|---------|
| `core::log level msg ctx` | Structured logging (always use, never echo) |
| `core::with_flock lock cmd` | Execute with exclusive file lock |
| `io::ensure_dir dir mode` | Create directory with sudo fallback |
| `io::atomic_write file mode` | Atomic file write from stdin |
| `validators::domain domain` | RFC-compliant domain validation |
| `xray::generate_shortid` | Generate 16-char hex shortId |

## Development Workflow

Use Test-Driven Development:
1. Write failing test
2. Implement until test passes
3. Run `make fmt && make lint && make test-unit`
4. Commit

## Critical Rules

**Security**:
- Verify downloaded code integrity BEFORE execution (CWE-494)
- Fix both ownership AND permissions for shared files (CWE-283)
- Use `io::atomic_write` for safe file operations (CWE-362)

**Shell patterns**:
- Never use EXIT traps in utility functions (breaks pipelines)
- Source guards required for libraries with readonly variables
- Explicitly source all module dependencies

**Quality**:
- All logs to stderr via `core::log`
- Network operations need retry logic (`core::retry`)
- Normalize external tool output before parsing (formats change)

## Documentation

- [AGENTS.md](./AGENTS.md) - Technical reference and patterns
- [docs/adr/](./docs/adr/) - Architecture Decision Records
- [.claude/](./.claude/) - Claude Code hooks and commands
