#!/usr/bin/env bats
# Regression tests for GitHub workflow and Dependabot metadata.

load '../test_helper'

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

workflow_has_job_timeout() {
  local workflow="${1}"
  local job="${2}"
  local expected_timeout="${3}"

  awk -v job="${job}" -v expected_timeout="${expected_timeout}" '
    $0 ~ "^  " job ":" {
      in_job = 1
      next
    }

    in_job && $0 ~ "^  [A-Za-z0-9_-]+:" {
      in_job = 0
    }

    in_job && $0 ~ "^    timeout-minutes:[[:space:]]*" expected_timeout "$" {
      found = 1
    }

    END {
      exit(found ? 0 : 1)
    }
  ' "${workflow}"
}

@test "workflow jobs define explicit timeout-minutes" {
  local workflow="${PROJECT_ROOT}/.github/workflows/test.yml"

  for spec in \
    "lint:5" \
    "format-check:5" \
    "unit-tests:15" \
    "integration-tests:20" \
    "coverage:30" \
    "security-scan:5" \
    "workflow-summary:5"; do
    IFS=':' read -r job timeout <<< "${spec}"
    if ! workflow_has_job_timeout "${workflow}" "${job}" "${timeout}"; then
      echo "missing timeout-minutes=${timeout} for job=${job}" >&2
      return 1
    fi
  done
}

@test "dependabot github-actions updates include commit metadata and assignment" {
  local dependabot="${PROJECT_ROOT}/.github/dependabot.yml"

  run grep -F 'commit-message:' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F 'prefix: "ci"' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F 'include: "scope"' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F 'assignees:' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F '  - "xrf9268-hue"' "${dependabot}"
  [ "${status}" -eq 0 ]
}

@test "dependabot github-actions group declares major minor patch update-types" {
  local dependabot="${PROJECT_ROOT}/.github/dependabot.yml"

  run grep -F 'update-types:' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F '          - "major"' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F '          - "minor"' "${dependabot}"
  [ "${status}" -eq 0 ]

  run grep -F '          - "patch"' "${dependabot}"
  [ "${status}" -eq 0 ]
}
