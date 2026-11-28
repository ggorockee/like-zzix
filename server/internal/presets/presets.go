// Package presets serves the composition presets bundled with the server.
//
// presets.json is a copy of mobile/assets/presets/presets.json (the app's
// offline fallback); presets_test.go fails when the two drift apart. Until the
// admin console stores presets in a database, this file is the source of truth.
package presets

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
)

//go:embed presets.json
var raw []byte

// LandmarkCount is the BlazePose topology size shared by the app and admin.
const LandmarkCount = 33

// Preset mirrors the app's preset schema (2.1-모바일-앱-설계.md section 5). Unknown
// fields are kept in Extra so the server never drops data the app expects.
type Preset struct {
	ID        string          `json:"id"`
	Category  string          `json:"category"`
	Title     string          `json:"title"`
	SortOrder int             `json:"sort_order"`
	Pose      Pose            `json:"pose"`
	Outline   [][2]float64    `json:"outline"`
	Body      json.RawMessage `json:"-"`
}

// Pose holds normalized landmarks: [x, y, likelihood].
type Pose struct {
	Landmarks [][3]float64 `json:"landmarks"`
}

// Category is a preset group shown as a chip in the app.
type Category struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// Catalog is the validated, immutable preset list.
type Catalog struct {
	version string
	items   []Preset
	byID    map[string]Preset
	etag    string
	listRaw []byte
}

var categoryNames = map[string]string{
	// ids are kept for already stored documents; names follow the app's tabs
	"full_body": "기본/인물",
	"cafe":      "배경/여행",
	"look_back": "포즈/느낌",
	"side":      "특수/2인",
}

// Load parses and validates the embedded presets.
func Load() (*Catalog, error) { return Parse(raw) }

// Embedded returns the bundled preset items (used to seed an empty database).
func Embedded() (version string, items []json.RawMessage, err error) {
	var doc struct {
		Version string            `json:"version"`
		Items   []json.RawMessage `json:"items"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return "", nil, fmt.Errorf("presets: %w", err)
	}
	return doc.Version, doc.Items, nil
}

// Parse validates a list document: {"version": "...", "items": [...]}.
func Parse(data []byte) (*Catalog, error) {
	var doc struct {
		Version string            `json:"version"`
		Items   []json.RawMessage `json:"items"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("presets: %w", err)
	}
	if len(doc.Items) == 0 {
		return nil, errors.New("presets: empty list")
	}
	return Build(doc.Version, doc.Items)
}

// Build validates items and builds a catalog. An empty list is allowed
// (e.g. every preset in the database is still a draft).
func Build(version string, items []json.RawMessage) (*Catalog, error) {
	c := &Catalog{version: version, byID: map[string]Preset{}}
	for i, item := range items {
		p, err := Validate(item)
		if err != nil {
			return nil, fmt.Errorf("presets[%d]: %w", i, err)
		}
		if _, dup := c.byID[p.ID]; dup {
			return nil, fmt.Errorf("presets: duplicate id %q", p.ID)
		}
		c.items = append(c.items, p)
		c.byID[p.ID] = p
	}
	sort.SliceStable(c.items, func(a, b int) bool { return c.items[a].SortOrder < c.items[b].SortOrder })

	bodies := make([]json.RawMessage, len(c.items))
	for i, p := range c.items {
		bodies[i] = p.Body
	}
	list, err := json.Marshal(map[string]any{"version": c.version, "items": bodies})
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(list)
	c.listRaw = list
	c.etag = `"` + hex.EncodeToString(sum[:8]) + `"`
	return c, nil
}

// Validate parses one preset document and checks the schema the app relies on.
func Validate(item json.RawMessage) (Preset, error) {
	var p Preset
	if err := json.Unmarshal(item, &p); err != nil {
		return p, err
	}
	if err := validate(p); err != nil {
		return p, fmt.Errorf("%q: %w", p.ID, err)
	}
	p.Body = item
	return p, nil
}

// ValidID reports whether id is a lowercase slug (used in URLs and metric labels).
func ValidID(id string) bool { return idPattern.MatchString(id) }

var idPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)

// CategoryIDs lists the known category ids.
func CategoryIDs() []string {
	ids := make([]string, 0, len(categoryNames))
	for id := range categoryNames {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func validate(p Preset) error {
	switch {
	case !ValidID(p.ID):
		return errors.New("id must be a lowercase slug (a-z, 0-9, -)")
	case p.Title == "":
		return errors.New("title is required")
	case categoryNames[p.Category] == "":
		return fmt.Errorf("unknown category %q", p.Category)
	case len(p.Pose.Landmarks) != LandmarkCount:
		return fmt.Errorf("landmarks must be %d, got %d", LandmarkCount, len(p.Pose.Landmarks))
	}
	for i, l := range p.Pose.Landmarks {
		if l[2] < 0 || l[2] > 1 {
			return fmt.Errorf("landmark %d likelihood out of range", i)
		}
	}
	for i, o := range p.Outline {
		if o[0] < 0 || o[0] > 1 || o[1] < 0 || o[1] > 1 {
			return fmt.Errorf("outline point %d out of [0,1]", i)
		}
	}
	return nil
}

// ListJSON is the full list response body; its ETag changes when any preset does.
func (c *Catalog) ListJSON() []byte { return c.listRaw }

// ETag is a strong validator for ListJSON.
func (c *Catalog) ETag() string { return c.etag }

// Len is the number of presets.
func (c *Catalog) Len() int { return len(c.items) }

// Get returns one preset's original JSON.
func (c *Catalog) Get(id string) (json.RawMessage, bool) {
	p, ok := c.byID[id]
	return p.Body, ok
}

// Has reports whether id is a known preset (used to bound metric labels).
func (c *Catalog) Has(id string) bool {
	_, ok := c.byID[id]
	return ok
}

// IDs lists preset ids in display order.
func (c *Catalog) IDs() []string {
	ids := make([]string, len(c.items))
	for i, p := range c.items {
		ids[i] = p.ID
	}
	return ids
}

// Categories lists categories that have at least one preset, in display order.
func (c *Catalog) Categories() []Category {
	counts := map[string]int{}
	var order []string
	for _, p := range c.items {
		if counts[p.Category] == 0 {
			order = append(order, p.Category)
		}
		counts[p.Category]++
	}
	out := make([]Category, len(order))
	for i, id := range order {
		out[i] = Category{ID: id, Name: categoryNames[id], Count: counts[id]}
	}
	return out
}
