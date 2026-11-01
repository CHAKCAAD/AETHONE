package psiphon

import (
	"testing"

	"github.com/Psiphon-Labs/psiphon-tunnel-core/psiphon/common/protocol"
)

func TestQUICNoiseAllowed(t *testing.T) {
	quic := protocol.GetCapability(protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH)
	withGQUIC := &protocol.ServerEntry{Capabilities: []string{quic, quic + "v1"}}
	v1Only := &protocol.ServerEntry{Capabilities: []string{quic + "v1"}}

	cases := []struct {
		name     string
		tunnel   string
		version  string
		server   *protocol.ServerEntry
		expected bool
	}{
		{"plain QUICv1 to a gQUIC server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_V1, withGQUIC, true},
		{"randomized QUICv1 to a gQUIC server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_RANDOMIZED_V1, withGQUIC, true},
		{"obfuscated QUICv1 to a gQUIC server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_OBFUSCATED_V1, withGQUIC, false},
		{"decoy QUICv1 to a gQUIC server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_DECOY_V1, withGQUIC, false},
		{"obfuscated QUICv1 to a QUICv1-only server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_OBFUSCATED_V1, v1Only, true},
		{"decoy QUICv1 to a QUICv1-only server", protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_DECOY_V1, v1Only, true},
		{"fronted meek over QUIC", protocol.TUNNEL_PROTOCOL_FRONTED_MEEK_QUIC_OBFUSCATED_SSH, protocol.QUIC_VERSION_V1, withGQUIC, true},
		{"in-proxy QUIC travels through the proxy", protocol.TunnelProtocolPlusInproxyWebRTC(protocol.TUNNEL_PROTOCOL_QUIC_OBFUSCATED_SSH), protocol.QUIC_VERSION_V1, v1Only, false},
		{"OSSH is TCP", protocol.TUNNEL_PROTOCOL_OBFUSCATED_SSH, "", v1Only, false},
		{"TLS-OSSH is TCP", protocol.TUNNEL_PROTOCOL_TLS_OBFUSCATED_SSH, "", v1Only, false},
	}
	for _, c := range cases {
		dialParams := &DialParameters{TunnelProtocol: c.tunnel, QUICVersion: c.version, ServerEntry: c.server}
		if got := quicNoiseAllowed(dialParams); got != c.expected {
			t.Errorf("%s: allowed=%v, want %v", c.name, got, c.expected)
		}
	}
}
