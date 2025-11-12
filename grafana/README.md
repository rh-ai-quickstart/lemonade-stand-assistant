# Grafana Dashboard Helm Chart

This Helm chart deploys Grafana with monitoring dashboards for the Lemonade Stand Assistant guardrails metrics.

## Prerequisites

- OpenShift cluster with cluster-monitoring enabled
- Grafana Operator installed (or set `operator: true` in values.yaml to install it)
- Guardrails metrics being exposed by the Lemonade Stand Assistant

## Installation

### Install the Grafana Operator (if not already installed)

The chart can automatically install the Grafana Operator by setting `operator: true` in values.yaml (enabled by default).

### Deploy Grafana and Dashboards

```bash
# Set the namespace (should match your lemonade-stand-assistant namespace)
NAMESPACE="lemonade-stand-assistant"

# Install the helm chart
helm install lemonade-grafana ./grafana --namespace ${NAMESPACE}
```

### Access Grafana

Once deployed, you can access Grafana through the OpenShift route:

```bash
echo https://$(oc get route/grafana-route -n ${NAMESPACE} --template='{{.spec.host}}')
```

Login with your OpenShift credentials.

## Configuration

The following table lists the configurable parameters and their default values:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `operator` | Install Grafana Operator | `true` |
| `grafana.serviceAccount.name` | Service account name | `grafana-sa` |
| `datasource.prometheus.url` | Prometheus/Thanos URL | `https://thanos-querier.openshift-monitoring.svc.cluster.local:9091` |
| `datasource.prometheus.timeInterval` | Metrics scrape interval | `5s` |

## Dashboards

The chart includes a pre-configured dashboard for visualizing guardrail metrics:

- **Total Detections**: Overall count of all guardrail detections
- **Detections by Detector**: Breakdown by detector type (HAP, Prompt Injection, Regex, Language)
- **Detections by Direction**: Input vs Output detections
- **Detections Heatmap**: Visualization of all detector combinations

## Uninstall

```bash
helm uninstall lemonade-grafana --namespace ${NAMESPACE}
```

