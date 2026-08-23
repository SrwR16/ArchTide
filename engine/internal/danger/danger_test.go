package danger

import (
	"os"
	"testing"
)

func TestEvaluateGates(t *testing.T) {
	t.Setenv("KUBECONFIG", "")
	t.Setenv("AWS_PROFILE", "")

	// prod context via kubeconfig file
	dir := t.TempDir()
	cfg := dir + "/config"
	os.WriteFile(cfg, []byte("current-context: arn:aws:eks:eu:1:cluster/prod-eu\n"), 0600)
	t.Setenv("KUBECONFIG", cfg)

	v := Evaluate("kubectl delete namespace payments")
	if !v.Triggered || v.RequiredText != "prod-eu" {
		t.Fatalf("prod kubectl delete should gate on context token: %+v", v)
	}

	// non-prod context: kubectl delete allowed
	os.WriteFile(cfg, []byte("current-context: dev-local\n"), 0600)
	if v := Evaluate("kubectl delete pod x"); v.Triggered {
		t.Fatalf("non-prod delete must not gate: %+v", v)
	}

	// host-killer gates even without any context
	if v := Evaluate("sudo mkfs.ext4 /dev/sda"); !v.Triggered {
		t.Fatal("mkfs must always gate")
	}
	if v := Evaluate("rm -rf ~/Documents"); !v.Triggered {
		t.Fatal("rm -rf must always gate")
	}
	// benign commands never gate
	if v := Evaluate("kubectl get pods -A"); v.Triggered {
		t.Fatal("get pods gated?!")
	}
	if v := Evaluate("ls -la"); v.Triggered {
		t.Fatal("ls gated?!")
	}
}

func TestLiveContextOverridesFile(t *testing.T) {
	dir := t.TempDir()
	cfg := dir + "/config"
	os.WriteFile(cfg, []byte("current-context: file-says-dev\n"), 0600)
	t.Setenv("KUBECONFIG", cfg)

	SetLiveContext("")
	if v := Evaluate("kubectl delete ns x"); v.Triggered {
		t.Fatal("file fallback said prod?!")
	}
	SetLiveContext("prod-eu")
	v := Evaluate("kubectl delete ns x")
	if !v.Triggered || v.RequiredText != "prod-eu" {
		t.Fatalf("live ctx gate failed: %+v", v)
	}
	SetLiveContext("")
}
