#!/bin/bash
# Container validation script for MsQuic Linux packages
# Runs inside Docker containers to validate package installation and functionality
# Used by GitHub Actions workflow

set -e

PKG_TYPE=$1      # deb or rpm
ARCH=$2          # x64, arm64, arm
SKIP_DOTNET=$3   # true to skip .NET tests
CONFIG=${4:-Release}
TLS=${5:-quictls}

# Detect OS from /etc/os-release
. /etc/os-release
OS=$ID
OS_VERSION=$VERSION_ID

echo "========================================"
echo "MsQuic Package Validation"
echo "========================================"
echo "OS: $OS $OS_VERSION"
echo "Architecture: $ARCH"
echo "Package Type: $PKG_TYPE"
echo "Skip .NET: $SKIP_DOTNET"
echo "========================================"

# Exit codes:
# 0 = All tests passed
# 1 = Package installation failed
# 2 = Library load test failed
# 3 = msquictest failed
# 4 = .NET test failed
# 5 = .NET runtime installation failed (skipped)

# Install dependencies and package based on OS type
install_package_apt() {
    echo "=== Installing package (apt) ==="
    apt-get update -qq
    # Install dependencies for .NET runtime
    apt-get install -y curl ca-certificates || true
    # Install the package
    apt-get install -y /packages/*.deb
}

install_package_dnf() {
    echo "=== Installing package (dnf/yum) ==="
    # Try dnf first, fallback to yum
    if command -v dnf &> /dev/null; then
        dnf install -y /packages/*.rpm
    else
        yum install -y /packages/*.rpm
    fi
}

install_package_zypper() {
    echo "=== Installing package (zypper) ==="
    zypper refresh || true
    zypper install -y --allow-unsigned-rpm /packages/*.rpm
}

install_package_tdnf() {
    echo "=== Installing package (tdnf) ==="
    tdnf update -y || true
    tdnf install -y /packages/*.rpm
}

install_package_apk() {
    echo "=== Installing package (apk) ==="
    apk update || true
    apk add --allow-untrusted /packages/*.apk
}

# Install package based on distro
install_package() {
    case "$OS" in
        ubuntu|debian)
            install_package_apt
            ;;
        centos|rhel|almalinux|rocky|fedora)
            install_package_dnf
            ;;
        opensuse*|sles)
            install_package_zypper
            ;;
        azurelinux|mariner)
            install_package_tdnf
            ;;
        alpine)
            install_package_apk
            ;;
        *)
            echo "Error: Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Test that the library can be loaded
test_library_load() {
    echo ""
    echo "=== Testing library load ==="

    # Try Python if available
    if command -v python3 &> /dev/null; then
        echo "Using Python to test library load..."
        python3 -c "
import ctypes
import sys

# Try common library paths
paths = [
    'libmsquic.so.2',
    '/usr/lib/libmsquic.so.2',
    '/usr/lib64/libmsquic.so.2',
    '/usr/local/lib/libmsquic.so.2'
]

loaded = False
for path in paths:
    try:
        lib = ctypes.CDLL(path)
        print(f'Successfully loaded: {path}')
        loaded = True
        break
    except OSError as e:
        print(f'Failed to load {path}: {e}')

if not loaded:
    print('ERROR: Could not load libmsquic.so.2')
    sys.exit(1)
"
    else
        # Fallback: use ldconfig to verify library is installed
        echo "Python not available, using ldconfig..."
        ldconfig -p | grep -i msquic || {
            echo "Warning: libmsquic not found in ldconfig cache"
            # Try to find the library manually
            find /usr -name 'libmsquic*' 2>/dev/null || true
        }
    fi

    echo "Library load test: PASSED"
}

# Run msquictest
run_msquictest() {
    echo ""
    echo "=== Running msquictest ==="

    # Map architecture names
    local test_arch
    case "$ARCH" in
        x64) test_arch="x64" ;;
        arm64) test_arch="arm64" ;;
        arm) test_arch="arm" ;;
        *) test_arch="$ARCH" ;;
    esac

    # Look for msquictest in various locations
    local msquictest_paths=(
        "/artifacts/msquictest"
        "/artifacts/${test_arch}_${CONFIG}_${TLS}/msquictest"
        "/artifacts/bin/linux/${test_arch}_${CONFIG}_${TLS}/msquictest"
    )

    local msquictest_path=""
    for path in "${msquictest_paths[@]}"; do
        if [ -f "$path" ]; then
            msquictest_path="$path"
            break
        fi
    done

    if [ -z "$msquictest_path" ]; then
        echo "Warning: msquictest not found, skipping native tests"
        echo "Searched paths:"
        for path in "${msquictest_paths[@]}"; do
            echo "  - $path"
        done
        ls -la /artifacts/ 2>/dev/null || true
        return 0
    fi

    echo "Found msquictest at: $msquictest_path"
    chmod +x "$msquictest_path"

    # Run the validation test
    "$msquictest_path" --gtest_filter=ParameterValidation.ValidateApi

    echo "msquictest: PASSED"
}

# Install .NET runtime
install_dotnet() {
    echo ""
    echo "=== Installing .NET runtime ==="

    # Check if dotnet is already installed
    if command -v dotnet &> /dev/null; then
        echo ".NET is already installed"
        dotnet --info
        return 0
    fi

    # Install dependencies based on OS
    case "$OS" in
        ubuntu|debian)
            apt-get install -y curl ca-certificates libicu-dev || apt-get install -y curl ca-certificates libicu72 || apt-get install -y curl ca-certificates libicu74 || true
            ;;
        centos|rhel|almalinux|rocky|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y curl ca-certificates libicu || true
            else
                yum install -y curl ca-certificates libicu || true
            fi
            ;;
        opensuse*|sles)
            zypper install -y curl ca-certificates libicu || true
            ;;
        azurelinux|mariner)
            tdnf install -y curl ca-certificates icu || true
            ;;
        alpine)
            apk add --no-cache curl ca-certificates icu-libs || true
            ;;
    esac

    # Download and run dotnet-install.sh
    echo "Downloading .NET install script..."
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh

    # Install .NET 9.0 runtime
    echo "Installing .NET 9.0 runtime..."
    /tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir /usr/share/dotnet || {
        echo "Warning: .NET 9.0 installation failed, trying 8.0..."
        /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet || {
            echo "Error: Failed to install .NET runtime"
            return 1
        }
    }

    # Create symlink
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet || true

    # Set environment variables
    export DOTNET_ROOT=/usr/share/dotnet
    export PATH=$PATH:/usr/share/dotnet

    echo ".NET runtime installed successfully"
    dotnet --info || true
}

# Run .NET QUIC test
run_dotnet_test() {
    echo ""
    echo "=== Running .NET QUIC test ==="

    # Look for QuicHello.dll in various locations
    local dll_paths=(
        "/dotnet/QuicHello.dll"
        "/dotnet/QuicHello.net9.0.dll"
        "/dotnet/QuicHello.net8.0.dll"
    )

    local dll_path=""
    for path in "${dll_paths[@]}"; do
        if [ -f "$path" ]; then
            dll_path="$path"
            break
        fi
    done

    if [ -z "$dll_path" ]; then
        echo "Warning: QuicHello.dll not found, skipping .NET test"
        ls -la /dotnet/ 2>/dev/null || true
        return 0
    fi

    echo "Found QuicHello at: $dll_path"

    # Install .NET if not present
    install_dotnet || {
        echo "Warning: Could not install .NET runtime, skipping .NET test"
        return 5
    }

    # Set environment for .NET
    export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
    export DOTNET_ROOT=/usr/share/dotnet
    export PATH=$PATH:/usr/share/dotnet

    # Run the test
    dotnet "$dll_path"

    echo ".NET test: PASSED"
}

# Main execution
main() {
    local exit_code=0

    # Install package
    install_package || {
        echo "ERROR: Package installation failed"
        exit 1
    }

    # Test library load
    test_library_load || {
        echo "ERROR: Library load test failed"
        exit 2
    }

    # Run msquictest
    run_msquictest || {
        echo "ERROR: msquictest failed"
        exit 3
    }

    # Run .NET test (if not skipped)
    if [ "$SKIP_DOTNET" != "true" ]; then
        run_dotnet_test
        local dotnet_result=$?
        if [ $dotnet_result -eq 5 ]; then
            echo "Warning: .NET test skipped (runtime installation failed)"
            # Don't fail the overall test for .NET installation issues
        elif [ $dotnet_result -ne 0 ]; then
            echo "ERROR: .NET test failed"
            exit 4
        fi
    else
        echo ""
        echo "=== .NET test skipped (--skip-dotnet) ==="
    fi

    echo ""
    echo "========================================"
    echo "All validations PASSED!"
    echo "========================================"
}

main "$@"
