#!/usr/bin/env bash
# ==============================================================================
# Turnback Endurance Tracker - Developer Onboarding & Environment Setup
# ==============================================================================
# Written with defensive shell script patterns. Safe to run.
# Supported Shells: bash, zsh
# Target OS: Linux (Linux Mint / Debian-based systems)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Color constants for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;37m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Cleanup hook on failure
cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        log_error "Setup script failed. Review errors above."
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# 1. Dependency Checks
# ------------------------------------------------------------------------------
log_info "Checking system pre-requisites..."

# Check Git
if ! command -v git &>/dev/null; then
    log_error "Git is not installed. Please install it using: sudo apt install git"
    exit 1
fi
log_success "Git verified."

# Check standard Linux dependencies for Flutter engine compilation
log_info "Checking essential compilation libraries..."
MISSING_LIBS=()
for lib in clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev; do
    if ! dpkg -s "$lib" &>/dev/null; then
        MISSING_LIBS+=("$lib")
    fi
done

if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
    log_warning "Missing required compilation packages: ${MISSING_LIBS[*]}"
    log_info "Attempting to install missing libraries. System password may be required."
    sudo apt update
    sudo apt install -y "${MISSING_LIBS[@]}"
else
    log_success "All native compilation libraries verified."
fi

# ------------------------------------------------------------------------------
# 2. Flutter SDK Installation / Detection
# ------------------------------------------------------------------------------
FLUTTER_INSTALL_DIR="$HOME/development/flutter"
FLUTTER_BIN="$FLUTTER_INSTALL_DIR/bin/flutter"

if command -v flutter &>/dev/null; then
    log_success "Flutter is already installed on the system PATH."
    FLUTTER_CMD="flutter"
elif [ -f "$FLUTTER_BIN" ]; then
    log_success "Flutter SDK detected at $FLUTTER_INSTALL_DIR."
    FLUTTER_CMD="$FLUTTER_BIN"
else
    log_info "Flutter SDK not found on system."
    log_info "Cloning stable Flutter branch into: $FLUTTER_INSTALL_DIR"
    mkdir -p "$HOME/development"
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_INSTALL_DIR"
    FLUTTER_CMD="$FLUTTER_BIN"
    log_success "Flutter SDK cloned successfully."
fi

# ------------------------------------------------------------------------------
# 3. Shell Path Injection
# ------------------------------------------------------------------------------
export_line="export PATH=\"\$PATH:$FLUTTER_INSTALL_DIR/bin\""

configure_shell() {
    local rc_file="$1"
    if [ -f "$rc_file" ]; then
        if ! grep -q "development/flutter/bin" "$rc_file"; then
            log_info "Injecting Flutter path exports to $rc_file"
            echo "" >> "$rc_file"
            echo "# Flutter SDK path configuration" >> "$rc_file"
            echo "$export_line" >> "$rc_file"
            log_success "Updated $rc_file. Please run 'source $rc_file' to load in current terminal."
        else
            log_success "Flutter path already configured in $rc_file"
        fi
    fi
}

configure_shell "$HOME/.bashrc"
configure_shell "$HOME/.zshrc"

# ------------------------------------------------------------------------------
# 4. Generate local.properties for Android Build Configuration
# ------------------------------------------------------------------------------
if [ -d "android" ]; then
    log_info "Setting up android/local.properties..."
    
    # Try to locate Android SDK
    ANDROID_SDK_PATH=""
    if [ -d "$HOME/Android/Sdk" ]; then
        ANDROID_SDK_PATH="$HOME/Android/Sdk"
    elif [ -d "$HOME/development/Android/Sdk" ]; then
        ANDROID_SDK_PATH="$HOME/development/Android/Sdk"
    elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
        ANDROID_SDK_PATH="$ANDROID_SDK_ROOT"
    elif [ -n "${ANDROID_HOME:-}" ]; then
        ANDROID_SDK_PATH="$ANDROID_HOME"
    fi

    if [ -z "$ANDROID_SDK_PATH" ]; then
        log_warning "Android SDK path could not be auto-detected."
        log_warning "Defaulting SDK path to: $HOME/Android/Sdk"
        ANDROID_SDK_PATH="$HOME/Android/Sdk"
    else
        log_success "Android SDK located at: $ANDROID_SDK_PATH"
    fi

    # Write configs to file
    LOCAL_PROP="android/local.properties"
    cat <<EOF > "$LOCAL_PROP"
# Generated automatically by Turnback onboarding setup.
sdk.dir=$ANDROID_SDK_PATH
flutter.sdk=$FLUTTER_INSTALL_DIR
EOF
    log_success "Generated $LOCAL_PROP"
fi

# ------------------------------------------------------------------------------
# 5. Fetch Workspace Packages
# ------------------------------------------------------------------------------
log_info "Running package resolutions..."
"$FLUTTER_CMD" pub get
log_success "Dependencies successfully fetched and locked."

# ------------------------------------------------------------------------------
# 6. Verify and Run Doctor
# ------------------------------------------------------------------------------
log_info "Running Flutter diagnostic checks..."
"$FLUTTER_CMD" doctor -v

echo -e "\n=============================================================================="
log_success "ONBOARDING COMPLETE!"
echo -e "To proceed with testing and compilation, please reload your shell or run:"
echo -e "  source ~/.zshrc    (or source ~/.bashrc depending on active shell)"
echo -e "Then run tests:"
echo -e "  flutter test test/turnback_math_test.dart"
echo -e "=============================================================================="
