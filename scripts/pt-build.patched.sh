#!/usr/bin/env bash
set -euo pipefail

goos="${1:-}"
goarch="${2:-}"
out="${3:-}"
goarm="${4:-}"
# With a licensedir, lyrebird's license files are copied there too, named
# lyrebird-<file>, with .txt added to a name that has no extension, and
# go_notices writes lyrebird-THIRD-PARTY-NOTICES.txt there with the license
# files of the Go standard library and the modules lyrebird links. The
# release archives carry them in LICENSES/.
licensedir="${5:-}"

if [ -z "$goos" ] || [ -z "$goarch" ] || [ -z "$out" ]; then
    echo "usage: pt-build.sh <goos> <goarch> <outdir> [goarm] [licensedir]" >&2
    exit 2
fi

# go_notice_text <texts dir> <label> <heading> <file> prints a license file
# under its heading, with \r removed, or names the entry that printed the
# same text before.
go_notice_text() {
    local texts="$1" label="$2" heading="$3" src="$4" i=1
    tr -d '\r' < "$src" > "$texts/new"
    if [ -n "$(tail -c 1 "$texts/new")" ]; then
        echo >> "$texts/new"
    fi
    printf '\n--- %s ---\n' "$heading"
    while [ -f "$texts/$i" ]; do
        if cmp -s "$texts/$i" "$texts/new"; then
            printf '(The same text as %s, above.)\n' "$(cat "$texts/$i.label")"
            return 0
        fi
        i=$((i + 1))
    done
    mv "$texts/new" "$texts/$i"
    printf '%s\n' "$label" > "$texts/$i.label"
    cat "$texts/$i"
}

# go_notices <name> <package> <file> writes the license notices of what the
# Go build in the current directory links into <package>: the Go standard
# library's LICENSE, then, for each module outside the main one that
# `go list -deps` gives a package of, its path, version and the LICENSE*,
# LICENCE*, COPYING* and NOTICE* files at its root. Run it with the build's
# GOOS, GOARCH, GOARM, CGO_ENABLED and GOFLAGS, so that it lists what the
# build compiled and the toolchain that compiled it. A text given before is
# not repeated; the entry names where it is.
#
# The standard library's LICENSE is the one at the root of the toolchain's
# GOROOT or, as Fedora's and RHEL's golang package installs it as a license
# file of the package instead (GOROOT /usr/lib/golang has none),
# /usr/share/licenses/golang/LICENSE. A module's files come from the folder
# `go list` gives as its .Dir: the module cache, or the local directory that
# replaces it. A build that vendors compiles vendor/<module path>, and
# `go list` then gives no .Dir, also for a module that go.mod replaces by a
# local directory, so its files come from vendor/<module path>.
go_notices() {
    local name="$1" pkg="$2" file="$3"
    local rule goroot goversion target golicense gosource modules texts count=0
    local mpath mversion rpath rversion mdir mreplace dir source f base found
    rule="================================================================================"
    goroot="$(go env GOROOT)"
    goversion="$(go env GOVERSION)"
    target="$(go env GOOS)/$(go env GOARCH)"
    if [ "$(go env GOARCH)" = "arm" ]; then
        target="$target, GOARM=$(go env GOARM)"
    fi
    golicense="$goroot/LICENSE"
    gosource="the Go toolchain"
    if [ ! -f "$golicense" ]; then
        golicense="/usr/share/licenses/golang/LICENSE"
        gosource="$golicense of the system's golang package"
    fi
    if [ ! -f "$golicense" ]; then
        echo "$name: no LICENSE in the Go toolchain's GOROOT $goroot or in /usr/share/licenses/golang" >&2
        return 1
    fi
    modules="$(go list -deps -f '{{if not .Standard}}{{with .Module}}{{if not .Main}}{{.Path}}|{{.Version}}|{{with .Replace}}{{.Path}}|{{.Version}}{{else}}|{{end}}|{{.Dir}}{{end}}{{end}}{{end}}' "$pkg" | sort -u)"
    texts="$(mktemp -d "$work/notices.XXXXXX")"
    {
        printf '%s\nGo standard library %s\nSource: %s\n' "$rule" "$goversion" "$gosource"
        go_notice_text "$texts" "Go standard library $goversion, LICENSE" LICENSE "$golicense"
        while IFS='|' read -r mpath mversion rpath rversion mdir; do
            if [ -z "$mpath" ]; then
                continue
            fi
            mreplace="$rpath${rversion:+ $rversion}"
            dir="$mdir"
            if [ -z "$dir" ]; then
                dir="vendor/$mpath"
                source="$dir in the source tree"
            elif [ -n "$rpath" ] && [ -z "$rversion" ]; then
                source="the local directory $rpath"
            else
                source="the module cache"
            fi
            if [ ! -d "$dir" ]; then
                echo "$name: no folder for module $mpath $mversion (looked for $dir)" >&2
                return 1
            fi
            count=$((count + 1))
            printf '  %s %s' "$mpath" "$mversion" >> "$texts/list"
            if [ -n "$mreplace" ]; then
                printf ' => %s' "$mreplace" >> "$texts/list"
            fi
            echo >> "$texts/list"
            printf '\n%s\n%s %s\nSource: %s\n' "$rule" "$mpath" "$mversion" "$source"
            if [ -n "$mreplace" ]; then
                printf 'Replaced by: %s\n' "$mreplace"
            fi
            found=0
            for f in "$dir"/*; do
                base="$(basename "$f")"
                case "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" in
                    *.go) continue ;;
                    license*|licence*|copying*|notice*) ;;
                    *) continue ;;
                esac
                if [ ! -f "$f" ]; then
                    continue
                fi
                found=1
                go_notice_text "$texts" "$mpath $mversion, $base" "$base" "$f"
            done
            if [ "$found" = 0 ]; then
                printf '\nThis module has no license file at its root.\n'
                echo "$name: warning: $mpath $mversion has no license file at its root" >&2
            fi
        done <<< "$modules"
    } > "$texts/entries"
    mkdir -p "$(dirname "$file")"
    {
        printf 'Third-party notices for %s\nBuilt by %s for %s\n\n' "$name" "$goversion" "$target"
        printf '%s links the Go standard library and the %s Go modules below,\n' "$name" "$count"
        printf 'the modules outside its own that `go list -deps` gives a package of\n'
        printf "for its build. Each entry gives the license files at the module's\n"
        printf 'root. A text given before is not repeated; the entry names where it\n'
        printf "is. %s's own license files are the other %s-* files beside\n" "$name" "$name"
        printf 'this one.\n\nModules:\n'
        if [ -f "$texts/list" ]; then
            cat "$texts/list"
        fi
        echo
        cat "$texts/entries"
    } > "$file"
    echo "$name: notices of the Go standard library and $count modules -> $file"
}

module="gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird"
repo="https://$module.git"
commit="fc105a03c0e0"
version="v0.0.0-20260312101154-fc105a03c0e0"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# AETHONE (N8 pin hardening, applied by scripts/pt-build-pin.patch):
# every acquisition path must record HOW the pinned lyrebird source was
# obtained into $PT_LYREBIRD_PROOF_FILE (consumed by build_native.sh and
# copied into the artifact manifest). dirhash_h1 is an independent local
# re-implementation of golang.org/x/mod/sumdb/dirhash (Hash1 + HashZip),
# cross-checked against the x/mod v0.29.0 source and the live
# sum.golang.org record — see
# evidence/lyrebird_pin_independent_test.txt (AETHONE CI bundle v4).
dirhash_h1() { # zip  -> prints h1:...
    python3 - "$1" <<'PYDIRHASH'
import base64, hashlib, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = sorted(i.filename for i in z.infolist())
h = hashlib.sha256()
for n in names:
    data = b'' if n.endswith('/') else z.read(n)
    h.update(hashlib.sha256(data).hexdigest().encode() + b"  " + n.encode() + b"\n")
print("h1:" + base64.b64encode(h.digest()).decode(), end='')
PYDIRHASH
}

if [ -z "${PT_LYREBIRD_PROOF_FILE:-}" ]; then
    echo "pt-build: FATAL: PT_LYREBIRD_PROOF_FILE is not set — the lyrebird pin proof cannot be recorded (N8)" >&2
    exit 1
fi

src=""
if git clone --quiet "$repo" "$work/lyrebird" 2>/dev/null; then
    src="$work/lyrebird"
    # AETHONE (N8 pin hardening, applied by scripts/pt-build-pin.patch):
    # a failed checkout must abort the build — silently continuing on the
    # default branch would build unpinned code. HEAD must also really be
    # the pinned commit, not merely "some commit that checked out fine".
    if ! git -C "$src" checkout --quiet "$commit" 2>/dev/null; then
        echo "pt-build: FATAL: pinned lyrebird commit $commit is gone upstream" >&2
        exit 1
    fi
    head_commit="$(git -C "$src" rev-parse HEAD)"
    case "$head_commit" in
        "$commit"*) ;;
        *) echo "pt-build: FATAL: lyrebird HEAD $head_commit != pin $commit" >&2; exit 1 ;;
    esac
    echo "pt-build: lyrebird source verified at $head_commit" >&2
    # AETHONE v4: record the git-path source-origin proof. The binary built
    # below carries vcs.revision == $head_commit (Go buildvcs stamping,
    # mechanism proven in evidence/lyrebird_pin_independent_test.txt [7]);
    # build_native.sh checks that grep on this path.
    printf '{"path":"git","module":"%s","pin":"%s","head":"%s"}\n' \
        "$module" "$commit" "$head_commit" > "$PT_LYREBIRD_PROOF_FILE"
    echo "pt-build: source-origin proof (git) -> $PT_LYREBIRD_PROOF_FILE" >&2
else
    echo "pt-build: cannot reach gitlab, taking the go module proxy instead" >&2
    # AETHONE (N8): the proxy URL embeds the pinned pseudo-version; assert
    # that it really does, so a future edit of $version can never bypass the
    # pin silently.
    case "$version" in
        *"$commit"*) ;;
        *) echo "pt-build: FATAL: proxy pseudo-version $version does not embed pin $commit" >&2; exit 1 ;;
    esac
    # AETHONE v4 (employer review of bundle v3, fix #3): the pseudo-version
    # embedded in the URL is NOT sufficient proof of source identity. The
    # zip is therefore verified against the PUBLIC Go checksum database:
    # the H1 dirhash that sum.golang.org attests for THIS exact module
    # version must equal the locally recomputed hash of the downloaded zip.
    # Every failure aborts the build with an explicit message — the pin is
    # never weakened and never silently bypassed.
    if ! curl -fsSL "https://proxy.golang.org/$module/@v/$version.zip" -o "$work/lyrebird.zip"; then
        echo "pt-build: FATAL: cannot download $version.zip from the module proxy (pin $commit)" >&2
        exit 1
    fi
    zip_sha256="$(sha256sum "$work/lyrebird.zip" | awk '{print $1}')"
    if ! curl -fsSL "https://sum.golang.org/lookup/$module@$version" -o "$work/lyrebird.sumdb"; then
        echo "pt-build: FATAL: sum.golang.org unreachable — proxy-path source origin cannot be proven, refusing to build (pin $commit)" >&2
        exit 1
    fi
    sumdb_h1="$(grep -m1 -o 'h1:[A-Za-z0-9+/=]*' "$work/lyrebird.sumdb")"
    if [ -z "$sumdb_h1" ]; then
        echo "pt-build: FATAL: no h1: dirhash in the sumdb record for $version — refusing to build (pin $commit)" >&2
        exit 1
    fi
    local_h1="$(dirhash_h1 "$work/lyrebird.zip")"
    if [ "$local_h1" != "$sumdb_h1" ]; then
        echo "pt-build: FATAL: dirhash mismatch: downloaded zip $local_h1 != sumdb $sumdb_h1 — SOURCE NOT PROVEN, refusing to build (pin $commit)" >&2
        exit 1
    fi
    echo "pt-build: proxy zip verified against sum.golang.org: $sumdb_h1" >&2
    # AETHONE v4.2 (employer review of v4.1, item 2): the lookup + h1 grep
    # above does NOT validate the SIGNATURE of the sumdb record. Verify the
    # signed record EXPLICITLY with the OFFICIAL Go client (GOSUMDB), in a
    # fresh temp module (a go.sum that already carries h1 entries satisfies
    # 'go mod download' WITHOUT consulting the sumdb — behaviour recorded in
    # evidence/lyrebird_sumdb_goclient_verification.txt, control B note).
    if ! command -v go >/dev/null 2>&1; then
        echo "pt-build: FATAL: go not found — official Go-client sumdb verification cannot run (pin $commit)" >&2
        exit 1
    fi
    goverify="$(mktemp -d)"
    if ! (
        export GOFLAGS= GONOPROXY= GONOSUMDB= GOPRIVATE=
        export GOPROXY="https://proxy.golang.org,direct" GOSUMDB="sum.golang.org"
        export GOTOOLCHAIN=local GOPATH="$goverify/gopath"
        export GOMODCACHE="$goverify/gomodcache" GOCACHE="$goverify/gocache"
        cd "$goverify" || exit 1
        go mod init aethone-sumdb-verify || exit 1
        go mod edit -require="$module@$version" || exit 1
        go mod download -x "$module" || exit 1
    ) > "$work/lyrebird_goclient_transcript.log" 2>&1; then
        cat "$work/lyrebird_goclient_transcript.log" >&2
        echo "pt-build: FATAL: the official Go client did NOT verify the signed sumdb record for $module@$version — SOURCE NOT PROVEN, refusing to build (pin $commit)" >&2
        rm -rf "$goverify"
        exit 1
    fi
    go_zip="$goverify/gomodcache/cache/download/$module/@v/$version.zip"
    if [ ! -f "$go_zip" ]; then
        echo "pt-build: FATAL: go-client-verified zip not found in module cache: $go_zip (pin $commit)" >&2
        rm -rf "$goverify"
        exit 1
    fi
    go_zip_sha256="$(sha256sum "$go_zip" | awk '{print $1}')"
    if [ "$go_zip_sha256" != "$zip_sha256" ]; then
        echo "pt-build: FATAL: zip identity mismatch: downloaded $zip_sha256 != go-client-verified $go_zip_sha256 — the verified zip is not the build zip, refusing to build (pin $commit)" >&2
        rm -rf "$goverify"
        exit 1
    fi
    rm -rf "$goverify"
    echo "pt-build: signed sumdb record verified by the official Go client (GOSUMDB=sum.golang.org); build zip is byte-identical to the verified zip: $go_zip_sha256" >&2
    printf '{"path":"proxy","module":"%s","version":"%s","pin":"%s","zip_sha256":"%s","dirhash":"%s","sumdb_response_sha256":"%s","sumdb_goclient":"verified-by-official-go-client","zip_identity":"curl==go-client","goclient_transcript_sha256":"%s"}\n' \
        "$module" "$version" "$commit" "$zip_sha256" "$local_h1" \
        "$(sha256sum "$work/lyrebird.sumdb" | awk '{print $1}')" \
        "$(sha256sum "$work/lyrebird_goclient_transcript.log" | awk '{print $1}')" > "$PT_LYREBIRD_PROOF_FILE"
    echo "pt-build: source-origin proof (proxy) -> $PT_LYREBIRD_PROOF_FILE" >&2
    (cd "$work" && unzip -q lyrebird.zip)

    src="$work/$module@$version"
    if [ ! -f "$src/go.mod" ]; then
        src="$(dirname "$(find "$work" -type f -name go.mod | head -n 1)")"
    fi
    chmod -R u+w "$src"
fi

if [ ! -f "$src/go.mod" ]; then
    echo "pt-build: no lyrebird source to build" >&2
    exit 1
fi

ext=""
if [ "$goos" = "windows" ]; then
    ext=".exe"
fi

mkdir -p "$out"

(
    cd "$src"
    export GOOS="$goos" GOARCH="$goarch" GOARM="$goarm" CGO_ENABLED=0
    go build -trimpath -ldflags "-s -w" -o "$out/lyrebird$ext" ./cmd/lyrebird
    if [ -n "$licensedir" ]; then
        go_notices lyrebird ./cmd/lyrebird "$licensedir/lyrebird-THIRD-PARTY-NOTICES.txt"
    fi
)

if [ -n "$licensedir" ]; then
    mkdir -p "$licensedir"
    copied=""
    for f in "$src"/LICENSE* "$src"/LICENCE* "$src"/COPYING* "$src"/NOTICE*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        case "$name" in
            *.*) ;;
            *) name="$name.txt" ;;
        esac
        cp "$f" "$licensedir/lyrebird-$name"
        copied="$copied lyrebird-$name"
    done
    if [ -z "$copied" ]; then
        echo "pt-build: lyrebird's source has no license file" >&2
        exit 1
    fi
    echo "pt-build: license files ->$copied"
fi

echo "pt-build: $goos/$goarch ->"
ls -l "$out"
