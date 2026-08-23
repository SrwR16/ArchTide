package danger

import (
	"fmt"
	"strings"
)

// GateSession holds live state while a confirmation is pending.
type GateSession struct {
	Verdict
	Cmd      string // full command awaiting execution
	Typed    string // confirmation token being typed
	SegLen   int    // visible length of the rendered inline strip
	Attempts int    // wrong-token count
}

// NewSession starts a confirmation session for a gated command.
func NewSession(v Verdict, cmd string) *GateSession {
	return &GateSession{Verdict: v, Cmd: cmd}
}

const (
	ansiReset = "\033[0m"
	ansiRed   = "\033[91m"
	ansiBold  = "\033[1m"
	ansiDim   = "\033[90m"
)

// StripANSI returns visible length of s.
func visibleLen(s string) int {
	n := 0
	inEsc := false
	for _, r := range s {
		if inEsc {
			if r == 'm' {
				inEsc = false
			}
			continue
		}
		if r == '\033' {
			inEsc = true
			continue
		}
		n++
	}
	return n
}

// Render builds the inline strip appended at the cursor. Caller tracks
// SegLen = visibleLen(rendered) and erases with EraseSeq().
func (g *GateSession) Render(wrong bool) string {
	tok := g.RequiredText
	var b strings.Builder
	b.WriteString(ansiRed + ansiBold + " ⛔ PROD · type \"" + tok + "\"")
	if g.Reason != "" {
		b.WriteString(" · " + g.Reason)
	}
	b.WriteString(ansiReset)
	if wrong {
		b.WriteString(ansiRed + ansiBold + " ✗ mismatch" + ansiReset)
	}
	b.WriteString(ansiDim + " — type it + Enter · Esc cancels" + ansiReset)
	if g.Typed != "" {
		b.WriteString(ansiBold + "  " + g.Typed + ansiReset)
	}
	return b.String()
}

// EraseSeq returns the escape sequence removing a strip of visible length n
// from the current cursor position (cursor ends where it was before).
func EraseSeq(n int) string {
	if n <= 0 {
		return ""
	}
	return strings.Repeat("\b", n) + "\033[0K"
}

// Feed processes one printable rune; returns false when input full-ish.
func (g *GateSession) Feed(r rune) {
	g.Typed += string(r)
}

// VisibleLen exports the ANSI-aware length counter.
func VisibleLen(s string) int { return visibleLen(s) }

func (g *GateSession) Match() bool {
	return g.Typed == g.RequiredText
}

// DebugString is used by tests.
func (g *GateSession) DebugString() string {
	return fmt.Sprintf("gate req=%q typed=%q", g.RequiredText, g.Typed)
}
