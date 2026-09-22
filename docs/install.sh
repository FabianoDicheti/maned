#!/bin/sh
# ---------------------------------------------------------------------------
# Maned installer.
#
#   curl -fsSL https://fabianodicheti.github.io/maned/install.sh | sh
#
#   ... | sh -s -- --version 0.1.0       install a specific release
#   ... | sh -s -- --prefix ~/.local     install somewhere else
#   ... | sh -s -- --dry-run             show what would happen
#   ... | sh -s -- --uninstall           remove the binaries again
#
# Downloads a prebuilt tarball for this machine, verifies its SHA-256 against
# the release's SHA256SUMS, and installs three binaries. It writes nothing
# outside the install prefix, never calls sudo, and never edits your shell
# configuration.
#
# WHAT THE CHECKSUM PROVES. SHA256SUMS is fetched over the same TLS connection
# to the same host as the tarball. It catches a truncated download, a corrupted
# CDN cache, or a stale mirror. It is NOT a signature: it does not defend
# against a compromised GitHub account or anyone who can forge both files. If
# you need that guarantee, build from a source licence instead.
# ---------------------------------------------------------------------------
set -eu

REPO="${MANED_REPO:-FabianoDicheti/maned}"
TOOLS="maned-run maned-serve maned-lint"
# The hosted Bark worker, shipped since 0.2.1 so `host = "local"` works on a
# plain install. Handled apart from $TOOLS: it has no --version flag, so the
# delete-safety probe below identifies it by its usage line instead. Older
# tarballs do not carry it, and the installer stays compatible with those.
VM_TOOL="bark-vm"
VM_ALIAS="maned-bark-here"

VERSION=""
PREFIX=""
DRY_RUN=0
UNINSTALL=0

say()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="${2:?--version needs a value}"; shift ;;
    --prefix)    PREFIX="${2:?--prefix needs a value}"; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)   sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# --- Where ------------------------------------------------------------------
if [ -n "$PREFIX" ]; then
  BINDIR="$PREFIX/bin"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  BINDIR=/usr/local/bin
else
  BINDIR="$HOME/.local/bin"
fi

# --- Uninstall --------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  say "Removing Maned from $BINDIR"
  removed=0
  # The VM answers --help, not --version, so it gets its own probe: the
  # usage line names the flag nothing else on a PATH is likely to print.
  vb="$BINDIR/$VM_TOOL"
  if [ -f "$vb" ] && "$vb" --help 2>&1 | head -1 | grep -q -- "--max-payload"; then
    va="$BINDIR/$VM_ALIAS"
    [ -L "$va" ] && [ "$(readlink "$va")" = "$VM_TOOL" ] && rm -f "$va"
    rm -f "$vb"
    removed=$((removed + 1))
  fi
  for t in $TOOLS; do
    b="$BINDIR/$t"
    [ -f "$b" ] || continue
    # Only delete a file that identifies itself as the tool it is named after.
    # The path is partly user-supplied, and rm on a guessed path is how an
    # installer eats something it did not install.
    if "$b" --version 2>/dev/null | head -1 | grep -q "^$t "; then
      [ "$DRY_RUN" = 1 ] && info "would remove $b" || { rm -f "$b"; info "removed $b"; }
      removed=$((removed + 1))
    else
      info "skipped $b (does not identify as $t)"
    fi
  done
  [ "$removed" -gt 0 ] || info "nothing to remove"
  exit 0
fi

# --- Which build ------------------------------------------------------------
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin) target=universal-apple-darwin ;;
  Linux)
    # musl is not a near miss: the binary links glibc, and without this check
    # the user gets "not found" for a file that is plainly there.
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
      die "Maned links glibc; Alpine and other musl systems are not supported"
    fi
    case "$arch" in
      x86_64|amd64)  target=x86_64-unknown-linux-gnu ;;
      aarch64|arm64) target=aarch64-unknown-linux-gnu ;;
      *) die "no Linux build for $arch (x86_64 and aarch64 only)" ;;
    esac
    ;;
  *) die "unsupported operating system: $os (macOS and Linux only)" ;;
esac

for c in curl tar; do
  command -v "$c" >/dev/null 2>&1 || die "$c is required but not installed"
done
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"
elif command -v shasum >/dev/null 2>&1;   then SHA="shasum -a 256"
else die "need sha256sum or shasum to verify the download"
fi

# --- Resolve the release ----------------------------------------------------
# SHA256SUMS is the only asset whose filename does not carry the version, which
# makes it the discovery mechanism: fetch it, read the tarball name out of it.
# This avoids the GitHub API entirely - no JSON to parse without jq, and no
# 60-requests-per-hour unauthenticated rate limit, which bites everyone sharing
# a corporate NAT.
# $MANED_BASE exists so the installer can be exercised end to end against a
# local server before a release is public. Not for general use.
BASE="${MANED_BASE:-https://github.com/$REPO/releases}"
if [ -n "$VERSION" ]; then
  sums_url="$BASE/download/v$VERSION/SHA256SUMS"
else
  sums_url="$BASE/latest/download/SHA256SUMS"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/maned-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Maned installer"
info "platform   $os $arch -> $target"

curl -fsSL "$sums_url" -o "$TMP/SHA256SUMS" \
  || die "could not fetch $sums_url${VERSION:+ (is v$VERSION a real release?)}"

line=$(grep -E "  maned-[^ ]+-$target\.tar\.gz$" "$TMP/SHA256SUMS" | head -1) \
  || die "this release has no build for $target"
[ -n "$line" ] || die "this release has no build for $target"
want=$(echo "$line" | awk '{print $1}')
tarball=$(echo "$line" | awk '{print $2}')
found_version=$(echo "$tarball" | sed -E "s/^maned-(.+)-$target\.tar\.gz$/\1/")

if [ -n "$VERSION" ]; then
  tar_url="$BASE/download/v$VERSION/$tarball"
else
  tar_url="$BASE/latest/download/$tarball"
fi

info "version    $found_version"
info "install to $BINDIR"

if [ "$DRY_RUN" = 1 ]; then
  info "url        $tar_url"
  info "sha256     $want"
  say "dry run: nothing was downloaded or written"
  exit 0
fi

# --- Download and verify ----------------------------------------------------
curl -fsSL "$tar_url" -o "$TMP/$tarball" || die "download failed: $tar_url"

# Compare explicitly rather than `sha256sum -c`: the manifest lists all three
# platforms, so -c would report the two files we did not download as failures
# and exit non-zero on a perfectly good install.
got=$($SHA "$TMP/$tarball" | awk '{print $1}')
if [ "$got" != "$want" ]; then
  die "checksum mismatch for $tarball
    expected $want
    actual   $got
  Refusing to install. Try again; if it persists, report it."
fi
info "sha256     verified"

tar -xzf "$TMP/$tarball" -C "$TMP"
unpacked="$TMP/maned-$found_version-$target"
[ -d "$unpacked/bin" ] || die "unexpected archive layout in $tarball"

# --- Install ----------------------------------------------------------------
mkdir -p "$BINDIR" 2>/dev/null || die "cannot create $BINDIR"
if [ ! -w "$BINDIR" ]; then
  die "$BINDIR is not writable. Either
    sh install.sh --prefix \"\$HOME/.local\"
  or re-run this installer with sudo."
fi

for t in $TOOLS; do
  # install(1) unlinks and replaces, so this is safe even if a copy is running.
  install -m 0755 "$unpacked/bin/$t" "$BINDIR/$t"
done
installed="$TOOLS"
if [ -f "$unpacked/bin/$VM_TOOL" ]; then
  install -m 0755 "$unpacked/bin/$VM_TOOL" "$BINDIR/$VM_TOOL"
  # Relative target: the pair moves together if $BINDIR is ever relocated.
  ln -sf "$VM_TOOL" "$BINDIR/$VM_ALIAS"
  installed="$installed $VM_TOOL $VM_ALIAS"
fi
info "installed  $installed"

# --- PATH -------------------------------------------------------------------
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *)
    case "${SHELL:-}" in
      */zsh)  rc="~/.zshrc" ;;
      */bash) rc="~/.bashrc" ;;
      */fish) rc="~/.config/fish/config.fish" ;;
      *)      rc="your shell's startup file" ;;
    esac
    say ""
    say "$BINDIR is not on your PATH. Add this line to $rc:"
    say ""
    say "    export PATH=\"$BINDIR:\$PATH\""
    ;;
esac

say ""
say "Maned $found_version installed. Try:"
say ""
say "    maned-run --version"
say ""
say "Docs: https://maned-lang.com"
