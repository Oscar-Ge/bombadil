#!/bin/bash
#SBATCH --job-name=bombadil-shifttab
#SBATCH --clusters=granite
#SBATCH --partition=coe-class-grn
#SBATCH --qos=coe-class-grn
#SBATCH --account=jiangy
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=/uufs/chpc.utah.edu/common/home/u6076945/bombadil/test-logs/%x-%j.out
#SBATCH --error=/uufs/chpc.utah.edu/common/home/u6076945/bombadil/test-logs/%x-%j.err

set -u -o pipefail

BOMBADIL_REPOSITORY=/uufs/chpc.utah.edu/common/home/u6076945/bombadil
BOMBADIL_CARGO_HOME=/scratch/general/vast/u6076945/bombadil-0.6.1-cargo
BOMBADIL_JOB_ROOT=/scratch/local/u6076945/${SLURM_JOB_ID}/bombadil-shifttab
BOMBADIL_SOURCE_DIR=${BOMBADIL_JOB_ROOT}/source
BOMBADIL_TARGET_DIR=${BOMBADIL_JOB_ROOT}/target
BOMBADIL_RESULT_DIR=${BOMBADIL_REPOSITORY}/test-logs/${SLURM_JOB_ID}
BOMBADIL_CHROME_SOURCE=/uufs/chpc.utah.edu/common/home/u6076945/.cache/puppeteer/chrome/linux-145.0.7632.77/chrome-linux64
BOMBADIL_CHROME_DIR=${BOMBADIL_JOB_ROOT}/chrome-linux64
BOMBADIL_CARGO=/usr/bin/cargo
BOMBADIL_RUSTC=/usr/bin/rustc

mkdir -p "${BOMBADIL_SOURCE_DIR}" "${BOMBADIL_TARGET_DIR}" "${BOMBADIL_RESULT_DIR}"
cp -a "${BOMBADIL_REPOSITORY}/." "${BOMBADIL_SOURCE_DIR}/"
cp -a "${BOMBADIL_CHROME_SOURCE}" "${BOMBADIL_CHROME_DIR}"

export CARGO_HOME=${BOMBADIL_CARGO_HOME}
export CARGO_TARGET_DIR=${BOMBADIL_TARGET_DIR}
export CARGO_NET_OFFLINE=true
export CARGO_REGISTRIES_CRATES_IO_PROTOCOL=git
export CARGO_BUILD_JOBS=${SLURM_CPUS_PER_TASK}
export RUSTC=${BOMBADIL_RUSTC}
export CHROME=${BOMBADIL_CHROME_DIR}/chrome
export TMPDIR=${BOMBADIL_JOB_ROOT}/tmp
mkdir -p "${TMPDIR}"

cd "${BOMBADIL_SOURCE_DIR}"

git diff --binary > "${BOMBADIL_RESULT_DIR}/pre-clippy.patch"

BOMBADIL_OVERALL_STATUS=0

run_step() {
  local step_name=$1
  shift
  printf 'RUN %s\n' "${step_name}"
  "$@"
  local step_status=$?
  printf 'RESULT %s %s\n' "${step_name}" "${step_status}"
  if [[ ${step_status} -ne 0 ]]; then
    BOMBADIL_OVERALL_STATUS=1
  fi
}

run_nonblocking_step() {
  local step_name=$1
  shift
  printf 'RUN %s (non-blocking)\n' "${step_name}"
  "$@"
  local step_status=$?
  printf 'RESULT %s %s (non-blocking)\n' \
    "${step_name}" "${step_status}"
}

run_step rustc-version "${BOMBADIL_RUSTC}" --version
run_step cargo-version "${BOMBADIL_CARGO}" --version
run_step chrome-linkage ldd "${CHROME}"
run_step relevant-workspace-build \
  "${BOMBADIL_CARGO}" build --offline --workspace \
    --exclude bombadil-inspect \
    --exclude bombadil-terminal \
    --exclude bombadil-cli
run_step relevant-workspace-clippy \
  "${BOMBADIL_CARGO}" clippy --offline --workspace \
    --exclude bombadil-inspect \
    --exclude bombadil-terminal \
    --exclude bombadil-cli \
    --all-targets --fix --allow-dirty -- -D warnings
run_step rust-format "${BOMBADIL_CARGO}" fmt --all -- --check
# v0.6.1 uses unstable slice::array_windows in the unchanged Inspect timeline.
# Inject only that upstream feature for this validation so the modified action
# renderer is type-checked even though CHPC has no Nix/nightly toolchain.
run_nonblocking_step inspect-check-with-array-windows \
  env RUSTC_BOOTSTRAP=1 RUSTFLAGS="-Zcrate-attr=feature(array_windows)" \
    "${BOMBADIL_CARGO}" check --offline -p bombadil-inspect
run_step schema-unit-tests \
  "${BOMBADIL_CARGO}" test --offline -p bombadil-schema --lib
run_step browser-unit-tests \
  "${BOMBADIL_CARGO}" test --offline -p bombadil-browser --lib
run_step shift-tab-integration \
  "${BOMBADIL_CARGO}" test --offline \
    -p bombadil-browser-integration-tests \
    test_shift_tab -- --exact --nocapture

git diff --binary > "${BOMBADIL_RESULT_DIR}/post-clippy.patch"
git status --short > "${BOMBADIL_RESULT_DIR}/git-status.txt"
printf '%s\n' "${BOMBADIL_OVERALL_STATUS}" \
  > "${BOMBADIL_RESULT_DIR}/exit-code.txt"

exit "${BOMBADIL_OVERALL_STATUS}"
