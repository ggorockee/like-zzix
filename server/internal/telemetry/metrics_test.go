package telemetry

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestNormalize(t *testing.T) {
	cases := map[string]string{"Android": "android", " ios ": "ios", "web": "other", "": "none"}
	for in, want := range cases {
		if got := NormalizePlatform(in); got != want {
			t.Errorf("platform %q: got %q want %q", in, got, want)
		}
	}
	versions := map[string]string{"1.0.0": "1.0.0", "1.2.3+4": "other", "abc": "other", "": "none"}
	for in, want := range versions {
		if got := NormalizeVersion(in); got != want {
			t.Errorf("version %q: got %q want %q", in, got, want)
		}
	}
}

func TestPreCreatedSeries(t *testing.T) {
	m := New("test", "abc")
	m.SetPresets([]string{"a", "b"}, 1)
	// every allowlisted event x {android, ios}
	if got := testutil.CollectAndCount(m.appEvents); got != len(AllowedEvents)*2 {
		t.Fatalf("app events series: got %d", got)
	}
	if got := testutil.CollectAndCount(m.presetEvents); got != len(PresetEvents)*2 {
		t.Fatalf("preset events series: got %d", got)
	}
	if got := testutil.ToFloat64(m.presetsCount.WithLabelValues("published")); got != 2 {
		t.Fatalf("published gauge: got %v", got)
	}
	if got := testutil.ToFloat64(m.presetsCount.WithLabelValues("draft")); got != 1 {
		t.Fatalf("draft gauge: got %v", got)
	}
	if got := testutil.ToFloat64(m.dbUp); got != -1 {
		t.Fatalf("db_up must start at -1 (no database), got %v", got)
	}
}

func TestPresetEventsAreSubsetOfAllowed(t *testing.T) {
	for e := range PresetEvents {
		if !AllowedEvents[e] {
			t.Errorf("%s must also be allowlisted", e)
		}
	}
}
