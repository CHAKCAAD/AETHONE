//go:build cgo

package main

// resolverGoBuildCgoEnabled reports (at compile time) that this binary
// was built with CGO — on Android that means name resolution goes
// through Bionic's getaddrinfo (the platform resolver), which is the
// A1 decree's required configuration for every Android ABI.

const resolverGoBuildCgoEnabled = true
