package providerurl

import (
	"strings"
	"testing"
)

func TestValidate(t *testing.T) {
	const (
		envVar         = "FEED_PROVIDER_URL"
		insecureEnvVar = "FEED_ALLOW_INSECURE_HTTP"
	)
	tests := []struct {
		name              string
		raw               string
		allowInsecureHTTP bool
		want              string // "" = valid; otherwise a required substring
		forbidden         string // must not appear in the message
	}{
		{name: "valid https", raw: "https://feed.example.com/v2"},
		{name: "valid uppercase scheme", raw: "HTTPS://feed.example.com/v2"},
		{name: "whitespace trimmed", raw: "  https://feed.example.com/v2\n"},
		{name: "empty", raw: "", want: envVar + " is required"},
		{name: "whitespace only", raw: "   ", want: envVar + " is required"},
		{name: "malformed", raw: "://invalid", want: envVar + " is invalid"},
		{name: "missing host", raw: "https://", want: "must include a host"},
		{name: "port-only host", raw: "https://:443/v2", want: "must include a host"},
		{
			name:      "embedded credentials",
			raw:       "https://user:hunter2secret@feed.example.com/v2",
			want:      "must not contain embedded credentials",
			forbidden: "hunter2secret",
		},
		{name: "out-of-range port", raw: "https://feed.example.com:99999/v2", want: "has an invalid port"},
		{name: "empty port", raw: "https://feed.example.com:/v2", want: "has an invalid port"},
		{name: "non-http scheme", raw: "ftp://feed.example.com/v2", want: "must be http(s)"},
		{name: "http without opt-in", raw: "http://feed.example.com/v2", want: "must be https; set " + insecureEnvVar + "=true"},
		{name: "http with opt-in", raw: "http://feed.example.com/v2", allowInsecureHTTP: true},
		{name: "uppercase http without opt-in", raw: "HTTP://feed.example.com/v2", want: "must be https"},
		{name: "opt-in does not relax whitelist", raw: "ftp://feed.example.com/v2", allowInsecureHTTP: true, want: "must be http(s)"},
		{
			name:      "parse error does not leak credentials",
			raw:       "https://user:hunter2secret@feed.example.com/%zz",
			want:      envVar + " is invalid",
			forbidden: "hunter2secret",
		},
		{name: "signed port rejected at parse", raw: "https://feed.example.com:+443/v2", want: envVar + " is invalid"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Validate(tt.raw, envVar, insecureEnvVar, tt.allowInsecureHTTP)
			if tt.want == "" {
				if got != "" {
					t.Errorf("Validate(%q) = %q, want valid", tt.raw, got)
				}
			} else if !strings.Contains(got, tt.want) {
				t.Errorf("Validate(%q) = %q, want substring %q", tt.raw, got, tt.want)
			}
			if tt.forbidden != "" && strings.Contains(got, tt.forbidden) {
				t.Errorf("Validate(%q) = %q leaks %q", tt.raw, got, tt.forbidden)
			}
		})
	}
}
