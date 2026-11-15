package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/oboo/moho/internal/mihomo"
	"github.com/oboo/moho/internal/settings"
	"gopkg.in/yaml.v3"
)

func TestPhoneTunStackSelection(t *testing.T) {
	x := testBridge(t)
	ctx := context.Background()
	// Older phone settings inherit the desktop's mixed default, but have
	// always run gVisor. The settings page must describe that actual stack.
	if got := x.settingsData().TunStack; got != "gvisor" {
		t.Fatalf("phone default shown as %q, want gvisor", got)
	}
	if err := os.WriteFile(filepath.Join(x.dir, tunFDFile), []byte("42\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, stack := range []string{"mips", "gvisor"} {
		if err := x.setSettings(ctx, json.RawMessage(fmt.Sprintf(`{"tunStack":%q}`, stack))); err != nil {
			t.Fatal(err)
		}
		st, err := openSettings(x.dir)
		if err != nil {
			t.Fatal(err)
		}
		x.set = st
		if got := x.settingsData().TunStack; got != stack {
			t.Fatalf("saved stack = %q, want %q", got, stack)
		}
		data, err := json.Marshal(x.settingsData())
		if err != nil {
			t.Fatal(err)
		}
		var page map[string]any
		if err := json.Unmarshal(data, &page); err != nil || page["tunStack"] != stack {
			t.Fatalf("settings page JSON = %s: %v", data, err)
		}
		tun := config(t, x)["tun"].(map[string]any)
		if tun["stack"] != stack || fmt.Sprint(tun["file-descriptor"]) != "42" || tun["mtu"] != 1500 {
			t.Fatalf("phone config lost stack/descriptor/MTU: %v", tun)
		}
		if tun["auto-route"] != false || tun["auto-detect-interface"] != false || tun["strict-route"] != false {
			t.Fatalf("phone routing overrides lost: %v", tun)
		}
	}
	if err := x.setSettings(ctx, json.RawMessage(`{"tunStack":"invalid"}`)); err == nil {
		t.Fatal("unknown stack accepted")
	}
	if got := x.set.Get().TunStack; got != "gvisor" {
		t.Fatalf("invalid patch changed saved stack to %q", got)
	}
	if err := x.resetCore(ctx); err != nil {
		t.Fatal(err)
	}
	if got := x.settingsData().TunStack; got != "gvisor" {
		t.Fatalf("reset stack = %q, want gvisor", got)
	}
	if got := config(t, x)["tun"].(map[string]any)["stack"]; got != "gvisor" {
		t.Fatalf("reset config stack = %v, want gvisor", got)
	}
}

func TestPhoneMipsNeedsReload(t *testing.T) {
	old := settings.Defaults.Clone()
	next := old.Clone()
	next.TunStack = "mips"
	if coreSame(old, next) {
		t.Fatal("changing the stack must reload the running core")
	}
}

// The live settings path must reload MIPS using the existing VPN descriptor,
// and keep both the saved and generated config when a later switch is refused.
func TestPhoneTunStackReloadAndRollback(t *testing.T) {
	x := testBridge(t)
	if err := os.WriteFile(filepath.Join(x.dir, tunFDFile), []byte("42\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	seen := make(chan string, 2)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPut && r.URL.Path == "/configs" {
			var body struct {
				Path string `json:"path"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			raw, err := os.ReadFile(body.Path)
			if err != nil {
				t.Error(err)
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			var cfg map[string]any
			if err := yaml.Unmarshal(raw, &cfg); err != nil {
				t.Error(err)
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			tun := cfg["tun"].(map[string]any)
			if fmt.Sprint(tun["file-descriptor"]) != "42" {
				t.Errorf("reload lost VPN descriptor: %v", tun)
			}
			stack := tun["stack"].(string)
			seen <- stack
			if stack == "gvisor" {
				http.Error(w, `{"message":"stack refused"}`, http.StatusBadRequest)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		_, _ = w.Write([]byte(`{"proxies":{},"providers":{}}`))
	}))
	defer srv.Close()
	x.client = mihomo.NewTCP(strings.TrimPrefix(srv.URL, "http://"), "")
	ctx := context.Background()
	if err := x.setSettings(ctx, json.RawMessage(`{"tunStack":"mips"}`)); err != nil {
		t.Fatal(err)
	}
	if stack := <-seen; stack != "mips" {
		t.Fatalf("live core received %q", stack)
	}
	if err := x.setSettings(ctx, json.RawMessage(`{"tunStack":"gvisor"}`)); err == nil {
		t.Fatal("refused switch reported success")
	}
	if stack := <-seen; stack != "gvisor" {
		t.Fatalf("live core received %q", stack)
	}
	st, err := openSettings(x.dir)
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Get().TunStack; got != "mips" {
		t.Fatalf("rollback left saved stack %q", got)
	}
	if got := config(t, x)["tun"].(map[string]any)["stack"]; got != "mips" {
		t.Fatalf("rollback left generated stack %v", got)
	}
}
