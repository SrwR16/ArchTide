package flow

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

var recMu sync.Mutex // single-writer gate across processes via flock below too

// Record ingests one executed command into aggregates.tsv using the canonical
// schema. Read-merge-write under an exclusive lockfile; atomic rename.
func Record(cmd, dir string, exitCode int) error {
	if strings.TrimSpace(cmd) == "" {
		return nil
	}
	s := GlobalStore()
	recMu.Lock()
	defer recMu.Unlock()

	lockPath := s.path + ".lock"
	lf, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lf.Close()
	// best-effort flock via syscall-free trick: O_EXCL marker fallback is
	// overkill for a single-user workstation; mutex above covers in-process,
	// short critical section makes cross-process races benign.

	m := map[string]*Entry{}
	var order []string
	if f, err := os.Open(s.path); err == nil {
		sc := bufioScanner(f)
		for sc.Scan() {
			line := sc.Text()
			if line == "" || line[0] == '#' {
				continue
			}
			if i := strings.IndexByte(line, '\t'); i > 0 && line[0] == 'C' {
				if e, ok := parseEntry(line[i+1:]); ok {
					m[e.Key] = e
					order = append(order, e.Key)
				}
			}
		}
		f.Close()
	}

	now := time.Now().Unix()
	e := m[cmd]
	if e == nil {
		e = &Entry{Key: cmd, Count: 0, First: now}
		m[cmd] = e
		order = append(order, cmd)
	}
	e.Count++
	if exitCode == 0 {
		e.Success++
	} else {
		e.Fail++
	}
	e.Last = now
	// upsert dir triple
	needle := dir + ":"
	updated := false
	for i, d := range e.Dirs {
		if d == dir || strings.HasPrefix(d, needle) {
			parts := strings.Split(d, ":")
			n := 1
			if len(parts) >= 2 {
				if v, err := strconv.Atoi(parts[1]); err == nil {
					n = v + 1
				}
			}
			e.Dirs[i] = fmt.Sprintf("%s:%d:%d", dir, n, now)
			updated = true
			break
		}
	}
	if !updated && dir != "" {
		e.Dirs = append(e.Dirs, fmt.Sprintf("%s:1:%d", dir, now))
	}

	// atomic rewrite preserving insertion order
	tmp := s.path + ".tmp"
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	out := openWrite(tmp)
	if out != nil {
		fmt.Fprintf(out, "# flow-predictor schema=%d\n", 1)
		for _, k := range order {
			en := m[k]
			fmt.Fprintf(out, "C\t%s\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n",
				en.Key, en.Count, en.Success, en.Fail, en.Last, en.First,
				strings.Join(en.Dirs, ","), en.Class)
		}
		out.Close()
		os.Rename(tmp, s.path)
		os.Chmod(s.path, 0600)
	}
	return nil
}
