#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant — Status Check
# ============================================================================

verify_deployment() {
  local ns="$TARGET_NAMESPACE"

  # Check if namespace exists
  if ! oc get namespace "$ns" &>/dev/null; then
    echo "Namespace $ns does not exist. Quickstart is not deployed."
    return 0
  fi

  local ns_phase
  ns_phase=$(oc get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$ns_phase" == "Terminating" ]]; then
    echo "Namespace $ns is terminating."
    return 0
  fi

  # Check Helm release
  echo "Checking Helm release..."
  if helm list -n "$ns" 2>/dev/null | grep -q "lemonade-stand-assistant"; then
    local helm_status
    helm_status=$(helm status lemonade-stand-assistant -n "$ns" -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "unknown")
    echo "  Helm release status: $helm_status"
  else
    echo "  No Helm release found."
  fi

  # Check pod status
  echo "Checking pod status..."
  local pods
  pods=$(oc get pods -n "$ns" --no-headers 2>/dev/null || echo "")
  if [[ -z "$pods" ]]; then
    echo "  No pods found in namespace $ns."
    return 0
  fi

  local total ready running failed pending
  total=$(echo "$pods" | wc -l | tr -d ' ')
  running=$(echo "$pods" | { grep "Running" || true; } | wc -l | tr -d ' ')
  ready=$(echo "$pods" | { grep -E "1/1|2/2|3/3|4/4|5/5" || true; } | wc -l | tr -d ' ')
  failed=$(echo "$pods" | { grep -E "Error|CrashLoopBackOff|ImagePullBackOff" || true; } | wc -l | tr -d ' ')
  pending=$(echo "$pods" | { grep -E "Pending|ContainerCreating|Init:" || true; } | wc -l | tr -d ' ')

  echo "  Total pods: $total"
  echo "  Running: $running"
  echo "  Ready: $ready"
  echo "  Failed: $failed"
  echo "  Pending: $pending"

  # List pods with issues
  if [[ "${failed:-0}" -gt 0 ]]; then
    echo "  Pods with issues:"
    echo "$pods" | { grep "Error\|CrashLoopBackOff\|ImagePullBackOff" || true; } | while read -r line; do
      echo "    $line"
    done
  fi

  # Check InferenceService status
  echo "Checking InferenceServices..."
  local isvc_list
  isvc_list=$(oc get inferenceservices -n "$ns" --no-headers 2>/dev/null || echo "")
  if [[ -n "$isvc_list" ]]; then
    echo "$isvc_list" | while read -r line; do
      echo "  $line"
    done
  else
    echo "  No InferenceServices found."
  fi

  # Check routes
  echo "Checking routes..."
  local app_route
  app_route=$(oc get route lemonade-stand -n "$ns" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -n "$app_route" ]]; then
    echo "  ✓ Lemonade Stand Chat: https://$app_route"
  else
    echo "  ✗ Lemonade Stand Chat route not found"
  fi

  local dashboard_route
  dashboard_route=$(oc get route shiny-dashboard -n "$ns" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -n "$dashboard_route" ]]; then
    echo "  ✓ Monitoring Dashboard: https://$dashboard_route"
  else
    echo "  ✗ Monitoring Dashboard route not found"
  fi

  # Check health endpoint
  if [[ -n "$app_route" ]]; then
    echo "Checking health endpoint..."
    local health_status
    health_status=$(curl -sk -o /dev/null -w "%{http_code}" "https://${app_route}/health" 2>/dev/null || echo "000")
    if [[ "$health_status" == "200" ]]; then
      echo "  ✓ Health endpoint: OK (HTTP $health_status)"
    else
      echo "  ⚠ Health endpoint: HTTP $health_status"
    fi
  fi

  echo "Status check complete."
}
