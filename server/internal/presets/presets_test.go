package presets

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestEmbeddedPresetsAreValid(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.Len() < 2 {
		t.Fatalf("want at least 2 presets, got %d", c.Len())
	}
	if !strings.HasPrefix(c.ETag(), `"`) {
		t.Fatalf("etag must be quoted: %s", c.ETag())
	}
	if got := len(c.Categories()); got != 2 {
		t.Fatalf("want 2 categories, got %d", got)
	}
}

// The server copy must match the app's bundled fallback.
func TestEmbeddedPresetsMatchMobileAsset(t *testing.T) {
	mobile, err := os.ReadFile("../../../mobile/assets/presets/presets.json")
	if err != nil {
		t.Skipf("mobile asset not found (server built alone): %v", err)
	}
	if !bytes.Equal(mobile, raw) {
		t.Fatal("server/internal/presets/presets.json differs from mobile/assets/presets/presets.json; copy the mobile file")
	}
}

func TestParseRejectsBadPresets(t *testing.T) {
	landmarks := "[" + strings.TrimSuffix(strings.Repeat("[0.5,0.5,0.9],", 33), ",") + "]"
	cases := map[string]string{
		"wrong landmark count": `{"items":[{"id":"a","category":"side","title":"t","pose":{"landmarks":[[0,0,1]]}}]}`,
		"unknown category":     `{"items":[{"id":"a","category":"nope","title":"t","pose":{"landmarks":` + landmarks + `}}]}`,
		"duplicate id": `{"items":[{"id":"a","category":"side","title":"t","pose":{"landmarks":` + landmarks + `}},` +
			`{"id":"a","category":"side","title":"t","pose":{"landmarks":` + landmarks + `}}]}`,
		"outline out of range": `{"items":[{"id":"a","category":"side","title":"t","outline":[[1.2,0]],"pose":{"landmarks":` + landmarks + `}}]}`,
		"empty":                `{"items":[]}`,
	}
	for name, doc := range cases {
		if _, err := Parse([]byte(doc)); err == nil {
			t.Errorf("%s: want error", name)
		}
	}
}

func TestListIsSortedAndETagChangesWithContent(t *testing.T) {
	landmarks := "[" + strings.TrimSuffix(strings.Repeat("[0.5,0.5,0.9],", 33), ",") + "]"
	doc := func(title string) []byte {
		return []byte(`{"version":"v","items":[` +
			`{"id":"b","category":"side","title":"` + title + `","sort_order":20,"pose":{"landmarks":` + landmarks + `}},` +
			`{"id":"a","category":"cafe","title":"t","sort_order":10,"pose":{"landmarks":` + landmarks + `}}]}`)
	}
	c1, err := Parse(doc("x"))
	if err != nil {
		t.Fatal(err)
	}
	if ids := c1.IDs(); ids[0] != "a" || ids[1] != "b" {
		t.Fatalf("want sort_order order, got %v", ids)
	}
	c2, _ := Parse(doc("y"))
	if c1.ETag() == c2.ETag() {
		t.Fatal("etag must change when content changes")
	}
	if !c1.Has("a") || c1.Has("zzz") {
		t.Fatal("Has mismatch")
	}
}
