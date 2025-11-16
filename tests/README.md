# Xray-Fusion Test Suite

This directory contains the test suite for the xray-fusion project.

## Directory Structure

```
tests/
├── README.md           # This file
├── test_helper.bash    # Common test helper functions
├── unit/               # Unit tests
│   ├── test_args_validation.bats
│   └── test_core_functions.bats
├── integration/        # Integration tests (TODO)
└── helpers/            # Test helper scripts (TODO)
```

## Test Framework

Using [bats-core](https://github.com/bats-core/bats-core) - a testing framework designed for Bash.

### Install bats-core

```bash
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# Manual installation
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

## Running Tests

```bash
# Run all tests
bats tests/**/*.bats

# Run unit tests only
bats tests/unit/*.bats

# Run specific test file
bats tests/unit/test_args_validation.bats

# Verbose output
bats -t tests/unit/*.bats

# Run in parallel
bats -j 4 tests/unit/*.bats
```

## Writing Tests

### Basic Structure

```bash
#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

@test "describe your test" {
  run your_command args
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected"* ]]
}
```

### Available Helper Functions

- `setup_test_env`: Create isolated test environment
- `cleanup_test_env`: Clean up test environment
- `assert_file_exists <file>`: Assert file exists
- `assert_dir_exists <dir>`: Assert directory exists
- `assert_equals <expected> <actual>`: Assert equality
- `assert_contains <haystack> <needle>`: Assert contains
- `assert_command_success <cmd> [args]`: Assert command succeeds
- `assert_command_fails <cmd> [args]`: Assert command fails

## Current Test Coverage

### Unit Tests

- ✅ **lib/args.sh**: Parameter validation (19 tests)
  - topology validation
  - domain validation (including internal domain blocking)
  - version validation
  - configuration cross-validation

- ✅ **lib/core.sh**: Core functionality (7 tests)
  - timestamp generation
  - log output (text/JSON)
  - debug log filtering
  - retry mechanism

- ✅ **lib/plugins.sh**: Plugin system (21 tests)
  - plugin directory management
  - plugin ID validation (security checks)
  - plugin enable/disable
  - plugin loading and metadata
  - event emission and hook invocation

- ✅ **modules/io.sh**: IO operations (20 tests)
  - directory creation and permissions
  - writability checks
  - atomic file writes
  - file installation

- ✅ **services/xray/common.sh**: Xray paths (15 tests)
  - path functions (prefix, etc, confbase, releases, active, bin)
  - environment variable overrides
  - path hierarchy consistency

### Test Statistics

- **Test files**: 5
- **Test cases**: 82
- **Code coverage**:
  - lib/args.sh: 100%
  - lib/core.sh: ~85%
  - lib/plugins.sh: ~90%
  - modules/io.sh: ~95%
  - services/xray/common.sh: 100%
  - **Overall**: ~80%

### TODO

- [ ] **services/xray/configure.sh**: Configuration generation tests
- [ ] **modules/web/caddy.sh**: Caddy management tests
- [ ] **integration**: Complete installation flow tests

## CI/CD Integration

Tests run automatically in GitHub Actions (see `.github/workflows/test.yml`).

## Best Practices

1. **Isolation**: Each test uses independent temporary directories
2. **Idempotency**: Tests can be run repeatedly
3. **Speed**: Unit tests should be fast (< 1 second)
4. **Clarity**: Test names should describe expected behavior
5. **Coverage**: Prioritize testing critical paths and edge cases

## Debugging Tests

```bash
# Print each command (verbose mode)
bats -t tests/unit/test_args_validation.bats

# Run only specific test
bats tests/unit/test_args_validation.bats --filter "accepts valid domain"

# Stop on failure
bats --no-parallelize-across-files tests/unit/*.bats
```
