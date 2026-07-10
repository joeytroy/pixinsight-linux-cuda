#!/usr/bin/env bash
#
# setup-cuda-pixinsight.sh
# -----------------------------------------------------------------------------
# Automates GPU (CUDA) acceleration for PixInsight + RC Astro tools on
# Kubuntu / Ubuntu 24.04 LTS and 26.04 LTS.
#
# What it does (everything EXCEPT downloading/installing Kubuntu itself):
#   1. apt update && upgrade
#   2. Install build-essential (GCC)
#   3. Install the recommended NVIDIA driver         [requires a reboot]
#   4. Install the CUDA 12.8 toolkit
#   5. Configure environment (PATH / LD_LIBRARY_PATH / ldconfig)
#   6. Install cuDNN 8.9.7          (you must download the .deb first — gated)
#   7. Install TensorFlow 2.15.0 C libraries
#   8. Install PixInsight           (you must download the tarball — gated)
#   9. Configure PixInsight to use the system TensorFlow (CUDA-enabled)
#
# The script is RESUMABLE. It records completed steps in a state file and
# stops for the required reboot after the NVIDIA driver install. Just run it
# again after rebooting and it continues where it left off.
#
# Usage:
#   chmod +x setup-cuda-pixinsight.sh
#   ./setup-cuda-pixinsight.sh                 # run / resume the full process
#   ./setup-cuda-pixinsight.sh --status        # show which steps are done
#   ./setup-cuda-pixinsight.sh --verify        # check the GPU stack is working
#   ./setup-cuda-pixinsight.sh --repair-driver # purge & reinstall NVIDIA driver
#   ./setup-cuda-pixinsight.sh --reset         # forget saved state (start over)
#
# Optional: point the script at your gated downloads instead of ~/Downloads
#   CUDNN_DEB=/path/to/cudnn-local-repo-*.deb \
#   PIXINSIGHT_TARBALL=/path/to/PI-linux-x64-*.tar.xz \
#   ./setup-cuda-pixinsight.sh
#
# Run as your normal user (NOT with sudo). The script calls sudo itself where
# it needs root, and edits your own ~/.bashrc.
# -----------------------------------------------------------------------------

set -euo pipefail

# ----------------------------- Configuration ---------------------------------
# Bump these when NVIDIA/PixInsight/TensorFlow publish newer compatible builds.
UBUNTU_REPO="ubuntu2404"                 # CUDA repo flavor (24.04 debs work on 26.04)
CUDA_VERSION="12.8.1"                    # CUDA toolkit version
CUDA_PIN_DRIVER="570.124.06"             # driver bundled in the local-installer deb
CUDA_DASH="12-8"                         # apt package suffix (cuda-toolkit-12-8)
TF_VERSION="2.15.0"                      # TensorFlow C-library version (matches CUDA 12.x)
CUDNN_VERSION="8.9.7.29"                 # cuDNN version (Ubuntu 22.04 debs, compatible)

DOWNLOADS="${HOME}/Downloads"
STATE_FILE="${HOME}/.pixinsight-cuda-setup.state"
BASHRC="${HOME}/.bashrc"

# User-provided (login-gated) downloads. Auto-discovered from ~/Downloads if unset.
CUDNN_DEB="${CUDNN_DEB:-}"
PIXINSIGHT_TARBALL="${PIXINSIGHT_TARBALL:-}"

# ----------------------------- Pretty output ---------------------------------
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
    BOLD=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; RESET=''
fi
info()  { echo "${BLUE}${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }
ok()    { echo "${GREEN}  ✔ $*${RESET}"; }
warn()  { echo "${YELLOW}  ! $*${RESET}"; }
die()   { echo "${RED}${BOLD}  ✘ $*${RESET}" >&2; exit 1; }

# ----------------------------- State helpers ---------------------------------
touch "$STATE_FILE"
is_done()   { grep -qxF "$1" "$STATE_FILE"; }
mark_done() { is_done "$1" || echo "$1" >> "$STATE_FILE"; }

# Run a named step only if it hasn't completed before.
step() {
    local name="$1"; shift
    if is_done "$name"; then
        ok "[$name] already done — skipping"
        return 0
    fi
    "$@"
    mark_done "$name"
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    local prompt="${1:-Continue?}"
    read -r -p "${YELLOW}${prompt} [y/N] ${RESET}" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# Auto-discover a file in ~/Downloads matching a glob, newest first.
find_download() {
    local pattern="$1"
    # shellcheck disable=SC2012
    ls -t ${DOWNLOADS}/${pattern} 2>/dev/null | head -n1 || true
}

# ----------------------------- Pre-flight ------------------------------------
preflight() {
    [[ $EUID -ne 0 ]] || die "Do not run this script with sudo. Run it as your normal user."
    need_cmd apt-get || die "This script requires an apt-based distro (Kubuntu/Ubuntu)."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        die "This guide/script targets x86_64. Detected: $(uname -m)."
    fi
    if need_cmd lsb_release; then
        local ver; ver="$(lsb_release -rs || true)"
        case "$ver" in
            24.04|26.04) info "Detected Ubuntu/Kubuntu $ver" ;;
            *) warn "Untested Ubuntu version '$ver' — proceeding, but 24.04/26.04 are supported." ;;
        esac
    fi
    mkdir -p "$DOWNLOADS"
}

# ----------------------------- Steps -----------------------------------------
do_system_update() {
    info "Updating and upgrading the system (apt update && upgrade)"
    sudo apt-get update
    sudo apt-get -y upgrade
}

do_build_essential() {
    info "Installing the GCC toolchain (build-essential)"
    sudo apt-get install -y build-essential
}

do_nvidia_driver() {
    info "Installing the recommended NVIDIA driver (ubuntu-drivers install)"
    sudo apt-get install -y ubuntu-drivers-common
    sudo ubuntu-drivers install
    mark_done nvidia_driver
    echo
    warn "The NVIDIA driver was installed. A REBOOT is required now."
    warn "After rebooting, run this script again to continue:"
    echo  "    ${BOLD}$0${RESET}"
    echo
    if confirm "Reboot now?"; then
        sudo reboot
    fi
    exit 0
}

verify_driver_after_reboot() {
    if ! need_cmd nvidia-smi; then
        die "nvidia-smi not found. The driver may not have finished installing — reboot and retry, or run '$0 --repair-driver'."
    fi
    if ! nvidia-smi >/dev/null 2>&1; then
        die "nvidia-smi failed. Try a reboot, or run '$0 --repair-driver'."
    fi
    ok "NVIDIA driver active:"
    nvidia-smi | sed 's/^/      /'
}

do_cuda_toolkit() {
    info "Installing the CUDA ${CUDA_VERSION} toolkit"
    local pin="cuda-${UBUNTU_REPO}.pin"
    local deb="cuda-repo-${UBUNTU_REPO}-${CUDA_DASH}-local_${CUDA_VERSION}-${CUDA_PIN_DRIVER}-1_amd64.deb"
    local base="https://developer.download.nvidia.com/compute/cuda"

    cd "$DOWNLOADS" || die "Cannot cd into $DOWNLOADS"
    info "Fetching repository pin"
    wget -q --show-progress -O "$pin" "${base}/repos/${UBUNTU_REPO}/x86_64/${pin}"
    sudo mv "$pin" /etc/apt/preferences.d/cuda-repository-pin-600

    info "Fetching CUDA local-installer package (~3 GB, this can take a while)"
    wget -q --show-progress -O "$deb" "${base}/${CUDA_VERSION}/local_installers/${deb}"

    sudo dpkg -i "$deb"
    sudo cp /var/cuda-repo-${UBUNTU_REPO}-${CUDA_DASH}-local/cuda-*-keyring.gpg /usr/share/keyrings/
    sudo apt-get update
    sudo apt-get -y install "cuda-toolkit-${CUDA_DASH}"
    ok "CUDA toolkit installed under /usr/local/cuda-${CUDA_DASH/-/./}"
}

append_bashrc_once() {
    # append_bashrc_once <marker-substring> <line>
    local marker="$1" line="$2"
    if grep -qF "$marker" "$BASHRC" 2>/dev/null; then
        ok "Already in ~/.bashrc: $marker"
    else
        printf '%s\n' "$line" >> "$BASHRC"
        ok "Added to ~/.bashrc: $line"
    fi
}

do_env_config() {
    info "Configuring CUDA environment variables and linker paths"
    # Keep a header so the block is easy to find later.
    grep -qF "# >>> PixInsight CUDA setup >>>" "$BASHRC" 2>/dev/null || \
        printf '\n# >>> PixInsight CUDA setup >>>\n' >> "$BASHRC"

    append_bashrc_once 'cuda/bin' 'export PATH="/usr/local/cuda/bin:$PATH"'
    append_bashrc_once 'cuda/lib64' 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"'
    # TF_FORCE_GPU_ALLOW_GROWTH keeps PixInsight from grabbing all VRAM up front.
    append_bashrc_once 'TF_FORCE_GPU_ALLOW_GROWTH' 'export TF_FORCE_GPU_ALLOW_GROWTH="true"'

    grep -qF "# <<< PixInsight CUDA setup <<<" "$BASHRC" 2>/dev/null || \
        printf '# <<< PixInsight CUDA setup <<<\n' >> "$BASHRC"

    # Register the CUDA libs system-wide for the dynamic linker.
    if ! grep -qxF '/usr/local/cuda/lib64' /etc/ld.so.conf 2>/dev/null; then
        echo "/usr/local/cuda/lib64" | sudo tee -a /etc/ld.so.conf >/dev/null
    fi
    sudo ldconfig
    ok "Environment configured. (Open a new terminal, or run 'source ~/.bashrc'.)"
}

resolve_cudnn_deb() {
    [[ -n "$CUDNN_DEB" ]] && { echo "$CUDNN_DEB"; return; }
    local f
    f="$(find_download "cudnn*.deb")"
    echo "$f"
}

do_cudnn() {
    info "Installing cuDNN ${CUDNN_VERSION}"
    local deb; deb="$(resolve_cudnn_deb)"
    if [[ -z "$deb" || ! -f "$deb" ]]; then
        warn "cuDNN download not found."
        cat <<EOF
${BOLD}cuDNN must be downloaded manually${RESET} — it is behind the NVIDIA Developer login.

  1. Sign in / join the NVIDIA Developer Program:  https://developer.nvidia.com/cudnn
     (You will need an authenticator app for 2FA.)
  2. Open the cuDNN archive:  https://developer.nvidia.com/rdp/cudnn-archive
  3. Choose "Download cuDNN v8.9.7 (December 5th, 2023) for CUDA 12.x"
  4. Choose "Local Installer for Ubuntu22.04 x86_64 (Deb)"
     File: cudnn-local-repo-ubuntu2204-${CUDNN_VERSION}_1.0-1_amd64.deb
  5. Save it into ${DOWNLOADS}/ and re-run this script, OR run:
     CUDNN_DEB=/path/to/that.deb $0
EOF
        die "cuDNN .deb not found — see instructions above."
    fi

    info "Using cuDNN package: $deb"
    local work="${DOWNLOADS}/cudnn_install"
    rm -rf "$work"; mkdir -p "$work"
    cp "$deb" "$work/cudnn.deb"
    cd "$work" || die "Cannot cd into $work"

    # The local-repo .deb is an ar archive; unpack it to get the inner libcudnn debs.
    ar -x cudnn.deb
    tar -xf data.tar.xz

    local pkgdir
    pkgdir="$(find "$work" -type d -name 'cudnn-local-repo-*' | head -n1)"
    [[ -n "$pkgdir" ]] || die "Could not find extracted cudnn-local-repo directory."

    local runtime dev samples
    runtime="$(ls "$pkgdir"/libcudnn8_*.deb 2>/dev/null | head -n1 || true)"
    dev="$(ls "$pkgdir"/libcudnn8-dev_*.deb 2>/dev/null | head -n1 || true)"
    samples="$(ls "$pkgdir"/libcudnn8-samples_*.deb 2>/dev/null | head -n1 || true)"
    [[ -n "$runtime" && -n "$dev" ]] || die "Expected libcudnn8 .deb files not found in $pkgdir."

    sudo dpkg -i "$runtime"
    sudo dpkg -i "$dev"
    [[ -n "$samples" ]] && sudo dpkg -i "$samples" || warn "samples package not found (optional) — skipping"
    sudo ldconfig
    ok "cuDNN installed into /usr/lib/x86_64-linux-gnu/"
}

do_tensorflow() {
    info "Installing TensorFlow ${TF_VERSION} C libraries"
    local tarball="libtensorflow-gpu-linux-x86_64-${TF_VERSION}.tar.gz"
    cd "$DOWNLOADS" || die "Cannot cd into $DOWNLOADS"
    if [[ ! -f "$tarball" ]]; then
        info "Downloading $tarball"
        wget -q --show-progress -O "$tarball" \
            "https://storage.googleapis.com/tensorflow/libtensorflow/${tarball}"
    else
        ok "Already downloaded: $tarball"
    fi
    sudo tar -C /usr/local -xzf "$tarball"
    sudo ldconfig /usr/local/lib
    ok "TensorFlow libraries installed into /usr/local/lib"
}

resolve_pixinsight_tarball() {
    [[ -n "$PIXINSIGHT_TARBALL" ]] && { echo "$PIXINSIGHT_TARBALL"; return; }
    find_download "PI-linux-x64-*.tar.xz"
}

do_pixinsight_install() {
    info "Installing PixInsight for Linux"
    local tarball; tarball="$(resolve_pixinsight_tarball)"
    if [[ -z "$tarball" || ! -f "$tarball" ]]; then
        warn "PixInsight download not found."
        cat <<EOF
${BOLD}PixInsight must be downloaded manually${RESET} — it requires your licensed account.

  1. Go to:  https://pixinsight.com/downloads/index.html
  2. Software Distribution -> Linux version -> download the tarball
     (e.g. PI-linux-x64-1.9.4-YYYYMMDD-c.tar.xz)
  3. Save it into ${DOWNLOADS}/ and re-run this script, OR run:
     PIXINSIGHT_TARBALL=/path/to/PI-linux-x64-*.tar.xz $0
EOF
        die "PixInsight tarball not found — see instructions above."
    fi

    info "Using PixInsight package: $tarball"
    local work="${DOWNLOADS}/pixinsight_install"
    rm -rf "$work"; mkdir -p "$work"
    tar -xf "$tarball" -C "$work"
    local installer
    installer="$(find "$work" -maxdepth 2 -type f -name installer | head -n1)"
    [[ -n "$installer" ]] || die "Could not find the PixInsight 'installer' inside the tarball."
    info "Launching the PixInsight installer (follow its prompts)"
    ( cd "$(dirname "$installer")" && sudo ./installer )
    ok "PixInsight installed."
}

do_pixinsight_config() {
    info "Configuring PixInsight to use the CUDA-enabled system TensorFlow"
    if [[ ! -d /opt/PixInsight/bin/lib ]]; then
        die "/opt/PixInsight/bin/lib not found — did the PixInsight install finish?"
    fi
    # PixInsight ships its own (CPU/older) TensorFlow. Removing it makes PI fall
    # back to the CUDA-enabled TF 2.15.0 we installed in /usr/local/lib.
    if compgen -G "/opt/PixInsight/bin/lib/libtensorflow*" >/dev/null; then
        sudo rm -f /opt/PixInsight/bin/lib/libtensorflow*
        ok "Removed PixInsight's bundled TensorFlow libraries."
    else
        ok "No bundled TensorFlow libraries present (already removed)."
    fi
    ok "PixInsight will now use TensorFlow ${TF_VERSION} from /usr/local/lib (CUDA-enabled)."
}

# ----------------------------- Special modes ---------------------------------
show_status() {
    info "Setup progress (state file: $STATE_FILE)"
    local steps=(system_update build_essential nvidia_driver cuda_toolkit \
                 env_config cudnn tensorflow pixinsight pixinsight_config)
    for s in "${steps[@]}"; do
        if is_done "$s"; then echo "  ${GREEN}✔${RESET} $s"; else echo "  ${YELLOW}·${RESET} $s"; fi
    done
}

verify_stack() {
    info "Verifying the GPU / CUDA / TensorFlow stack"
    local fail=0
    if need_cmd nvidia-smi && nvidia-smi >/dev/null 2>&1; then
        ok "NVIDIA driver OK"; nvidia-smi | sed 's/^/      /'
    else
        warn "nvidia-smi not working"; fail=1
    fi
    if need_cmd nvcc; then
        ok "nvcc: $(nvcc --version | grep -oE 'release [0-9.]+' || echo present)"
    elif [[ -x /usr/local/cuda/bin/nvcc ]]; then
        ok "nvcc present at /usr/local/cuda/bin (run 'source ~/.bashrc' to add to PATH)"
    else
        warn "nvcc not found — CUDA toolkit may be missing"; fail=1
    fi
    if compgen -G "/usr/lib/x86_64-linux-gnu/libcudnn.so*" >/dev/null; then
        ok "cuDNN libraries present"
    else
        warn "cuDNN libraries not found"; fail=1
    fi
    if compgen -G "/usr/local/lib/libtensorflow.so*" >/dev/null; then
        ok "TensorFlow ${TF_VERSION} libraries present"
    else
        warn "TensorFlow libraries not found in /usr/local/lib"; fail=1
    fi
    if [[ -d /opt/PixInsight/bin/lib ]]; then
        if compgen -G "/opt/PixInsight/bin/lib/libtensorflow*" >/dev/null; then
            warn "PixInsight still has bundled TensorFlow — run: $0  (or) sudo rm /opt/PixInsight/bin/lib/libtensorflow*"
            fail=1
        else
            ok "PixInsight is set to use the system TensorFlow"
        fi
    else
        warn "PixInsight not installed yet"
    fi
    if [[ $fail -eq 0 ]]; then
        echo; ok "${BOLD}All checks passed. GPU acceleration should be active in PixInsight.${RESET}"
    else
        echo; warn "Some checks failed — see messages above."
    fi
    return $fail
}

repair_driver() {
    info "Repairing the NVIDIA driver (purge + reinstall)"
    warn "This removes all NVIDIA packages and reinstalls the recommended driver."
    confirm "Proceed?" || die "Aborted."
    sudo apt-get purge -y 'nvidia*' || true
    sudo apt-get autoremove -y
    sudo apt-get autoclean
    sudo apt-get update
    sudo ubuntu-drivers install
    warn "Reboot required. After reboot, run: nvidia-smi"
    confirm "Reboot now?" && sudo reboot
}

# ----------------------------- Main ------------------------------------------
main() {
    preflight
    info "PixInsight CUDA setup — starting/resuming"
    echo "  State file: $STATE_FILE"
    echo "  (Steps already completed are skipped automatically.)"
    echo

    step system_update    do_system_update
    step build_essential  do_build_essential

    # NVIDIA driver install ends the run with a reboot the first time through.
    if ! is_done nvidia_driver; then
        do_nvidia_driver   # marks done + exits for reboot
    else
        ok "[nvidia_driver] already done — verifying it survived the reboot"
        verify_driver_after_reboot
    fi

    step cuda_toolkit      do_cuda_toolkit
    step env_config        do_env_config
    step cudnn             do_cudnn
    step tensorflow        do_tensorflow
    step pixinsight        do_pixinsight_install
    step pixinsight_config do_pixinsight_config

    echo
    ok "${BOLD}Done!${RESET} Open a NEW terminal (or 'source ~/.bashrc'), then start PixInsight."
    ok "Install the RC Astro tools inside PixInsight to test CUDA acceleration."
    echo
    verify_stack || true
}

case "${1:-}" in
    ""|--run)          main ;;
    --status)          show_status ;;
    --verify)          verify_stack ;;
    --repair-driver)   repair_driver ;;
    --reset)           rm -f "$STATE_FILE"; ok "State reset. Next run starts from the beginning." ;;
    -h|--help)
        sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "Unknown option: $1  (try --help)" ;;
esac
