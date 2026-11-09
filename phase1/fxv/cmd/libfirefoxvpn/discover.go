package main

// The --discover role: fetch the LIVE Mozilla RemoteSettings server
// list and print the AETHONE location model as ONE JSON line on stdout
// (the Dart FirefoxDiscovery consumes exactly this shape). No stdin,
// no secrets, exit 0 on a usable list.

import (
        "context"
        "encoding/json"
        "fmt"
        "os"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/discovery"
        "aethone/fxv/internal/engine"
)

// discoverPayload is the --discover output contract (mirrored by
// FirefoxLocationList / FirefoxLocation on the Dart side).
type discoverPayload struct {
        Locations []discovery.Location `json:"locations"`
}

func runDiscover() int {
        ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
        defer cancel()

        countries, err := vpnclient.FetchServerList(ctx)
        if err != nil {
                fmt.Fprintf(os.Stderr, "discover: fetch failed: %v\n", err)
                return engine.ExitStartup
        }
        model := discovery.Model(countries)
        if len(model) == 0 {
                fmt.Fprintf(os.Stderr, "discover: the live list carried no usable locations\n")
                return engine.ExitStartup
        }
        out, err := json.Marshal(discoverPayload{Locations: model})
        if err != nil {
                fmt.Fprintf(os.Stderr, "discover: marshal failed: %v\n", err)
                return engine.ExitStartup
        }
        fmt.Println(string(out))
        return engine.ExitClean
}
