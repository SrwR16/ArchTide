package root

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/versenilvis/iris/integration"
	"github.com/versenilvis/iris/internal/ai"
	"github.com/versenilvis/iris/internal/config"
	"github.com/versenilvis/iris/internal/flow"
	"github.com/versenilvis/iris/internal/logger"
	"github.com/versenilvis/iris/internal/scoring"
	"github.com/versenilvis/iris/spec"
)

// MergeResults collects and dedupes suggestions for a query and mode
func MergeResults(query string, mode string) []spec.Suggestion {
	maxSugg := config.Get().UI.MaxSuggestions
	seen := make(map[string]bool)
	deduped := []spec.Suggestion{}
	normalizedQuery := strings.TrimSpace(query)

	// add suggestion helper to deduplicate
	addSuggestion := func(s spec.Suggestion) {
		normalizedCmd := strings.TrimSpace(s.Cmd)
		if normalizedCmd == "" {
			return
		}
		if s.Source != "alias" && normalizedCmd == normalizedQuery {
			return
		}
		if s.Source == "" {
			s.Source = "spec"
			if s.Confidence == 0 {
				s.Confidence = 50
			}
		}
		if !seen[s.Cmd] {
			seen[s.Cmd] = true
			deduped = append(deduped, s)
		}
	}

	// always call lookup to scan aliases and get spec suggestions
	logger.Debugf("Merge Calling Lookup for '%s'", query)
	cmdResults := spec.Lookup(query)

	if mode == "history" {
		aliases := spec.GetAliasesCopy()
		histResults, _ := integration.SearchHistory(query, aliases)

		// scale confidence based on recency (index in histResults) so the most recent commands stay on top
		baseConf := 75
		for i, h := range histResults {
			conf := max(baseConf-(i*2), 60)

			icon := "history"
			if h.Source == "atuin" {
				icon = "atuin"
			}

			addSuggestion(spec.Suggestion{
				Cmd:        h.Cmd,
				Desc:       h.Source,
				Icon:       icon,
				Source:     h.Source,
				Confidence: conf,
			})
		}
	}

	for _, s := range cmdResults {
		addSuggestion(s)
	}

	// ── Flow provider ────────────────────────────────────────────────────
	// Context-aware candidates from Flow aggregates: directory match,
	// success/failure weighting, recovery history, and "./" script discovery.
	// Candidates that already exist (history/spec/atuin) get their confidence
	// UPGRADED instead of duplicated — one merged list, no separate category.
	if config.Get().Flow.Enabled {
		fstore := flow.GlobalStore()
		cwd := spec.GetCWD()
		var fcands []*flow.Candidate
		if strings.HasPrefix(normalizedQuery, "./") {
			fcands = fstore.SuggestScripts(cwd, normalizedQuery, 5)
		} else if normalizedQuery != "" || mode == "history" {
			fcands = fstore.Suggest(cwd, normalizedQuery, 6)
		}
		for _, c := range fcands {
			conf := int(c.Score)
			if conf > 95 {
				conf = 95
			}
			if conf < 40 {
				continue
			}
			desc := flowDescFor(c)
			if seen[c.Key] {
				// merge: strengthen the existing row rather than duplicate it
				for i := range deduped {
					if deduped[i].Cmd == c.Key && conf > deduped[i].Confidence {
						deduped[i].Confidence = conf
						deduped[i].Desc = desc
					}
				}
				continue
			}
			addSuggestion(spec.Suggestion{
				Cmd:        c.Key,
				Desc:       desc,
				Icon:       "flow",
				Source:     "flow",
				Confidence: conf,
				Priority:   60,
			})
		}
	}

	if mode == "history" && normalizedQuery == "" {
		if len(deduped) > maxSugg {
			return deduped[:maxSugg]
		}
		return deduped
	}

	injectAISuggestion(&deduped, seen, normalizedQuery)

	var finalResults []spec.Suggestion
	if mode == "history" {
		sort.SliceStable(deduped, func(i, j int) bool {
			return deduped[i].Confidence > deduped[j].Confidence
		})
		finalResults = deduped
	} else {
		cwd := spec.GetCWD()
		tokens := spec.Tokenize(query)
		rootCmd := ""
		if len(tokens) > 0 {
			rootCmd = tokens[0]
		}

		ctxTimeout, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()
		store, _ := scoring.GetFrecencyStore()
		signals := scoring.CollectSignals(ctxTimeout, cwd, query, rootCmd, store, getPrevSkeleton())
		scored := scoring.Score(deduped, signals)

		finalResults = make([]spec.Suggestion, 0, len(scored))
		for _, sc := range scored {
			finalResults = append(finalResults, sc.Suggestion)
		}
	}

	if len(finalResults) > maxSugg {
		return finalResults[:maxSugg]
	}
	return finalResults
}

// flowDescFor renders why Flow surfaced a candidate, e.g.
// "in this dir · 83% ok" or "local script · recently modified".
func flowDescFor(c *flow.Candidate) string {
	parts := make([]string, 0, 3)
	failing := false
	for _, r := range c.Reasons {
		switch r {
		case "dir":
			parts = append(parts, "in this dir")
		case "parent_dir":
			parts = append(parts, "nearby project")
		case "recent":
			if !containsStr(parts, "recently used") && !containsStr(parts, "recent") {
				parts = append(parts, "recent")
			}
		case "exec", "script":
			parts = append(parts, "local script")
		case "fails_a_lot":
			failing = true
		}
	}
	if t := c.Total(); t >= 2 && !failing {
		pct := c.Success * 100 / t
		if pct >= 100 {
			parts = append(parts, fmt.Sprintf("%d%% ok", pct))
		} else if pct < 60 {
			parts = append(parts, fmt.Sprintf("⚠ %d%% ok", pct))
		}
	} else if failing {
		parts = append(parts, "⚠ low success")
	}
	return strings.Join(parts, " · ")
}

func containsStr(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func injectAISuggestion(deduped *[]spec.Suggestion, seen map[string]bool, normalizedQuery string) {
	if aiSugg := GetCurrentAISuggestion(); aiSugg != nil {
		normalizedCmd := strings.TrimSpace(aiSugg.Cmd)
		if normalizedCmd != "" && normalizedCmd != normalizedQuery && strings.HasPrefix(strings.ToLower(normalizedCmd), strings.ToLower(normalizedQuery)) {
			if !seen[aiSugg.Cmd] {
				seen[aiSugg.Cmd] = true
				*deduped = append(*deduped, *aiSugg)
			} else {
				for i, item := range *deduped {
					if item.Cmd == aiSugg.Cmd && aiSugg.Confidence > item.Confidence {
						(*deduped)[i].Confidence = aiSugg.Confidence
						if (*deduped)[i].Source == "" || (*deduped)[i].Source == "spec" || (*deduped)[i].Source == "history" {
							(*deduped)[i].Source = "ai"
						}
						break
					}
				}
			}
		}
	}
}

var (
	aiEngine     *ai.AIEngine
	aiEngineOnce sync.Once
)

func GetAIEngine() *ai.AIEngine {
	aiEngineOnce.Do(func() {
		aiEngine = ai.NewAIEngine(nil)
		for _, p := range ai.DefaultProviders {
			aiEngine.RegisterProvider(p)
		}
	})
	return aiEngine
}

var (
	currentAISugg *spec.Suggestion
	aiSuggMu      sync.RWMutex
)

func SetCurrentAISuggestion(sugg *spec.Suggestion) {
	aiSuggMu.Lock()
	defer aiSuggMu.Unlock()
	currentAISugg = sugg
}

func GetCurrentAISuggestion() *spec.Suggestion {
	aiSuggMu.RLock()
	defer aiSuggMu.RUnlock()
	return currentAISugg
}
