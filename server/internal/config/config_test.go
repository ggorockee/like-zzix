package config

import "testing"

func TestDevLoginBlockedOutsideLocal(t *testing.T) {
	t.Setenv("ADMIN_DEV_EMAIL", "dev@example.com")
	if _, err := Load(); err == nil {
		t.Fatal("ADMIN_DEV_EMAIL without APP_ENV=local must fail")
	}
	t.Setenv("APP_ENV", "local")
	if _, err := Load(); err != nil {
		t.Fatalf("local dev login: %v", err)
	}
}

func TestDatabaseURLEscapesPassword(t *testing.T) {
	c := Config{PostgresHost: "10.0.0.1", PostgresPort: "5432", PostgresUser: "u",
		PostgresPassword: "p@ss/word", PostgresDB: "like_zzix", PostgresSSLMode: "disable"}
	want := "postgres://u:p%40ss%2Fword@10.0.0.1:5432/like_zzix?sslmode=disable"
	if got := c.DatabaseURL(); got != want {
		t.Fatalf("got %s", got)
	}
}

func TestAdminEnabled(t *testing.T) {
	base := Config{AdminEmails: "a@x", GoogleClientID: "cid"}
	if base.AdminEnabled() {
		t.Fatal("no storage → disabled")
	}
	withDB := base
	withDB.PostgresHost = "db"
	if !withDB.AdminEnabled() {
		t.Fatal("db + client id + emails → enabled")
	}
	noEmails := withDB
	noEmails.AdminEmails = ""
	if noEmails.AdminEnabled() {
		t.Fatal("no allowlist → disabled")
	}
}
