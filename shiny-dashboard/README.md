# Lemonade Stand R Shiny Dashboard

An R Shiny dashboard that visualizes guardrails metrics from the Lemonade Stand Assistant. This dashboard reads from the same Prometheus `/metrics` endpoint as Grafana and displays the same metrics.

## Features

- **Total Requests** - Counter showing all requests processed
- **Input Blocked** - Requests blocked before reaching the LLM
- **Answers Blocked** - LLM responses blocked by output guardrails
- **Approved Requests** - Requests that passed all guardrails
- **Detections by Detector** - Bar chart showing which guardrails triggered

Auto-refreshes every 5 seconds.

## Configuration

Set these environment variables:

```bash
METRICS_URL=http://lemonade-stand-app:8080/metrics  # Metrics endpoint
REFRESH_INTERVAL=5  # Refresh interval in seconds
```

## Local Development

### Run locally with Docker/Podman

```bash
# Build the container
podman build -t shiny-dashboard .

# Run it
podman run -p 3838:3838 \
  -e METRICS_URL=http://localhost:8080/metrics \
  shiny-dashboard

# Access at http://localhost:3838
```

### Run locally with R

```bash
# Install dependencies
R -e "install.packages(c('shiny', 'httr', 'stringr', 'bslib'))"

# Set metrics URL
export METRICS_URL=http://localhost:8080/metrics

# Run the app
R -e "shiny::runApp('app.R', port=3838, host='0.0.0.0')"
```

## Deploy to OpenShift

### Build and Push Container

```bash
# Build
podman build -t quay.io/YOUR_ORG/shiny-dashboard:latest .

# Push
podman push quay.io/YOUR_ORG/shiny-dashboard:latest
```

### Deploy

```bash
# Create deployment
oc apply -f deployment.yaml

# Expose route
oc expose svc/shiny-dashboard

# Get URL
echo https://$(oc get route shiny-dashboard --template='{{.spec.host}}')
```

## Metrics Format

The dashboard reads Prometheus metrics in this format:

```
guardrail_requests_total{source="chat"} 150
guardrail_detections_by_direction{direction="input",source="chat"} 25
guardrail_detections_by_direction{direction="output",source="chat"} 3
guardrail_detections_by_detector{detector="hap",source="chat"} 10
guardrail_detections_by_detector{detector="language",source="chat"} 8
guardrail_detections_by_detector{detector="prompt_injection",source="chat"} 5
guardrail_detections_by_detector{detector="regex_fruit",source="chat"} 2
```

## Comparison with Grafana

This Shiny dashboard replicates the same Prometheus queries used by Grafana:

| Metric | Prometheus Query | Shiny Implementation |
|--------|------------------|---------------------|
| Total Requests | `sum(guardrail_requests_total)` | Parsed from metrics |
| Input Blocked | `sum(guardrail_detections_by_direction{direction="input"})` | Parsed from metrics |
| Output Blocked | `sum(guardrail_detections_by_direction{direction="output"})` | Parsed from metrics |
| Approved | `sum(guardrail_requests_total) - sum(guardrail_detections_total)` | Calculated |
| By Detector | `sum by (detector) (guardrail_detections_by_detector)` | Parsed and sorted |

## Architecture

```
┌─────────────────┐
│ Lemonade Stand  │
│   FastAPI App   │
│                 │
│  /metrics       │◄─────┐
└─────────────────┘      │
                         │ HTTP GET every 5s
┌─────────────────┐      │
│   R Shiny       │──────┘
│   Dashboard     │
│                 │
│  Port 3838      │
└─────────────────┘
```

The dashboard:
1. Fetches `/metrics` endpoint every 5 seconds
2. Parses Prometheus format metrics
3. Updates counter displays
4. Renders bar chart for detections by detector
