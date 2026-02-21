#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "bootstrap help works" {
  run "${REPO_ROOT}/bootstrap.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./bootstrap.sh [OPTIONS]"* ]]
}

@test "bootstrap dry-run works" {
  run "${REPO_ROOT}/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Setting up environment..."* ]]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "toolchain help works" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./install/install-toolchain.sh [OPTIONS]"* ]]
}

@test "toolchain invalid option fails" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --bad-option
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bad-option"* ]]
}

@test "toolchain dry-run works in non-amzn environments" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --dry-run --no-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run     : enabled"* ]]
}

@test "dev-utils help works" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./install/install-dev-utils.sh [OPTIONS]"* ]]
}

@test "dev-utils invalid option fails" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --bad-option
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bad-option"* ]]
}

@test "dev-utils dry-run works in non-amzn environments" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --dry-run --no-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run : enabled"* ]]
}
