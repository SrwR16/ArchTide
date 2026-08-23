// Package danger implements Flow's production safety gate (§8): destructive
// commands aimed at production contexts are intercepted before the shell
// ever sees Enter, and require explicit typed confirmation.
package danger

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Verdict describes a gate decision.
type Verdict struct {
	Triggered    bool
	RequiredText string // what the user must type ("yes", or the context name)
	Reason       string
	ProdContext  string
}

var (
	// Destructive patterns: command prefixes/substrings that mutate state in
	// ways worth stopping for. Matched case-insensitively as substrings.
	patterns = []struct {
		re     *regexp.Regexp
		reason string
	}{
		{regexp.MustCompile(`(?i)\brm\s+(-[a-z]*[rf][a-z]*\s+)+`), "recursive/forced delete"},
		{regexp.MustCompile(`(?i)\bmkfs(\.\w+)?\b`), "filesystem format"},
		{regexp.MustCompile(`(?i)\bdd\s+if=`), "raw disk write"},
		{regexp.MustCompile(`(?i)\b(kubectl|k)\s+delete\b`), "kubernetes delete"},
		{regexp.MustCompile(`(?i)\bterraform(\.tf)?\s+destroy\b`), "terraform destroy"},
		{regexp.MustCompile(`(?i)\btofu\s+destroy\b`), "tofu destroy"},
		{regexp.MustCompile(`(?i)\bhelm\s+(uninstall|del)\b`), "helm uninstall"},
		{regexp.MustCompile(`(?i)\baws\s+\w+\s+(delete|terminate)\b`), "AWS destructive API"},
		{regexp.MustCompile(`(?i)\bgit\s+push\b[^\n|;&]*--force\b`), "force push"},
		{regexp.MustCompile(`(?i):\(\)\s*\{`), "fork bomb pattern"},
	}

	prodRe = regexp.MustCompile(`(?i)prod`)
)

// liveContext is pushed by the shell over the FD protocol because env
// exports made inside zsh never reach this (parent) process.
var liveContext string

// SetLiveContext records the shell-reported kube context.
func SetLiveContext(ctx string) { liveContext = strings.TrimSpace(ctx) }

// CurrentKubeContext prefers the live shell-reported value, then falls back
// to reading current-context from $KUBECONFIG / ~/.kube/config
// with a minimal parser — no YAML library, no subprocess.
func CurrentKubeContext() string {
	if liveContext != "" {
		return liveContext
	}
	cfg := os.Getenv("KUBECONFIG")
	if cfg == "" {
		if home, err := os.UserHomeDir(); err == nil {
			cfg = filepath.Join(home, ".kube", "config")
		}
	}
	data, err := os.ReadFile(cfg)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "current-context:") {
			v := strings.TrimPrefix(t, "current-context:")
			v = strings.Trim(strings.TrimSpace(v), `"'`)
			return v
		}
	}
	return ""
}

// IsProd reports whether a name matches the production regex.
func IsProd(name string) bool {
	if name == "" {
		return false
	}
	rx := os.Getenv("FLOW_DANGER_REGEX")
	if rx == "" {
		rx = "prod"
	}
	re, err := regexp.Compile(`(?i)` + rx)
	if err != nil {
		re = prodRe
	}
	return re.MatchString(name)
}

// Evaluate decides whether cmd must pass through the confirmation gate.
//
// Rules:
//   - destructive patterns on their own are allowed in non-prod contexts
//     (developers delete test pods constantly) EXCEPT host-killers
//     (rm -rf on / or ~, mkfs, dd, fork bomb) which always gate;
//   - any destructive pattern combined with a prod-sounding context gates.
func Evaluate(cmd string) Verdict {
	trimmed := strings.TrimSpace(cmd)
	if trimmed == "" {
		return Verdict{}
	}

	ctx := CurrentKubeContext()
	// UNCONDITIONAL debug while Phase 8 stabilizes: every evaluation is
	// logged (engine env cannot see shell exports, so env-gating the debug
	// silently disabled it). Capped at ~1MB.
	msg := fmt.Sprintf("[danger] cmd=%q liveCtx=%q resolvedCtx=%q aws=%q\n",
		trimmed, liveContext, ctx, os.Getenv("AWS_PROFILE"))
	if st, err := os.Stat("/tmp/flow-danger-debug.log"); err == nil && st.Size() > 1_000_000 {
		os.Remove("/tmp/flow-danger-debug.log")
	}
	if f, err := os.OpenFile("/tmp/flow-danger-debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600); err == nil {
		f.WriteString(msg)
		f.Close()
	}
	prodCtx := ""
	if IsProd(ctx) {
		prodCtx = ctx
	}
	awsProf := os.Getenv("AWS_PROFILE")
	if prodCtx == "" && IsProd(awsProf) {
		prodCtx = awsProf
	}

	var reason string
	for _, p := range patterns {
		if p.re.MatchString(trimmed) {
			reason = p.reason
			break
		}
	}
	if reason == "" {
		return Verdict{}
	}

	// Always-gate class: host-killers AND recursive/forced deletes —
	// these confirm even outside production contexts.
	hostKiller := regexp.MustCompile(`(?i)(mkfs|\bdd\s+if=|:\(\)\s*\{|\brm\s+(-[a-z]*[rf][a-z]*[[:space:]]+)+)`)
	if hostKiller.MatchString(trimmed) {
		req := "yes"
		if prodCtx != "" {
			req = safeToken(prodCtx)
		}
		return Verdict{Triggered: true, RequiredText: req, Reason: reason, ProdContext: prodCtx}
	}

	if prodCtx != "" {
		return Verdict{
			Triggered:    true,
			RequiredText: safeToken(prodCtx),
			Reason:       reason,
			ProdContext:  prodCtx,
		}
	}
	return Verdict{}
}

// safeToken reduces a context/profile name to the short token the user must
// type: the last path-ish segment (e.g. "arn:…:cluster/prod-eu" → "prod-eu").
func safeToken(name string) string {
	name = strings.TrimSpace(name)
	if i := strings.LastIndexAny(name, ":/"); i >= 0 && i+1 < len(name) {
		name = name[i+1:]
	}
	if name == "" {
		name = "yes"
	}
	return name
}
