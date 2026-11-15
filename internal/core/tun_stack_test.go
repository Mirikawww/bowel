package core

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/oboo/moho/internal/routes"
	"gopkg.in/yaml.v3"
)

func TestMipsTunConfig(t *testing.T) {
	if !slices.Contains(TunStacks, "mips") {
		t.Fatal("MIPS is missing from the settings and CLI stack choices")
	}
	opts := DefaultOptions.Clone()
	opts.TunStack = "mips"
	if err := opts.Validate(); err != nil {
		t.Fatal(err)
	}
	raw, err := BuildConfig(Input{Routes: routes.Template(), Mode: "rule", MixedPort: 17899,
		LogLevel: "info", TestURL: "https://www.gstatic.com/generate_204", ProbePort: 17900,
		Tun: true, Options: opts})
	if err != nil {
		t.Fatal(err)
	}
	var cfg map[string]any
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	tun := cfg["tun"].(map[string]any)
	if tun["stack"] != "mips" || tun["enable"] != true || tun["auto-route"] != true {
		t.Fatalf("MIPS TUN config = %v", tun)
	}
	if DefaultOptions.TunStack != "mixed" {
		t.Fatal("adding a stack changed the desktop default")
	}
}

// Validate the generated MIPS config with the bundled executable, without
// creating an adapter, asking for elevation, or changing network settings.
func TestMipsTunPassesCore(t *testing.T) {
	bin := coreBin(t)
	dir := t.TempDir()
	geo(t, dir)
	opts := DefaultOptions.Clone()
	opts.TunStack = "mips"
	raw, err := BuildConfig(Input{Routes: routes.Template(), Mode: "rule", MixedPort: 17899,
		LogLevel: "info", TestURL: "https://www.gstatic.com/generate_204", ProbePort: 17900,
		Tun: true, Options: opts})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "mips.yaml")
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	m, err := New(bin, dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := m.Test(path); err != nil {
		t.Fatalf("bundled mihomo rejected MIPS: %v", err)
	}
}
