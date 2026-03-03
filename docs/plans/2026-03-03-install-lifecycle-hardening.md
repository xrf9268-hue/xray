# Install Lifecycle Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate install/uninstall lifecycle regressions (lint break, uninstall non-idempotency, sudo coupling, lock hang risk, and cert-dir mismatch) and make installation behavior consistent across default/custom prefixes.

**Architecture:** Apply focused hardening in five runtime layers: command safety (`uninstall`), privilege execution (`user` module), lock semantics (`core::with_flock`), service unit rendering (`systemd-unit`), and install/state/health data flow (`install` + `health_check`). Drive every change with failing tests first, then minimal implementation, then targeted verification, and finally Docker lifecycle validation.

**Tech Stack:** Bash, Bats, ShellCheck, jq, Docker (Ubuntu 24.04), systemd-unit integration scripts.

---

### Task 1: Fix Lint Gate and Export Module Hygiene

**Files:**
- Modify: `lib/export.sh`
- Test: `tests/unit/test_export_command.bats`

**Step 1: Write the failing lint expectation context**

Document current lint failure in commit notes and local scratch log:
- `SC2034` at `lib/export.sh` (`local line link`, `line` unused).

**Step 2: Run lint to verify current failure**

Run: `make lint`
Expected: FAIL with `SC2034` in `lib/export.sh`.

**Step 3: Implement minimal fix**

Edit `lib/export.sh`:
- Remove unused `line` declaration in `export::uri_raw`.
- Keep function behavior unchanged.

**Step 4: Run lint and export tests**

Run:
- `make lint`
- `bats -t tests/unit/test_export_command.bats`
Expected: both PASS.

**Step 5: Commit**

```bash
git add lib/export.sh tests/unit/test_export_command.bats
git commit -m "lib: fix export lint regression"
```

### Task 2: Make `xrf uninstall` Idempotent and Trap-Safe

**Files:**
- Modify: `commands/uninstall.sh`
- Modify: `tests/unit/test_uninstall_command.bats`

**Step 1: Write failing test for idempotent remove helper**

In `tests/unit/test_uninstall_command.bats`, change/add expectation:
- `_rm` on non-existent path should return `0` (no-op), not `1`.

**Step 2: Run test to verify it fails now**

Run: `bats -t tests/unit/test_uninstall_command.bats`
Expected: FAIL on non-existent path test.

**Step 3: Implement minimal `_rm` fix**

In `commands/uninstall.sh`:
- Replace `[[ -e ... || -L ... ]] && { ... }` with explicit guard:
  - if missing path: `return 0`
  - if exists: delete and return `0`
- Keep logging behavior unchanged.

**Step 4: Verify uninstall tests and integration check**

Run:
- `bats -t tests/unit/test_uninstall_command.bats`
- `make test-integration` (observe `test_systemd_unit` behavior unchanged or improved)
Expected: unit PASS; no new integration regression.

**Step 5: Commit**

```bash
git add commands/uninstall.sh tests/unit/test_uninstall_command.bats
git commit -m "commands: make uninstall idempotent"
```

### Task 3: Remove Hard `sudo` Requirement in User Provisioning

**Files:**
- Modify: `modules/user/user.sh`
- Modify: `tests/unit/test_user.bats`

**Step 1: Add failing tests for root-without-sudo and non-root-with-sudo paths**

In `tests/unit/test_user.bats`:
- Case A: `EUID=0`, `sudo` missing -> should still call `groupadd/useradd` directly and succeed.
- Case B: non-root path still uses sudo wrapper behavior.

**Step 2: Run targeted user tests (expect fail)**

Run: `bats -t tests/unit/test_user.bats`
Expected: new tests FAIL before implementation.

**Step 3: Implement privilege abstraction**

In `modules/user/user.sh`:
- Add helper (e.g., `user::_run_privileged`) that:
  - runs command directly when effective UID is root;
  - otherwise runs via `core::sudo_cmd` (or `sudo` with explicit error handling if keeping current pattern).
- Use helper for both `groupadd` and `useradd`.
- Preserve structured logs and return codes.

**Step 4: Verify tests and install path safety**

Run:
- `bats -t tests/unit/test_user.bats`
- `bats -t tests/unit/test_systemd_unit.bats`
Expected: PASS and no behavior regression.

**Step 5: Commit**

```bash
git add modules/user/user.sh tests/unit/test_user.bats tests/unit/test_systemd_unit.bats
git commit -m "modules: support root installs without sudo dependency"
```

### Task 4: Harden `core::with_flock` Against Long Blocking and FD Inheritance Side-Effects

**Files:**
- Modify: `lib/core.sh`
- Modify: `tests/unit/test_core_edge_cases.bats`
- Modify: `tests/unit/test_core_functions.bats`

**Step 1: Add failing lock-timeout regression test**

Add tests that:
- hold lock from process A;
- run `core::with_flock` from process B with short timeout;
- assert fast failure with clear error log (instead of hanging indefinitely).

**Step 2: Run core flock tests to capture failure**

Run:
- `bats -t tests/unit/test_core_functions.bats`
- `bats -t tests/unit/test_core_edge_cases.bats`
Expected: new timeout test FAIL/hang before fix.

**Step 3: Implement lock acquisition best practice**

In `lib/core.sh`:
- Add `XRF_FLOCK_TIMEOUT_SEC` (default, e.g., `30`).
- Use `flock` with timeout and close-on-exec behavior (path-based lock invocation), so lock acquisition cannot block forever and long-running children cannot keep inherited lock descriptors open unintentionally.
- Keep no-`flock` directory-lock fallback behavior intact.

**Step 4: Verify lock behavior**

Run:
- `bats -t tests/unit/test_core_functions.bats`
- `bats -t tests/unit/test_core_edge_cases.bats`
Expected: PASS; timeout test deterministic.

**Step 5: Commit**

```bash
git add lib/core.sh tests/unit/test_core_functions.bats tests/unit/test_core_edge_cases.bats
git commit -m "lib: harden flock acquisition and timeout behavior"
```

### Task 5: Make systemd Unit Render Dynamic Paths and Preserve Prefix/Etc Overrides

**Files:**
- Modify: `services/xray/systemd-unit.sh`
- Modify: `packaging/systemd/xray.service` (if kept as template)
- Modify: `tests/unit/test_systemd_unit.bats`

**Step 1: Add failing test for custom path rendering**

In `tests/unit/test_systemd_unit.bats`, assert generated unit contains:
- `ExecStart=$(xray::bin) ...`
- `ReadWritePaths=$(xray::confbase)`
when `XRF_PREFIX/XRF_ETC` are custom.

**Step 2: Run systemd unit tests (expect fail)**

Run: `bats -t tests/unit/test_systemd_unit.bats`
Expected: FAIL on new path assertions.

**Step 3: Implement dynamic unit generation**

In `services/xray/systemd-unit.sh`:
- Generate final unit file from dynamic values (`xray::bin`, `xray::confbase`, `xray::active`) instead of hardcoded `/usr/local/...` paths.
- Keep security directives unchanged.

**Step 4: Verify unit tests and install flow integration**

Run:
- `bats -t tests/unit/test_systemd_unit.bats`
- `bats -t tests/integration/test_systemd_unit.bats`
Expected: PASS or only known pre-existing skips/failures unrelated to this task.

**Step 5: Commit**

```bash
git add services/xray/systemd-unit.sh packaging/systemd/xray.service tests/unit/test_systemd_unit.bats tests/integration/test_systemd_unit.bats
git commit -m "services: render systemd unit with dynamic xray paths"
```

### Task 6: Align Install State, Backup Trigger, and Health Certificate Checks

**Files:**
- Modify: `commands/install.sh`
- Modify: `lib/health_check.sh`
- Modify: `tests/unit/test_health_check.bats`
- Modify: `tests/integration/test_install_flow.bats`

**Step 1: Add failing tests for cert-dir data flow and stale-state backup guard**

Add tests for:
- `vision-reality` state with custom `.xray.cert_dir` must be honored by `health::check_certificates`.
- install auto-backup should skip cleanly when `state.json` exists but config directory is absent (post-uninstall scenario), without warning as a failure path.

**Step 2: Run targeted tests (expect fail)**

Run:
- `bats -t tests/unit/test_health_check.bats`
- `bats -t tests/integration/test_install_flow.bats`
Expected: FAIL on new assertions.

**Step 3: Implement minimal data-flow fixes**

In `commands/install.sh`:
- Store `xray.cert_dir` into state for `vision-reality`.
- Gate auto-backup precondition on both existing state and existing config source directory.

In `lib/health_check.sh`:
- Use `.xray.cert_dir // DEFAULT_XRAY_CERT_DIR` for certificate checks and messages.

In `tests/integration/test_install_flow.bats`:
- Update brittle string assertions (`requires domain`, `invalid topology`) to match current structured output semantics.

**Step 4: Verify tests**

Run:
- `bats -t tests/unit/test_health_check.bats`
- `bats -t tests/integration/test_install_flow.bats`
Expected: PASS.

**Step 5: Commit**

```bash
git add commands/install.sh lib/health_check.sh tests/unit/test_health_check.bats tests/integration/test_install_flow.bats
git commit -m "commands: align install state and health cert-dir behavior"
```

### Task 7: Full Verification and Docker Lifecycle Regression Matrix

**Files:**
- Create: `scripts/e2e/install-lifecycle-smoke.sh`
- Modify: `README.md` (optional short section under testing)

**Step 1: Write Docker lifecycle smoke script**

Create script covering:
- fresh install;
- in-place reinstall;
- uninstall -> reinstall;
- topology switch (`reality-only -> vision-reality` with test certs);
- verify binary/config/state/systemd outcomes and exit codes.

**Step 2: Run script once to confirm deterministic failures (if any)**

Run: `bash scripts/e2e/install-lifecycle-smoke.sh`
Expected: deterministic report with explicit pass/fail checkpoints.

**Step 3: Adjust only test harness logic (not product logic) for stable assertions**

Ensure script handles environment constraints (container `systemctl` differences) while still flagging genuine regressions.

**Step 4: Run full project verification**

Run:
- `make fmt`
- `make lint`
- `make test-unit`
- `make test-integration`
- `bash scripts/e2e/install-lifecycle-smoke.sh`
Expected: no blocking failures; lifecycle scenarios pass in documented environment.

**Step 5: Final commit**

```bash
git add scripts/e2e/install-lifecycle-smoke.sh README.md
git commit -m "tests: add docker lifecycle smoke coverage"
```

## Final Acceptance Checklist

1. `make lint` has zero warnings/errors.
2. `xrf uninstall` is idempotent (second run exits `0`).
3. Install works in root container without requiring `sudo` binary.
4. Reinstall cannot hang indefinitely on configure lock.
5. systemd unit paths follow configured prefix/etc paths.
6. `vision-reality` health checks honor configured cert directory.
7. Docker lifecycle matrix reports pass for fresh/reinstall/uninstall-reinstall/topology-switch.
