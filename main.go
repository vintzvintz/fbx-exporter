package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/vintzvintz/fbx-exporter/fbx"
	"github.com/vintzvintz/fbx-exporter/log"
)

func usage() {
	fmt.Fprintf(flag.CommandLine.Output(),
		"Usage: %s [options] <api_token_file>\n"+
			"\n"+
			"api_token_file: file to store the token for the API\n"+
			"\n"+
			"options:\n",
		os.Args[0])
	flag.PrintDefaults()
}

func main() {
	flag.Usage = usage
	debugPtr := flag.Bool("debug", false, "enable the debug mode")
	hostDetailsPtr := flag.Bool("hostDetails", false, "get details about the hosts connected to wifi and ethernet. This increases the number of metrics")
	httpDiscoveryPtr := flag.Bool("httpDiscovery", false, "use http://mafreebox.freebox.fr/api_version to discover the Freebox at the first run (by default: use mDNS)")
	apiVersionPtr := flag.Int("apiVersion", 0, "Force the API version (by default use the latest one)")
	listenPtr := flag.String("listen", ":9091", "listen to address")
	goMetricsPtr := flag.Bool("goMetrics", false, "enable Go runtime metrics export")
	flag.Parse()

	args := flag.Args()
	if len(args) < 1 {
		fmt.Fprintf(flag.CommandLine.Output(), "ERROR: api_token_file not defined\n")
		usage()
		os.Exit(1)
	} else if len(args) > 1 {
		fmt.Fprintf(flag.CommandLine.Output(), "ERROR: too many arguments\n")
		usage()
		os.Exit(1)
	}
	if *debugPtr {
		log.InitDebug()
	} else {
		log.Init()
	}
	discovery := fbx.FreeboxDiscoveryMDNS
	if *httpDiscoveryPtr {
		discovery = fbx.FreeboxDiscoveryHTTP
	}

	collector := NewCollector(args[0], discovery, *apiVersionPtr, *hostDetailsPtr, *debugPtr)
	defer collector.Close()

	// Create custom registry to avoid default Go metrics
	registry := prometheus.NewRegistry()
	registry.MustRegister(collector)

	if *goMetricsPtr {
		registry.MustRegister(collectors.NewGoCollector())
		registry.MustRegister(collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
	}

	http.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	log.Info.Println("Listen to", *listenPtr)
	log.Error.Println(http.ListenAndServe(*listenPtr, nil))
}
