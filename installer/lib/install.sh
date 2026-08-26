#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant — Install
# ============================================================================

detect_gpu_tolerations() {
  local taint_keys
  taint_keys=$(oc get nodes -o json 2>/dev/null | \
    jq -r '[.items[] | select(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber > 0) | .spec.taints // [] | .[] | select(.effect == "NoSchedule") | .key] | unique | .[]' 2>/dev/null || echo "")

  if [[ -z "$taint_keys" ]]; then
    echo '[{"effect":"NoSchedule","key":"nvidia.com/gpu","operator":"Exists"}]'
    return
  fi

  local json="["
  local first=true
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if [[ "$first" == "true" ]]; then
      first=false
    else
      json+=","
    fi
    json+="{\"effect\":\"NoSchedule\",\"key\":\"${key}\",\"operator\":\"Exists\"}"
  done <<< "$taint_keys"
  json+="]"
  echo "$json"
}

# Append a string-typed Helm override to the helm_args array.
# Uses --set-string so values are never coerced to bool/number, and
# backslash-escapes literal commas that Helm would otherwise treat as
# --set multi-value delimiters (e.g. "Red Hat, Inc.").
append_set_string() {
  local key="$1" value="$2"
  value="${value//,/\\,}"
  helm_args+=("--set-string" "${key}=${value}")
}

deploy_quickstart() {
  local ns="$TARGET_NAMESPACE"

  # Create namespace if it doesn't exist
  if oc get namespace "$ns" &>/dev/null; then
    echo "Namespace $ns already exists"
  else
    echo "Creating namespace $ns..."
    oc create namespace "$ns" || true
  fi

  # Build helm install command
  local helm_args=(
    "install" "lemonade-stand-assistant" "/installer/chart"
    "--namespace" "$ns"
    "--wait"
    "--timeout" "15m"
  )

  # MaaS mode: pass model configuration if provided.
  # name/endpoint/api_key are free text -> --set-string; port is numeric.
  if [[ -n "${MODEL_NAME:-}" ]]; then
    append_set_string "model.name" "$MODEL_NAME"
  fi
  if [[ -n "${MODEL_ENDPOINT:-}" ]]; then
    append_set_string "model.endpoint" "$MODEL_ENDPOINT"
  fi
  if [[ -n "${MODEL_PORT:-}" ]]; then
    helm_args+=("--set" "model.port=${MODEL_PORT}")
  fi
  if [[ -n "${MODEL_API_KEY:-}" ]]; then
    append_set_string "model.api_key" "$MODEL_API_KEY"
  fi

  # GPU tolerations: use provided value or auto-detect from cluster
  local gpu_tolerations
  if [[ -n "${GPU_TOLERATIONS:-}" ]]; then
    gpu_tolerations="$GPU_TOLERATIONS"
    echo "Using provided GPU tolerations: $gpu_tolerations"
  else
    echo "Auto-detecting GPU taint keys from cluster nodes..."
    gpu_tolerations=$(detect_gpu_tolerations)
    echo "Detected GPU tolerations: $gpu_tolerations"
  fi

  local idx=0
  for row in $(echo "$gpu_tolerations" | jq -c '.[]'); do
    local key effect operator
    key=$(echo "$row" | jq -r '.key')
    effect=$(echo "$row" | jq -r '.effect')
    operator=$(echo "$row" | jq -r '.operator')
    helm_args+=("--set" "gpuTolerations[${idx}].key=${key}")
    helm_args+=("--set" "gpuTolerations[${idx}].effect=${effect}")
    helm_args+=("--set" "gpuTolerations[${idx}].operator=${operator}")
    idx=$((idx + 1))
  done

  echo "Running: helm ${helm_args[*]}"
  helm "${helm_args[@]}"

  echo "Helm install complete."
}

check_deployment_status() {
  local ns="$TARGET_NAMESPACE"
  local max_wait=120
  local wait_count=0

  echo "Waiting for pods to be ready in namespace $ns..."
  while [[ $wait_count -lt $max_wait ]]; do
    local total ready not_ready
    total=$(oc get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running\|Completed\|Succeeded" || echo "0")
    not_ready=$((total - ready))

    echo "  Pods: $ready/$total ready"

    if [[ "$total" -gt 0 && "$not_ready" -eq 0 ]]; then
      echo "All pods are ready."
      return 0
    fi

    sleep 10
    wait_count=$((wait_count + 1))
  done

  echo "Warning: Not all pods became ready within timeout. Continuing..."
  return 0
}

get_endpoints() {
  local ns="$TARGET_NAMESPACE"
  local endpoints="[]"

  local app_route
  app_route=$(oc get route lemonade-stand -n "$ns" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  local dashboard_route
  dashboard_route=$(oc get route shiny-dashboard -n "$ns" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  endpoints="["
  local first=true

  if [[ -n "$app_route" ]]; then
    endpoints+="{\"name\":\"Lemonade Stand Chat\",\"url\":\"https://${app_route}\",\"type\":\"route\"}"
    first=false
  fi

  if [[ -n "$dashboard_route" ]]; then
    if [[ "$first" == "false" ]]; then
      endpoints+=","
    fi
    endpoints+="{\"name\":\"Monitoring Dashboard\",\"url\":\"https://${dashboard_route}\",\"type\":\"route\"}"
  fi

  endpoints+="]"
  echo "$endpoints"
}
