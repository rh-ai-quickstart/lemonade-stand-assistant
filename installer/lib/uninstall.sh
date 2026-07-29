#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant — Uninstall
# ============================================================================

cleanup_quickstart() {
  local mode=$1
  local ns="$TARGET_NAMESPACE"

  # Check if namespace exists
  if ! oc get namespace "$ns" &>/dev/null; then
    echo "Namespace $ns does not exist. Nothing to uninstall."
    return 0
  fi

  # Uninstall Helm release if it exists
  if helm list -n "$ns" 2>/dev/null | grep -q "lemonade-stand-assistant"; then
    echo "Uninstalling Helm release lemonade-stand-assistant..."
    helm uninstall lemonade-stand-assistant --namespace "$ns" --wait --timeout 5m || true
    echo "Helm release uninstalled."
  else
    echo "No Helm release found. Cleaning up remaining resources..."
  fi

  case "$mode" in
    delete-all)
      echo "Deleting all resources including data volumes..."

      # Delete any remaining resources not managed by Helm
      oc delete inferenceservices --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete servingruntimes --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete guardrailsorchestrators --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete servicemonitors --all -n "$ns" --ignore-not-found=true 2>/dev/null || true

      # Delete PVCs
      echo "Deleting persistent volume claims..."
      oc delete pvc --all -n "$ns" --ignore-not-found=true 2>/dev/null || true

      # Delete the namespace
      echo "Deleting namespace $ns..."
      oc delete namespace "$ns" --ignore-not-found=true 2>/dev/null || true

      # Wait for namespace deletion
      local wait_count=0
      while [[ $wait_count -lt 60 ]]; do
        local ns_phase
        ns_phase=$(oc get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [[ -z "$ns_phase" ]]; then
          echo "Namespace $ns deleted."
          break
        fi
        if [[ "$ns_phase" == "Terminating" ]]; then
          echo "  Namespace $ns is terminating..."
        fi
        sleep 5
        wait_count=$((wait_count + 1))
      done
      ;;

    keep-data)
      echo "Removing workloads but preserving data volumes..."

      # Delete workloads and services but keep PVCs
      oc delete deployments --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete services --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete routes --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete configmaps --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete secrets --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete jobs --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete inferenceservices --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete servingruntimes --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete guardrailsorchestrators --all -n "$ns" --ignore-not-found=true 2>/dev/null || true
      oc delete servicemonitors --all -n "$ns" --ignore-not-found=true 2>/dev/null || true

      echo "Workloads removed. PVCs preserved in namespace $ns."
      ;;
  esac

  echo "Uninstall complete."
}
