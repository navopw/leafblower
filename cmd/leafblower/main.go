package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/navopw/leafblower/internal/api"
	"github.com/navopw/leafblower/internal/delete"
	"github.com/navopw/leafblower/internal/scan"
	"github.com/navopw/leafblower/internal/web"
)

func main() {
	port := flag.Int("port", 8000, "port to listen on")
	flag.Parse()

	scanMgr := scan.NewManager()
	delSvc, err := delete.NewService()
	if err != nil {
		log.Fatal(err)
	}

	staticFS := web.StaticFS()
	router := api.NewRouter(scanMgr, delSvc, staticFS)

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	fmt.Fprintf(os.Stderr, "Leafblower listening on http://%s\n", addr)

	server := &http.Server{
		Addr:    addr,
		Handler: router,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)

	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	<-quit
	log.Println("Shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
}
