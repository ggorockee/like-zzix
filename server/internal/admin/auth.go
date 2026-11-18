// Package admin authenticates admin console users.
//
// Login: the console obtains a Google ID token (Google Identity Services) and
// sends it once; the server verifies it, checks the allowlist (superusers) and
// issues an opaque session cookie. Only the SHA-256 of the session token is stored.
package admin

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"

	"github.com/ggorockee/like-zzix/server/internal/store"
)

var (
	// ErrInvalidToken means the ID token is malformed, expired, for another client or unverified.
	ErrInvalidToken = errors.New("invalid id token")
	// ErrNotAllowed means the Google account is valid but not an admin.
	ErrNotAllowed = errors.New("account not allowed")
)

// GoogleCertsURL is Google's JWKS endpoint for ID tokens.
const GoogleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

// Verifier turns a Google ID token into a verified email.
type Verifier interface {
	Verify(ctx context.Context, idToken string) (email string, err error)
}

// Allowlist holds superuser emails (lowercase).
type Allowlist map[string]bool

// ParseAllowlist parses a comma-separated email list.
func ParseAllowlist(csv string) Allowlist {
	a := Allowlist{}
	for _, e := range strings.Split(csv, ",") {
		if e = strings.ToLower(strings.TrimSpace(e)); e != "" {
			a[e] = true
		}
	}
	return a
}

// Allowed reports whether email may use the console.
func (a Allowlist) Allowed(email string) bool { return a[strings.ToLower(strings.TrimSpace(email))] }

// GoogleVerifier validates Google ID tokens against the published JWKS.
type GoogleVerifier struct {
	clientID string
	keyfunc  jwt.Keyfunc
	now      func() time.Time
}

// NewGoogleVerifier fetches Google's signing keys (refreshed in the background).
func NewGoogleVerifier(ctx context.Context, clientID string) (*GoogleVerifier, error) {
	if clientID == "" {
		return nil, errors.New("admin: GOOGLE_CLIENT_ID is empty")
	}
	k, err := keyfunc.NewDefaultCtx(ctx, []string{GoogleCertsURL})
	if err != nil {
		return nil, fmt.Errorf("admin: google jwks: %w", err)
	}
	return &GoogleVerifier{clientID: clientID, keyfunc: k.Keyfunc, now: time.Now}, nil
}

type googleClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	jwt.RegisteredClaims
}

// Verify checks signature (RS256), audience, issuer, expiry and email_verified.
func (v *GoogleVerifier) Verify(_ context.Context, idToken string) (string, error) {
	var c googleClaims
	_, err := jwt.ParseWithClaims(idToken, &c, v.keyfunc,
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithAudience(v.clientID),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(v.now),
	)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	if c.Issuer != "accounts.google.com" && c.Issuer != "https://accounts.google.com" {
		return "", fmt.Errorf("%w: issuer %q", ErrInvalidToken, c.Issuer)
	}
	if !c.EmailVerified || c.Email == "" {
		return "", fmt.Errorf("%w: email not verified", ErrInvalidToken)
	}
	return strings.ToLower(c.Email), nil
}

// Sessions issues and resolves session cookies backed by the store.
type Sessions struct {
	Store store.Store
	TTL   time.Duration
	Now   func() time.Time
}

// Create returns a new random session token for email.
func (s *Sessions) Create(ctx context.Context, email string) (token string, expires time.Time, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, err
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	expires = s.now().Add(s.TTL)
	return token, expires, s.Store.CreateSession(ctx, Hash(token), store.Session{Email: email, ExpiresAt: expires})
}

// Lookup returns the email of a live session.
func (s *Sessions) Lookup(ctx context.Context, token string) (string, error) {
	if token == "" {
		return "", store.ErrNotFound
	}
	sess, err := s.Store.GetSession(ctx, Hash(token))
	if err != nil {
		return "", err
	}
	if !s.now().Before(sess.ExpiresAt) {
		_ = s.Store.DeleteSession(ctx, Hash(token))
		return "", store.ErrNotFound
	}
	return sess.Email, nil
}

// Delete ends a session.
func (s *Sessions) Delete(ctx context.Context, token string) error {
	return s.Store.DeleteSession(ctx, Hash(token))
}

func (s *Sessions) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Hash is what the store keeps instead of the token.
func Hash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}
