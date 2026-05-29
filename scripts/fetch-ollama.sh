#!/usr/bin/env bash
# fetch-ollama.sh — downloads the pinned Ollama server binary and places it
# at src-tauri/binaries/ollama-aarch64-apple-darwin (Tauri sidecar naming).
#
# Per spec 002 research.md R-001. Version pin and SHA-256 hash are deliberate
# supply-chain integrity controls. Spec 006 (signing-and-ci) will re-sign
# under the JuraDrop Developer ID.

set -euo pipefail

# Pinned version. Bump deliberately when upgrading; re-pin the hash too.
# Bumped from v0.5.4 → v0.24.0 because v0.5.4 cannot pull gemma3:* (the
# manifest endpoint returns 412 "requires a newer version of Ollama").
# Previous SHA-256 for v0.5.4 was
# 2424d20363d1b0c7249fef40af3561c61101b1129ed7f22ba408deee0f12227f.
OLLAMA_VERSION="v0.24.0"
OLLAMA_ZIP_URL="https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/Ollama-darwin.zip"

# Pinned SHA-256 of the downloaded zip. Set to empty on first run; the script
# will print the observed hash so you can paste it here and commit.
EXPECTED_SHA256="8073624ec7986f9259f14a1234f5a5818f6285767f08b18cd0fbb4d1136599b1"

# Paths
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARIES_DIR="${REPO_ROOT}/src-tauri/binaries"
# Tauri sidecar naming: one file per target triple. The release build runs
# `tauri build --target universal-apple-darwin`, which lipo-combines a
# per-arch binary for EACH slice, so BOTH names must exist as real files.
ARM_BINARY="${BINARIES_DIR}/ollama-aarch64-apple-darwin"
X86_BINARY="${BINARIES_DIR}/ollama-x86_64-apple-darwin"
# The universal-target BUNDLE step resolves the `universal-apple-darwin`
# triple and needs the fat binary under this name too (the per-arch compile
# sub-builds use the thin slices above).
UNIVERSAL_BINARY="${BINARIES_DIR}/ollama-universal-apple-darwin"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${BINARIES_DIR}"

echo "[fetch-ollama] downloading ${OLLAMA_VERSION} from ${OLLAMA_ZIP_URL}"
curl -fL --proto '=https' --tlsv1.2 -o "${WORK_DIR}/Ollama-darwin.zip" "${OLLAMA_ZIP_URL}"

OBSERVED_SHA256="$(shasum -a 256 "${WORK_DIR}/Ollama-darwin.zip" | awk '{print $1}')"
echo "[fetch-ollama] observed SHA-256: ${OBSERVED_SHA256}"

if [[ -z "${EXPECTED_SHA256}" ]]; then
    echo "[fetch-ollama] WARNING: EXPECTED_SHA256 is empty. Paste the observed hash above into scripts/fetch-ollama.sh and re-run."
    echo "[fetch-ollama] continuing this run (supply-chain check effectively disabled until hash is pinned)"
elif [[ "${OBSERVED_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    echo "[fetch-ollama] FATAL: SHA-256 mismatch."
    echo "[fetch-ollama]   expected: ${EXPECTED_SHA256}"
    echo "[fetch-ollama]   observed: ${OBSERVED_SHA256}"
    echo "[fetch-ollama] Refusing to install. Investigate the discrepancy before re-running."
    exit 2
fi

echo "[fetch-ollama] extracting"
unzip -q "${WORK_DIR}/Ollama-darwin.zip" -d "${WORK_DIR}/extracted"

# The Ollama .app bundle layout has the server binary at one of two known
# locations depending on the upstream release. Try both.
CANDIDATE_PATHS=(
    "${WORK_DIR}/extracted/Ollama.app/Contents/Resources/ollama"
    "${WORK_DIR}/extracted/Ollama.app/Contents/MacOS/ollama"
    "${WORK_DIR}/extracted/Ollama.app/Contents/Resources/ollama-darwin"
)

SOURCE_BINARY=""
for candidate in "${CANDIDATE_PATHS[@]}"; do
    if [[ -f "${candidate}" ]]; then
        SOURCE_BINARY="${candidate}"
        break
    fi
done

if [[ -z "${SOURCE_BINARY}" ]]; then
    echo "[fetch-ollama] FATAL: could not locate the ollama binary inside Ollama.app. Inspect ${WORK_DIR}/extracted manually."
    ls -la "${WORK_DIR}/extracted/Ollama.app/Contents/" || true
    exit 3
fi

# Upstream ships a UNIVERSAL (fat) Mach-O. `tauri build --target
# universal-apple-darwin` lipo-combines a per-triple binary for each arch, so
# feeding it two universal copies makes `lipo -create` choke on duplicate
# architectures. Thin the fat binary into one arm64 slice and one x86_64
# slice under the Tauri sidecar names instead.
SOURCE_ARCHS="$(lipo -archs "${SOURCE_BINARY}" 2>/dev/null || echo "")"
echo "[fetch-ollama] source archs: ${SOURCE_ARCHS:-<thin/unknown>}"

# The fat binary itself is the universal sidecar the bundle step copies.
cp "${SOURCE_BINARY}" "${UNIVERSAL_BINARY}"

if [[ "${SOURCE_ARCHS}" == *"arm64"* && "${SOURCE_ARCHS}" == *"x86_64"* ]]; then
    echo "[fetch-ollama] thinning universal binary -> arm64 + x86_64 sidecars"
    lipo "${SOURCE_BINARY}" -thin arm64  -output "${ARM_BINARY}"
    lipo "${SOURCE_BINARY}" -thin x86_64 -output "${X86_BINARY}"
else
    # Upstream shipped a thin binary (unexpected). Place it under both arch
    # names so each per-arch sub-build still resolves its slice.
    echo "[fetch-ollama] WARNING: source is not universal — copying as-is to both arch names"
    cp "${SOURCE_BINARY}" "${ARM_BINARY}"
    cp "${SOURCE_BINARY}" "${X86_BINARY}"
fi

chmod +x "${ARM_BINARY}" "${X86_BINARY}" "${UNIVERSAL_BINARY}"

# Strip macOS quarantine attribute so dev runs don't trip Gatekeeper.
xattr -d com.apple.quarantine "${ARM_BINARY}" 2>/dev/null || true
xattr -d com.apple.quarantine "${X86_BINARY}" 2>/dev/null || true
xattr -d com.apple.quarantine "${UNIVERSAL_BINARY}" 2>/dev/null || true

echo "[fetch-ollama] done."
echo "  arm64    : ${ARM_BINARY} ($(stat -f '%z' "${ARM_BINARY}") bytes, archs: $(lipo -archs "${ARM_BINARY}"))"
echo "  x86_64   : ${X86_BINARY} ($(stat -f '%z' "${X86_BINARY}") bytes, archs: $(lipo -archs "${X86_BINARY}"))"
echo "  universal: ${UNIVERSAL_BINARY} ($(stat -f '%z' "${UNIVERSAL_BINARY}") bytes, archs: $(lipo -archs "${UNIVERSAL_BINARY}"))"
