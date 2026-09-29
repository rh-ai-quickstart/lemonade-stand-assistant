#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant — Prerequisites Check
# ============================================================================

check_prerequisites() {
  local missing=()

  # --------------------------------------------------------------------------
  # OpenShift version
  # --------------------------------------------------------------------------
  echo "Checking OpenShift version..."
  local ocp_version
  ocp_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "")
  if [[ -z "$ocp_version" ]]; then
    missing+=("{\"name\":\"OpenShift Version\",\"reason\":\"Could not determine OpenShift version\"}")
  else
    echo "  OpenShift version: $ocp_version"
    local required_version="4.16"
    local ocp_major ocp_minor req_major req_minor
    ocp_major=$(echo "$ocp_version" | cut -d. -f1)
    ocp_minor=$(echo "$ocp_version" | cut -d. -f2)
    req_major=$(echo "$required_version" | cut -d. -f1)
    req_minor=$(echo "$required_version" | cut -d. -f2)
    if [[ "$ocp_major" -lt "$req_major" ]] || { [[ "$ocp_major" -eq "$req_major" ]] && [[ "$ocp_minor" -lt "$req_minor" ]]; }; then
      missing+=("{\"name\":\"OpenShift Version\",\"reason\":\"Requires >= $required_version, found $ocp_version\"}")
    fi
  fi

  # --------------------------------------------------------------------------
  # Required CRDs
  # --------------------------------------------------------------------------
  echo "Checking required CRDs..."

  local required_crds=(
    "servingruntimes.serving.kserve.io"
    "inferenceservices.serving.kserve.io"
    "guardrailsorchestrators.trustyai.opendatahub.io"
  )

  for crd in "${required_crds[@]}"; do
    if oc get crd "$crd" &>/dev/null; then
      echo "  ✓ CRD found: $crd"
    else
      missing+=("{\"name\":\"CRD: $crd\",\"reason\":\"Custom Resource Definition not found. Ensure the required operator is installed.\"}")
    fi
  done

  # --------------------------------------------------------------------------
  # Required operators
  # --------------------------------------------------------------------------
  echo "Checking required operators..."

  # Check RHOAI via KServe CRDs (more reliable than CSV listing which requires extra RBAC)
  if oc get crd inferenceservices.serving.kserve.io &>/dev/null && \
     oc get crd servingruntimes.serving.kserve.io &>/dev/null; then
    echo "  ✓ Red Hat OpenShift AI operator found (KServe CRDs present)"
  else
    missing+=("{\"name\":\"Red Hat OpenShift AI\",\"reason\":\"Operator not installed. Install from OperatorHub.\"}")
  fi

  # Check TrustyAI via GuardrailsOrchestrator CRD
  if oc get crd guardrailsorchestrators.trustyai.opendatahub.io &>/dev/null; then
    echo "  ✓ TrustyAI component found (GuardrailsOrchestrator CRD present)"
  else
    missing+=("{\"name\":\"TrustyAI\",\"reason\":\"TrustyAI component not enabled in Red Hat OpenShift AI. Enable TrustyAI in the DataScienceCluster configuration.\"}")
  fi

  # --------------------------------------------------------------------------
  # Storage classes
  # --------------------------------------------------------------------------
  echo "Checking storage classes..."
  local rwo_classes
  rwo_classes=$(oc get storageclasses -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true" or true) | .metadata.name' 2>/dev/null || echo "")
  if [[ -n "$rwo_classes" ]]; then
    echo "  ✓ Storage classes available"
  else
    missing+=("{\"name\":\"Storage Class\",\"reason\":\"No storage classes found. A ReadWriteOnce storage class is required for MinIO PVC (50Gi).\"}")
  fi

  # --------------------------------------------------------------------------
  # Node resources
  # --------------------------------------------------------------------------
  echo "Checking node resources..."
  local total_cpu total_memory
  total_cpu=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.allocatable.cpu // "0" | if test("m$") then (gsub("m$";"") | tonumber / 1000) else tonumber end] | add | round' 2>/dev/null || echo "0")
  total_memory=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.allocatable.memory // "0" | gsub("Ki$";"") | tonumber / 1048576] | add | round' 2>/dev/null || echo "0")

  if [[ -n "$total_cpu" ]] && (( $(echo "$total_cpu >= 9" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ✓ CPU: ${total_cpu} vCPU available (minimum 9 required)"
  else
    missing+=("{\"name\":\"CPU Resources\",\"reason\":\"Minimum 9 vCPU required across cluster nodes. Found: ${total_cpu:-unknown}\"}")
  fi

  if [[ -n "$total_memory" ]] && (( $(echo "$total_memory >= 33" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ✓ Memory: ${total_memory} GiB available (minimum 33 required)"
  else
    missing+=("{\"name\":\"Memory Resources\",\"reason\":\"Minimum 33 GiB memory required across cluster nodes. Found: ${total_memory:-unknown} GiB\"}")
  fi

  # --------------------------------------------------------------------------
  # GPU (informational — only required for default model mode)
  # --------------------------------------------------------------------------
  echo "Checking GPU resources..."
  local gpu_count
  gpu_count=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.allocatable["nvidia.com/gpu"] // "0" | tonumber] | add' 2>/dev/null || echo "0")
  if [[ "$gpu_count" -gt 0 ]]; then
    echo "  ✓ GPU: $gpu_count NVIDIA GPU(s) available"

    local taint_keys
    taint_keys=$(oc get nodes -o json 2>/dev/null | \
      jq -r '[.items[] | select(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber > 0) | .spec.taints // [] | .[] | select(.effect == "NoSchedule") | .key] | unique | .[]' 2>/dev/null || echo "")
    if [[ -n "$taint_keys" ]]; then
      echo "  GPU node taint keys detected:"
      while IFS= read -r key; do
        [[ -n "$key" ]] && echo "    - $key"
      done <<< "$taint_keys"
      echo "  The installer will auto-detect these during install, or you can override with custom keys."
    else
      echo "  No NoSchedule taints found on GPU nodes."
    fi
  else
    echo "  ⚠ No NVIDIA GPUs detected. The default deployment mode (local Llama 3.2) requires 1 GPU."
    echo "    Use MaaS mode (bring your own model endpoint) to deploy without a GPU."
  fi

  # --------------------------------------------------------------------------
  # Report results
  # --------------------------------------------------------------------------
  if [[ ${#missing[@]} -gt 0 ]]; then
    local missing_json="["
    for i in "${!missing[@]}"; do
      if [[ $i -gt 0 ]]; then
        missing_json+=","
      fi
      missing_json+="${missing[$i]}"
    done
    missing_json+="]"
    log_prerequisites_failed "$missing_json"
    return 2
  fi

  echo "All prerequisites satisfied."
  return 0
}
