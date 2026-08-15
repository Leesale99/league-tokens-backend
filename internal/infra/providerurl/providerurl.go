// Package providerurl validates provider endpoint URLs shared by the feed and
// schedule contexts. Both poll the same external data provider and carry the
// same provider_api_key secret, so the URL checks must never diverge.
//
// Split strategy: the package is deliberately dependency-free (stdlib only, no
// app-layer imports — no config structs, secrets, or env parsing). When the
// modular monolith is split into microservices, move this directory verbatim
// into a shared module (publish it as its own Go module, or vendor it into the
// feed and schedule services) and update the two import sites. Nothing else
// changes: the package has no internal couplings, so the extraction is purely
// mechanical.
package providerurl

import (
	"errors"
	"net/url"
	"strconv"
	"strings"
)

// Validate checks a provider endpoint URL and returns the first defect message,
// or "" if the URL is valid. envVar and insecureEnvVar name the caller's env
// vars (e.g. "FEED_PROVIDER_URL" / "FEED_ALLOW_INSECURE_HTTP") so error
// messages stay field-specific per ADR-0012. allowInsecureHTTP opts into plain
// http for local mock providers only; the provider API key must never travel in
// cleartext (ADR-0007).
func Validate(raw, envVar, insecureEnvVar string, allowInsecureHTTP bool) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return envVar + " is required"
	}
	u, err := url.Parse(raw)
	switch {
	case err != nil:
		// url.Parse errors embed the raw URL (url.Error.URL), which may carry
		// userinfo; surface only the reason so credentials never reach the
		// logs (ADR-0007).
		return envVar + " is invalid: " + parseErrorReason(err)
	case u.Host == "" || u.Hostname() == "":
		return envVar + " must include a host"
	case u.User != nil:
		return envVar + " must not contain embedded credentials (user:pass@)"
	case invalidURLPort(u):
		return envVar + " has an invalid port"
	case strings.EqualFold(u.Scheme, "http") && !allowInsecureHTTP:
		return envVar + " must be https; set " + insecureEnvVar + "=true for local http dev"
	case !strings.EqualFold(u.Scheme, "https") && !strings.EqualFold(u.Scheme, "http"):
		return envVar + " must be http(s)"
	}
	return ""
}

// parseErrorReason returns the underlying reason of a url.Parse failure,
// omitting the raw URL that url.Error embeds (which may carry userinfo).
func parseErrorReason(err error) string {
	var ue *url.Error
	if errors.As(err, &ue) && ue.Err != nil {
		return ue.Err.Error()
	}
	// Non-*url.Error failures are unexpected; never fall back to err.Error()
	// as it may embed the raw URL and any userinfo it carried.
	return "malformed URL"
}

func validPort(p string) bool {
	n, err := strconv.Atoi(p)
	return err == nil && n >= 1 && n <= 65535
}

// invalidURLPort reports whether u carries a malformed or out-of-range port,
// e.g. "https://host:99999/" or "https://host:/".
func invalidURLPort(u *url.URL) bool {
	if strings.HasSuffix(u.Host, ":") {
		return true
	}
	if p := u.Port(); p != "" && !validPort(p) {
		return true
	}
	return false
}
