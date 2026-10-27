// vps-f3-test-app is a disposable app used to validate the VPS deploy pipeline
// (GitHub Actions -> GHCR -> SSH gateway -> project-deploy.sh). It is not a product.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

// version is set at build time with -ldflags "-X main.version=<commit sha>".
var version = "dev"

// release is the human-readable label of this build (bumped on each test version).
const release = "v2"

// healthy is the switch used to publish a deliberately broken version.
var healthy = true

func handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, "vps-f3-test-app %s %s\n", release, version)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		if !healthy {
			http.Error(w, "unhealthy", http.StatusInternalServerError)
			return
		}
		fmt.Fprintln(w, "ok")
	})
	return mux
}

// probe is used as the container healthcheck: the final image has no shell or wget.
func probe(url string) int {
	c := http.Client{Timeout: 2 * time.Second}
	resp, err := c.Get(url)
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	check := flag.Bool("healthcheck", false, "probe /healthz on localhost and exit 0 if healthy")
	addr := flag.String("addr", ":8080", "listen address")
	flag.Parse()
	if *check {
		os.Exit(probe("http://127.0.0.1:8080/healthz"))
	}
	srv := &http.Server{Addr: *addr, Handler: handler(), ReadHeaderTimeout: 5 * time.Second}
	log.Printf("vps-f3-test-app %s listening on %s", version, *addr)
	log.Fatal(srv.ListenAndServe())
}
