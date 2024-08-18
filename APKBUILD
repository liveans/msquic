# Contributor: Microsoft QUIC Team <quicdev@microsoft.com>
# Maintainer: Microsoft QUIC Team <quicdev@microsoft.com>
pkgname=libmsquic
pkgver=2.5.0
pkgrel=0
pkgdesc="Cross-platform, C implementation of the IETF QUIC protocol, exposed to C, C++, C# and Rust."
url="https://github.com/microsoft/msquic"
arch="x86_64 armhf aarch64"
license="MIT"
depends="openssl numactl"
subpackages="$pkgname-dev $pkgname-doc"
source="version.json"
builddir="$srcdir/.."

prepare() {
        # Install dependencies
        sudo apk add --upgrade --no-cache \
                cmake \
                g++ \
                gcc \
                git \
                numactl-dev \
                linux-headers \
                lttng-ust-dev \
                make \
                musl-dev \
                openssl-dev \
                perf
        git submodule update --init --recursive
}

build() {
	pwd
        cd $builddir
        cmake -B build/linux/Release_openssl3 \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_TARGET_ARCHITECTURE=${TARGETARCH} \
                -DQUIC_TLS=openssl3 \
                -DQUIC_ENABLE_LOGGING=true \
                -DQUIC_USE_SYSTEM_LIBCRYPTO=true \
                -DQUIC_BUILD_TOOLS=on \
                -DQUIC_BUILD_TEST=on \
                -DQUIC_BUILD_PERF=off
        cmake --build build/linux/Release_openssl3  --config Release
}

check() {
        # TODO : Run tests with packaging
        cd $builddir/build/linux/Release_openssl3
        ctest --output-on-failure
}

package() {
        mkdir -p "$pkgdir"
        cmake --install build/linux/Release_openssl3 --prefix $pkgdir
}
sha512sums="
ab9c24c66e8ce144d966cb65d586753ca5b8110d7f7188573e9a0ee02453fab23970e7c7ee5e5bec75252af07eb67f01ba158c7a62f950f3661d77590d646451  version.json
"
