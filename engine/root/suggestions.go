package root

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/SrwR16/flow-engine/integration"
	"github.com/SrwR16/flow-engine/internal/ai"
	"github.com/SrwR16/flow-engine/internal/config"
	"github.com/SrwR16/flow-engine/internal/flow"
	"github.com/SrwR16/flow-engine/internal/logger"
	"github.com/SrwR16/flow-engine/internal/scoring"
	"github.com/SrwR16/flow-engine/spec"
)

// normalizeVariantCmd groups command variants ("cd x" vs "cd x/") so
// different data sources don't produce duplicate rows.
func normalizeVariantCmd(cmd string) string {
	return strings.TrimRight(strings.TrimSpace(cmd), "/")
}

// MergeResults collects and dedupes suggestions for a query and mode
func MergeResults(query string, mode string) []spec.Suggestion {
	maxSugg := config.Get().UI.MaxSuggestions
	seenIdx := make(map[string]int)
	deduped := []spec.Suggestion{}
	normalizedQuery := strings.TrimSpace(query)

	// add suggestion helper — variant-aware dedup: "cd x" and "cd x/" are
	// the same command from different sources (atuin vs Flow aggregates);
	// keep the stronger row instead of showing both.
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
		k := normalizeVariantCmd(s.Cmd)
		if idx, ok := seenIdx[k]; ok {
			if s.Confidence > deduped[idx].Confidence {
				if deduped[idx].Desc != "" && s.Desc == "" {
					s.Desc = deduped[idx].Desc
				}
				deduped[idx] = s
			} else if deduped[idx].Desc == "" && s.Desc != "" {
				deduped[idx].Desc = s.Desc
			}
			return
		}
		seenIdx[k] = len(deduped)
		deduped = append(deduped, s)
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
			addSuggestion(spec.Suggestion{
				Cmd:        c.Key,
				Desc:       flowDescFor(c),
				Icon:       "history",
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

	injectAISuggestion(&deduped, normalizedQuery)

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

// flowDescFor stays deliberately quiet: professional UIs annotate only
// exceptions. A chronically failing command earns a warning; everything
// else speaks through its ranking position, not a caption.
func flowDescFor(c *flow.Candidate) string {
	t := c.Total()
	if t >= 3 && c.Fail > 0 {
		pct := c.Success * 100 / t
		if pct < 60 {
			return fmt.Sprintf("⚠ %d%% ok", pct)
		}
	}
	return ""
}

func injectAISuggestion(deduped *[]spec.Suggestion, normalizedQuery string) {
	taken := func(cmd string) bool {
		k := normalizeVariantCmd(cmd)
		for _, item := range *deduped {
			if normalizeVariantCmd(item.Cmd) == k {
				return true
			}
		}
		return false
	}
	if aiSugg := GetCurrentAISuggestion(); aiSugg != nil {
		normalizedCmd := strings.TrimSpace(aiSugg.Cmd)
		if normalizedCmd != "" && normalizedCmd != normalizedQuery && strings.HasPrefix(strings.ToLower(normalizedCmd), strings.ToLower(normalizedQuery)) {
			if !taken(aiSugg.Cmd) {
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
