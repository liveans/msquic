#!/bin/bash
# Downloads libmsquic packages from packages.microsoft.com
# Used by GitHub Actions workflow for package validation

set -e

# Default values
DISTRO=""
ARCH=""
TYPE=""
VERSION=""
TESTING="false"
OUTPUT="."

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --distro) DISTRO="$2"; shift 2 ;;
        --arch) ARCH="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --testing) TESTING="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 --distro <distro> --arch <arch> --type <deb|rpm> [options]"
            echo ""
            echo "Options:"
            echo "  --distro    Distribution name (e.g., ubuntu_24_04, fedora_42)"
            echo "  --arch      Package architecture (amd64, arm64, armhf for DEB; x86_64, aarch64 for RPM)"
            echo "  --type      Package type: deb or rpm"
            echo "  --version   Specific version to download (empty for latest)"
            echo "  --testing   Use testing/preview repos: true or false (default: false)"
            echo "  --output    Output directory (default: current directory)"
            exit 0
            ;;
        *) shift ;;
    esac
done

# Validate required arguments
if [ -z "$DISTRO" ] || [ -z "$ARCH" ] || [ -z "$TYPE" ]; then
    echo "Error: --distro, --arch, and --type are required"
    echo "Run with --help for usage information"
    exit 1
fi

mkdir -p "$OUTPUT"

# Build URL based on distro
get_base_url() {
    local distro=$1
    local testing=$2
    local arch=$3

    case "$distro" in
        # DEB-based distributions (Ubuntu, Debian)
        ubuntu_22_04)
            echo "https://packages.microsoft.com/ubuntu/22.04/prod/pool/main/libm/libmsquic/"
            ;;
        ubuntu_24_04)
            echo "https://packages.microsoft.com/ubuntu/24.04/prod/pool/main/libm/libmsquic/"
            ;;
        ubuntu_25_10)
            echo "https://packages.microsoft.com/ubuntu/25.10/prod/pool/main/libm/libmsquic/"
            ;;
        debian_12)
            echo "https://packages.microsoft.com/debian/12/prod/pool/main/libm/libmsquic/"
            ;;
        debian_13)
            echo "https://packages.microsoft.com/debian/13/prod/pool/main/libm/libmsquic/"
            ;;

        # Azure Linux (has separate x86_64 and aarch64 URLs)
        azurelinux_3_0)
            if [ "$arch" = "aarch64" ]; then
                if [ "$testing" = "true" ]; then
                    echo "https://packages.microsoft.com/azurelinux/3.0/preview/ms-oss/aarch64/Packages/l/"
                else
                    echo "https://packages.microsoft.com/azurelinux/3.0/prod/ms-oss/aarch64/Packages/l/"
                fi
            else
                if [ "$testing" = "true" ]; then
                    echo "https://packages.microsoft.com/azurelinux/3.0/preview/ms-oss/x86_64/Packages/l/"
                else
                    echo "https://packages.microsoft.com/azurelinux/3.0/prod/ms-oss/x86_64/Packages/l/"
                fi
            fi
            ;;

        # CentOS Stream
        centos_stream_9)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/rhel/9/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/rhel/9/prod/Packages/l/"
            fi
            ;;
        centos_stream_10)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/centos/10/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/centos/10/prod/Packages/l/"
            fi
            ;;

        # RHEL
        rhel_9)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/rhel/9/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/rhel/9/prod/Packages/l/"
            fi
            ;;
        rhel_10)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/rhel/10/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/rhel/10/prod/Packages/l/"
            fi
            ;;

        # Fedora
        fedora_42)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/fedora/42/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/fedora/42/prod/Packages/l/"
            fi
            ;;
        fedora_43)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/fedora/43/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/fedora/43/prod/Packages/l/"
            fi
            ;;

        # openSUSE
        opensuse_15_6)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/yumrepos/microsoft-opensuse15-testing-prod/Packages/l/"
            else
                echo "https://packages.microsoft.com/opensuse/15/prod/Packages/l/"
            fi
            ;;
        opensuse_16_0)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/opensuse/16/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/opensuse/16/prod/Packages/l/"
            fi
            ;;

        # SLES
        sles_15_6|sles_15_7)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/yumrepos/microsoft-sles15-testing-prod/Packages/l/"
            else
                echo "https://packages.microsoft.com/sles/15/prod/Packages/l/"
            fi
            ;;
        sles_16)
            if [ "$testing" = "true" ]; then
                echo "https://packages.microsoft.com/sles/16/testing/Packages/l/"
            else
                echo "https://packages.microsoft.com/sles/16/prod/Packages/l/"
            fi
            ;;

        *)
            echo "Error: Unknown distro: $distro" >&2
            exit 1
            ;;
    esac
}

# Get the base URL for this distro
BASE_URL=$(get_base_url "$DISTRO" "$TESTING" "$ARCH")
echo "Fetching package list from: $BASE_URL"

# Fetch the directory listing
HTML=$(curl -sL "$BASE_URL")
if [ -z "$HTML" ]; then
    echo "Error: Failed to fetch package list from $BASE_URL"
    exit 1
fi

# Find matching packages based on type and architecture
if [ "$TYPE" = "deb" ]; then
    # DEB package pattern: libmsquic_X.X.X_<arch>.deb
    # Filter by architecture suffix
    if [ "$TESTING" = "true" ]; then
        # Testing: look for ~rc packages
        PACKAGES=$(echo "$HTML" | grep -oP 'href="(libmsquic_[^"]+~rc[^"]*_'"$ARCH"'\.deb)"' | sed 's/href="//;s/"//' || true)
    else
        # Prod: exclude ~rc packages
        PACKAGES=$(echo "$HTML" | grep -oP 'href="(libmsquic_[^"]+_'"$ARCH"'\.deb)"' | sed 's/href="//;s/"//' | grep -v '~rc' || true)
    fi
else
    # RPM package pattern: libmsquic-X.X.X-1.<arch>.rpm
    if [ "$TESTING" = "true" ]; then
        PACKAGES=$(echo "$HTML" | grep -oP 'href="(libmsquic-[^"]+\.'"$ARCH"'\.rpm)"' | sed 's/href="//;s/"//' || true)
    else
        PACKAGES=$(echo "$HTML" | grep -oP 'href="(libmsquic-[^"]+\.'"$ARCH"'\.rpm)"' | sed 's/href="//;s/"//' | grep -v '~rc' || true)
    fi
fi

if [ -z "$PACKAGES" ]; then
    echo "Error: No packages found for $DISTRO $ARCH"
    exit 1
fi

echo "Found packages:"
echo "$PACKAGES" | head -10

# Function to extract version from package filename
extract_version() {
    local filename=$1
    local type=$2

    if [ "$type" = "deb" ]; then
        # libmsquic_2.4.8_amd64.deb -> 2.4.8
        echo "$filename" | sed -E 's/libmsquic_([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
    else
        # libmsquic-2.4.8-1.x86_64.rpm -> 2.4.8
        echo "$filename" | sed -E 's/libmsquic-([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
    fi
}

# Function to compare versions (returns 0 if v1 > v2, 1 if v1 < v2, 2 if equal)
version_compare() {
    local v1=$1
    local v2=$2

    # Split versions into components
    IFS='.' read -ra V1_PARTS <<< "$v1"
    IFS='.' read -ra V2_PARTS <<< "$v2"

    for i in 0 1 2; do
        local p1=${V1_PARTS[$i]:-0}
        local p2=${V2_PARTS[$i]:-0}

        if [ "$p1" -gt "$p2" ]; then
            return 0
        elif [ "$p1" -lt "$p2" ]; then
            return 1
        fi
    done

    return 2  # Equal
}

# Find the package to download
TARGET_PACKAGE=""

if [ -n "$VERSION" ]; then
    # Look for specific version
    echo "Looking for version: $VERSION"
    for pkg in $PACKAGES; do
        pkg_version=$(extract_version "$pkg" "$TYPE")
        if [ "$pkg_version" = "$VERSION" ]; then
            TARGET_PACKAGE="$pkg"
            break
        fi
    done

    if [ -z "$TARGET_PACKAGE" ] && [ "$TESTING" != "true" ]; then
        # Fallback: try testing repo if version not found in prod
        echo "Version $VERSION not found in prod repo, trying testing repo..."
        FALLBACK_URL=$(get_base_url "$DISTRO" "true" "$ARCH")
        echo "Fetching from testing repo: $FALLBACK_URL"

        FALLBACK_HTML=$(curl -sL "$FALLBACK_URL")
        if [ -n "$FALLBACK_HTML" ]; then
            if [ "$TYPE" = "deb" ]; then
                FALLBACK_PACKAGES=$(echo "$FALLBACK_HTML" | grep -oP 'href="(libmsquic_[^"]+_'"$ARCH"'\.deb)"' | sed 's/href="//;s/"//' || true)
            else
                FALLBACK_PACKAGES=$(echo "$FALLBACK_HTML" | grep -oP 'href="(libmsquic-[^"]+\.'"$ARCH"'\.rpm)"' | sed 's/href="//;s/"//' || true)
            fi

            for pkg in $FALLBACK_PACKAGES; do
                pkg_version=$(extract_version "$pkg" "$TYPE")
                if [ "$pkg_version" = "$VERSION" ]; then
                    TARGET_PACKAGE="$pkg"
                    BASE_URL="$FALLBACK_URL"
                    PACKAGES="$FALLBACK_PACKAGES"
                    echo "Found version $VERSION in testing repo"
                    break
                fi
            done
        fi
    fi

    if [ -z "$TARGET_PACKAGE" ]; then
        echo "Error: Version $VERSION not found in prod or testing repos. Available versions:"
        for pkg in $PACKAGES; do
            echo "  $(extract_version "$pkg" "$TYPE")"
        done | sort -u
        exit 1
    fi
else
    # Find latest version
    echo "Finding latest version..."
    LATEST_VERSION=""

    for pkg in $PACKAGES; do
        pkg_version=$(extract_version "$pkg" "$TYPE")

        if [ -z "$LATEST_VERSION" ]; then
            LATEST_VERSION="$pkg_version"
            TARGET_PACKAGE="$pkg"
        else
            if version_compare "$pkg_version" "$LATEST_VERSION"; then
                LATEST_VERSION="$pkg_version"
                TARGET_PACKAGE="$pkg"
            fi
        fi
    done

    echo "Latest version: $LATEST_VERSION"
fi

if [ -z "$TARGET_PACKAGE" ]; then
    echo "Error: Could not determine package to download"
    exit 1
fi

# Download the package
DOWNLOAD_URL="${BASE_URL}${TARGET_PACKAGE}"
OUTPUT_FILE="${OUTPUT}/${TARGET_PACKAGE}"

echo "Downloading: $TARGET_PACKAGE"
echo "URL: $DOWNLOAD_URL"
echo "Output: $OUTPUT_FILE"

curl -sL -o "$OUTPUT_FILE" "$DOWNLOAD_URL"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    echo "Downloaded successfully: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Error: Download failed"
    exit 1
fi

echo "Done!"
