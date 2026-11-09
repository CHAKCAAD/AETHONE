//go:build !cgo

package main

// resolverGoBuildCgoEnabled reports (at compile time) that this binary
// was built WITHOUT CGO — Go's own pure resolver. Fine for the Linux
// host test binary; on Android this is the KNOWN-BROKEN configuration
// (the [::1]:53 dead-resolver failure) the A1 decree eliminates, and
// build_engine.sh refuses to produce Android arm64 builds this way.

const resolverGoBuildCgoEnabled = false
