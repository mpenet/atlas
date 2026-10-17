#!/bin/sh
# ABOUTME: Packages a Linux release binary of ezu as a .deb and a .rpm, with its
# ABOUTME: shell completions and licenses; needs dpkg-deb and rpmbuild.
set -eu

if [ $# -ne 4 ]; then
  echo "usage: $0 BINARY VERSION ARCH OUTDIR   (ARCH: x86_64 or arm64)" >&2
  echo "COMPLETER=PATH: an ezu that runs here, to write the completions" >&2
  echo "(BINARY itself by default)" >&2
  exit 1
fi

binary=$1
version=$2
arch=$3
out=$4
completer=${COMPLETER:-$binary}
here=$(cd "$(dirname "$0")/.." && pwd)

# 1.0.0-beta8 is 1.0.0~beta8: apt and rpm sort it before 1.0.0
pkgver=$(printf '%s' "$version" | sed 's/-/~/')

case $arch in
  x86_64) deb_arch=amd64; rpm_arch=x86_64 ;;
  arm64) deb_arch=arm64; rpm_arch=aarch64 ;;
  *) echo "unknown architecture: $arch" >&2; exit 1 ;;
esac

summary="Call OpenAPI APIs and run Arazzo workflows from the command line"
description="ezu turns any API with an OpenAPI 3 description into commands,
with help, completion and checks before anything is sent, and runs
Arazzo workflows across its operations."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# stage ROOT ZSH_DIR: the files both packages install, under ROOT
stage() {
  install -Dm755 "$binary" "$1/usr/bin/ezu"
  mkdir -p "$1/usr/share/bash-completion/completions" "$1$2" \
    "$1/usr/share/fish/vendor_completions.d"
  "$completer" completion bash > "$1/usr/share/bash-completion/completions/ezu"
  "$completer" completion zsh > "$1$2/_ezu"
  "$completer" completion fish > "$1/usr/share/fish/vendor_completions.d/ezu.fish"
}

# ---- .deb ----
deb=$work/deb
stage "$deb" /usr/share/zsh/vendor-completions
mkdir -p "$deb/DEBIAN" "$deb/usr/share/doc/ezu"
{
  echo "ezu is licensed under the Mozilla Public License 2.0, below; the"
  echo "software it contains is listed with its licenses in THIRD-PARTY.md."
  echo
  cat "$here/LICENSE"
} > "$deb/usr/share/doc/ezu/copyright"
cp "$here/THIRD-PARTY.md" "$deb/usr/share/doc/ezu/"
cat > "$deb/DEBIAN/control" <<EOF
Package: ezu
Version: $pkgver
Architecture: $deb_arch
Maintainer: Max Penet <mpenet@s-exp.com>
Installed-Size: $(du -sk "$deb/usr" | cut -f1)
Section: utils
Priority: optional
Homepage: https://github.com/mpenet/ezu
Description: $summary
$(printf '%s\n' "$description" | sed 's/^/ /')
EOF
dpkg-deb --root-owner-group --build "$deb" "$out/ezu_${pkgver}_${deb_arch}.deb" >/dev/null

# ---- .rpm ----
rpmroot=$work/rpm
stage "$rpmroot/staging" /usr/share/zsh/site-functions
mkdir -p "$rpmroot/staging/usr/share/licenses/ezu"
cp "$here/LICENSE" "$here/THIRD-PARTY.md" "$rpmroot/staging/usr/share/licenses/ezu/"
cat > "$rpmroot/ezu.spec" <<EOF
# the binary is static and already stripped: nothing to build or extract
%global debug_package %{nil}
%global __strip /bin/true
%define _build_id_links none

Name: ezu
Version: $pkgver
Release: 1
Summary: $summary
License: MPL-2.0
URL: https://github.com/mpenet/ezu
AutoReqProv: no

%description
$description

%install
cp -a $rpmroot/staging/. %{buildroot}/

%files
/usr/bin/ezu
/usr/share/bash-completion/completions/ezu
/usr/share/zsh/site-functions/_ezu
/usr/share/fish/vendor_completions.d/ezu.fish
%license /usr/share/licenses/ezu/LICENSE
%license /usr/share/licenses/ezu/THIRD-PARTY.md
EOF
rpmbuild -bb --quiet --target "$rpm_arch" \
  --define "_topdir $rpmroot/top" \
  --define "_rpmdir $rpmroot/out" \
  "$rpmroot/ezu.spec" >/dev/null
mv "$rpmroot"/out/*/ezu-*.rpm "$out/"
