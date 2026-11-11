package main

// The --discover role fetches the live Mozilla Remote Settings list.
// It accepts an optional DNS config on stdin; empty stdin preserves the
// backward-compatible Android system resolver behavior.

import (
        "context"
        "encoding/json"
        "fmt"
        "os"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/discovery"
        "aethone/fxv/internal/dnsresolver"
        "aethone/fxv/internal/engine"
)

type discoverPayload struct {
        Locations []discovery.Location `json:"locations"`
}

func runDiscover() int {
        dnsConfig, err := readOptionalDNSConfig(os.Stdin)
        if err != nil {
                fmt.Fprintf(os.Stderr, "discover: invalid DNS configuration: %v\n", err)
                return engine.ExitStartup
        }
        if _, err := dnsresolver.Install(dnsConfig); err != nil {
                fmt.Fprintf(os.Stderr, "discover: DNS setup failed: %v\n", err)
                return engine.ExitStartup
        }

        ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
        defer cancel()
        countries, err := vpnclient.FetchServerList(ctx)
        if err != nil {
                fmt.Fprintf(os.Stderr, "discover: fetch failed: %v\n", err)
                return engine.ExitStartup
        }
        model := discovery.Model(countries)
        if len(model) == 0 {
                fmt.Fprintln(os.Stderr, "discover: the live list carried no usable locations")
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
