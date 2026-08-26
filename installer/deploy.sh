#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant — Deploy Script (Navigator Proxy)
# ============================================================================

set -euo pipefail

REGISTRY="quay.io/rh-ai-quickstart"
IMAGE_NAME="lemonade-stand-assistant-installer"
VERSION="1.0.0"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# ============================================================================
# Job deployment function
# ============================================================================

deploy_job() {
  local ACTION=$1
  local TARGET_NAMESPACE=$2
  local EXTRA_ENV=$3

  local INSTALLER_NAMESPACE="default"

  # --------------------------------------------------------------------------
  # Create RBAC for installer
  # --------------------------------------------------------------------------
  info "Creating installer RBAC..."

  cat <<RBAC | oc apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lemonade-stand-assistant-installer
  namespace: ${INSTALLER_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: lemonade-stand-assistant-installer
  namespace: ${INSTALLER_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["pods", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lemonade-stand-assistant-installer
  namespace: ${INSTALLER_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: lemonade-stand-assistant-installer
subjects:
  - kind: ServiceAccount
    name: lemonade-stand-assistant-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  cat <<RBAC | oc apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: lemonade-stand-assistant-installer-${TARGET_NAMESPACE}
rules:
  # Cluster-scoped read permissions
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
  - apiGroups: ["config.openshift.io"]
    resources: ["clusterversions"]
    verbs: ["get", "list"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list"]
  - apiGroups: ["packages.operators.coreos.com"]
    resources: ["packagemanifests"]
    verbs: ["get", "list"]
  # Namespace management
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "delete"]
  # Core resources
  - apiGroups: [""]
    resources: ["pods", "services", "secrets", "configmaps", "persistentvolumeclaims", "serviceaccounts"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Workloads
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Jobs
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Routes
  - apiGroups: ["route.openshift.io"]
    resources: ["routes"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # RBAC
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Monitoring
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["servicemonitors"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # KServe
  - apiGroups: ["serving.kserve.io"]
    resources: ["servingruntimes", "inferenceservices"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # TrustyAI
  - apiGroups: ["trustyai.opendatahub.io"]
    resources: ["guardrailsorchestrators"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: lemonade-stand-assistant-installer-${TARGET_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: lemonade-stand-assistant-installer-${TARGET_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: lemonade-stand-assistant-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  # --------------------------------------------------------------------------
  # Create and monitor the Job
  # --------------------------------------------------------------------------

  local ACTION_SHORT=$(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  local TIMESTAMP=$(date +%s | tail -c 7)
  local JOB_NAME="lsa-installer-${ACTION_SHORT}-${TIMESTAMP}"

  info "Creating installer Job: $JOB_NAME"
  info "Action: $ACTION"
  info "Target namespace: $TARGET_NAMESPACE"
  info "Installer namespace: $INSTALLER_NAMESPACE"
  info "Image: ${FULL_IMAGE}"

  cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${INSTALLER_NAMESPACE}
  labels:
    app: lemonade-stand-assistant-installer
    action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    target-namespace: ${TARGET_NAMESPACE}
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: lemonade-stand-assistant-installer
        action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    spec:
      restartPolicy: Never
      serviceAccountName: lemonade-stand-assistant-installer
      containers:
      - name: installer
        image: ${FULL_IMAGE}
        imagePullPolicy: Always
        terminationMessagePolicy: FallbackToLogsOnError
        env:
        - name: ACTION
          value: "${ACTION}"
        - name: TARGET_NAMESPACE
          value: "${TARGET_NAMESPACE}"
        - name: JOB_NAME
          value: "${JOB_NAME}"
${EXTRA_ENV}
EOF

  echo ""
  info "Job created! Monitoring logs..."
  echo ""

  sleep 3
  oc logs -n "$INSTALLER_NAMESPACE" -f "job/${JOB_NAME}" 2>/dev/null || {
    warn "Job may still be starting. Check logs with:"
    echo "  oc logs -n $INSTALLER_NAMESPACE -f job/${JOB_NAME}"
  }

  # --------------------------------------------------------------------------
  # Wait for Job completion
  # --------------------------------------------------------------------------
  echo ""
  info "Waiting for Job to complete..."

  WAIT_COUNT=0
  MAX_WAIT=240
  while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
    JOB_COMPLETE=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    JOB_FAILED=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)

    if [[ "$JOB_COMPLETE" == "True" ]]; then
      info "Job completed successfully"
      break
    elif [[ "$JOB_FAILED" == "True" ]]; then
      warn "Job failed. Check logs above for details."
      break
    fi

    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
  done

  if [[ $WAIT_COUNT -eq $MAX_WAIT ]]; then
    warn "Job did not complete within 20 minutes"
    echo "  Check status: oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  fi

  # --------------------------------------------------------------------------
  # Retrieve termination message
  # --------------------------------------------------------------------------
  TERM_MSG=""
  POD_NAME=$(oc get pods -n "$INSTALLER_NAMESPACE" -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$POD_NAME" ]]; then
    TERM_MSG=$(oc get pod -n "$INSTALLER_NAMESPACE" "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].state.terminated.message}' 2>/dev/null)
  fi
  if [[ -z "$TERM_MSG" ]]; then
    TERM_MSG=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.metadata.annotations.lemonade-stand-assistant-installer/termination-message}' 2>/dev/null)
  fi
  if [[ -n "$TERM_MSG" ]]; then
    echo ""
    info "Termination message:"
    echo "  $TERM_MSG"
  fi

  echo ""
  info "Job complete! Check status with:"
  echo "  oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  echo "  oc describe job -n $INSTALLER_NAMESPACE ${JOB_NAME}"

  # --------------------------------------------------------------------------
  # Clean up installer RBAC
  # --------------------------------------------------------------------------
  info "Cleaning up installer RBAC..."

  oc delete serviceaccount lemonade-stand-assistant-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete role lemonade-stand-assistant-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete rolebinding lemonade-stand-assistant-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete secret -l "kubernetes.io/service-account.name=lemonade-stand-assistant-installer" -n default --ignore-not-found=true 2>/dev/null || true

  oc delete clusterrolebinding "lemonade-stand-assistant-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
  oc delete clusterrole "lemonade-stand-assistant-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
}

# ============================================================================
# Main case statement
# ============================================================================

case "${1:-}" in
  check_pre_reqs)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh check_pre_reqs <namespace>"
    deploy_job "CHECK_PRE_REQS" "$NAMESPACE" ""
    ;;

  status)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh status <namespace>"
    deploy_job "STATUS" "$NAMESPACE" ""
    ;;

  install)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh install <namespace>"

    INSTALL_ENV="        - name: INSTALL_MODE
          value: \"demo\""

    # Prompt for MaaS mode configuration
    read -rp "Use external model endpoint (MaaS mode)? [y/N]: " USE_MAAS
    if [[ "$USE_MAAS" == "y" || "$USE_MAAS" == "Y" ]]; then
      read -rp "Model name: " MODEL_NAME
      read -rp "Model endpoint (hostname only): " MODEL_ENDPOINT
      read -rp "Model port [443]: " MODEL_PORT
      MODEL_PORT="${MODEL_PORT:-443}"
      read -rsp "Model API key: " MODEL_API_KEY
      echo ""

      INSTALL_ENV="        - name: INSTALL_MODE
          value: \"demo\"
        - name: MODEL_NAME
          value: \"${MODEL_NAME}\"
        - name: MODEL_ENDPOINT
          value: \"${MODEL_ENDPOINT}\"
        - name: MODEL_PORT
          value: \"${MODEL_PORT}\"
        - name: MODEL_API_KEY
          value: \"${MODEL_API_KEY}\""
    fi

    # Prompt for GPU taint key override
    echo ""
    echo "GPU tolerations control which tainted nodes GPU pods can schedule on."
    echo "Press Enter to auto-detect from cluster nodes, or provide a comma-separated"
    echo "list of taint keys to override (e.g., 'g5-gpu,g6e-gpu')."
    read -rp "GPU taint keys [auto-detect]: " GPU_TAINT_KEYS

    if [[ -n "$GPU_TAINT_KEYS" ]]; then
      local gpu_json="["
      local first=true
      IFS=',' read -ra KEYS <<< "$GPU_TAINT_KEYS"
      for key in "${KEYS[@]}"; do
        key=$(echo "$key" | tr -d ' ')
        [[ -z "$key" ]] && continue
        if [[ "$first" == "true" ]]; then
          first=false
        else
          gpu_json+=","
        fi
        gpu_json+="{\"effect\":\"NoSchedule\",\"key\":\"${key}\",\"operator\":\"Exists\"}"
      done
      gpu_json+="]"
      INSTALL_ENV="${INSTALL_ENV}
        - name: GPU_TOLERATIONS
          value: '${gpu_json}'"
    fi

    deploy_job "INSTALL" "$NAMESPACE" "$INSTALL_ENV"
    ;;

  uninstall_keep_data)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh uninstall_keep_data <namespace>"
    deploy_job "UNINSTALL_KEEP_DATA" "$NAMESPACE" ""
    ;;

  uninstall_delete_all)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh uninstall_delete_all <namespace>"
    deploy_job "UNINSTALL_DELETE_ALL" "$NAMESPACE" ""
    ;;

  "")
    echo "Lemonade Stand Assistant Installer - Deploy Jobs to Cluster"
    echo ""
    echo "Usage: ./deploy.sh <action> <namespace>"
    echo ""
    echo "Actions:"
    echo "  check_pre_reqs <namespace>          - Validate prerequisites"
    echo "  status <namespace>                   - Check deployment status"
    echo "  install <namespace>                  - Deploy installation"
    echo "  uninstall_keep_data <namespace>      - Uninstall (keep data)"
    echo "  uninstall_delete_all <namespace>     - Uninstall (delete all)"
    echo ""
    echo "Image: ${FULL_IMAGE}"
    ;;

  *)
    error "Unknown action: $1"
    ;;
esac
