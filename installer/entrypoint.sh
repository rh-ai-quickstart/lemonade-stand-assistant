#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant Installer Entrypoint
# ============================================================================

set -euo pipefail

source /installer/lib/check_pre_reqs.sh
source /installer/lib/install.sh
source /installer/lib/upgrade.sh
source /installer/lib/status.sh
source /installer/lib/uninstall.sh

# ============================================================================
# DO NOT MODIFY: Termination message and log capture infrastructure
# ============================================================================

_TERMINATION_STATUS=""
_TERMINATION_MESSAGE=""
_LOG_FILE="/tmp/installer-output.log"
: > "$_LOG_FILE"

exec 3>&1 4>&2
exec > >(tee -a "$_LOG_FILE") 2> >(tee -a "$_LOG_FILE" >&2)

log_status() {
  local status=$1
  local phase=$2
  local message=$3
  echo "{\"status\":\"$status\",\"phase\":\"$phase\",\"message\":\"$message\"}"
}

log_success() {
  local endpoints=$1
  _TERMINATION_STATUS="success"
  _TERMINATION_MESSAGE=""
  echo "{\"status\":\"success\",\"endpoints\":$endpoints}"
}

log_error() {
  local message=$1
  _TERMINATION_STATUS="error"
  _TERMINATION_MESSAGE="$message"
  echo "{\"status\":\"error\",\"message\":\"$message\"}" >&2
  exit 1
}

log_prerequisites_failed() {
  local missing_json=$1
  _TERMINATION_STATUS="prerequisites_failed"
  _TERMINATION_MESSAGE="$missing_json"
  echo "{\"status\":\"prerequisites_failed\",\"missing\":$missing_json}" >&2
  exit 2
}

cleanup_installer_rbac() {
  log_status "running" "cleanup" "Installer cleanup complete"
}

# ============================================================================
# DO NOT MODIFY: Log ConfigMap persistence
# ============================================================================

write_log_configmap() {
  local job_name="${JOB_NAME:-unknown}"
  local cm_name="lemonade-stand-assistant-installer-log-${job_name}"
  local target_ns="${TARGET_NAMESPACE:-unknown}"
  local expires_at
  expires_at=$(date -u -d "+7 days" '+%Y-%m-%d' 2>/dev/null || \
               date -u -v+7d '+%Y-%m-%d' 2>/dev/null || \
               echo "unknown")

  local log_content
  log_content=$(tail -c 51200 "$_LOG_FILE" 2>/dev/null || echo "")

  if [[ -z "$log_content" ]]; then
    return 0
  fi

  local log_tmpfile="/tmp/installer-log-data.txt"
  echo "$log_content" > "$log_tmpfile"

  oc create configmap "$cm_name" \
    --namespace default \
    --from-file=log="$log_tmpfile" 2>/dev/null || { true; return 0; }

  oc label configmap "$cm_name" \
    --namespace default \
    --overwrite \
    "app=lemonade-stand-assistant-installer" \
    "target-namespace=${target_ns}" \
    "lemonade-stand-assistant-installer/expires-at=${expires_at}" 2>&1 || true
}

# ============================================================================
# DO NOT MODIFY: Termination message + Job annotation
# ============================================================================

write_termination_message() {
  local exit_code=$1
  local status="${_TERMINATION_STATUS}"

  if [[ -z "$status" ]]; then
    case "$exit_code" in
      0) status="success" ;;
      2) status="prerequisites_failed" ;;
      *) status="error" ;;
    esac
  fi

  local recent_logs
  recent_logs=$(tail -10 "$_LOG_FILE" 2>/dev/null | head -c 2000 || echo "")
  recent_logs="${recent_logs//\\/\\\\}"
  recent_logs="${recent_logs//\"/\\\"}"
  recent_logs="${recent_logs//$'\n'/\\n}"

  local job_name="${JOB_NAME:-unknown}"
  local cm_name="lemonade-stand-assistant-installer-log-${job_name}"
  local action="${ACTION:-unknown}"
  local namespace="${TARGET_NAMESPACE:-unknown}"

  local message=""
  case "$status" in
    success)
      message="{\"status\":\"success\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
    prerequisites_failed)
      message="{\"status\":\"prerequisites_failed\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"missing\":${_TERMINATION_MESSAGE:-[]},\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
    error)
      local err_msg="${_TERMINATION_MESSAGE:-Unexpected failure (exit code $exit_code)}"
      err_msg="${err_msg//\\/\\\\}"
      err_msg="${err_msg//\"/\\\"}"
      err_msg="${err_msg//$'\n'/\\n}"
      message="{\"status\":\"error\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"message\":\"${err_msg}\",\"recentLogs\":\"${recent_logs}\",\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
  esac

  printf '%.4096s' "$message" > /dev/termination-log 2>/dev/null || true

  if [[ -n "$job_name" && "$job_name" != "unknown" ]]; then
    oc annotate job "$job_name" \
      --namespace default \
      --overwrite \
      "lemonade-stand-assistant-installer/termination-message=$message" 2>/dev/null || true
  fi
}

# ============================================================================
# DO NOT MODIFY: EXIT trap
# ============================================================================

cleanup_on_exit() {
  local exit_code=$?
  exec 1>&3 2>&4 3>&- 4>&-
  sleep 0.2
  write_termination_message "$exit_code" 2>&1 | tee -a "$_LOG_FILE"
  if [[ "$exit_code" -ne 2 ]]; then
    cleanup_installer_rbac 2>&1 | tee -a "$_LOG_FILE"
  fi
  write_log_configmap
}
trap cleanup_on_exit EXIT

# ============================================================================
# Validation
# ============================================================================

: "${ACTION:?ACTION must be set (CHECK_PRE_REQS, STATUS, INSTALL, UNINSTALL_DELETE_ALL, UNINSTALL_KEEP_DATA)}"
: "${TARGET_NAMESPACE:?TARGET_NAMESPACE must be set}"
: "${INSTALL_MODE:=demo}"

case "$ACTION" in
  UPGRADE)
    log_error "Deployment Action (UPGRADE) not supported."
    ;;
esac

if [[ "$INSTALL_MODE" != "demo" ]]; then
  log_error "Installation mode ($INSTALL_MODE) not supported. Only 'demo' mode is currently supported."
fi

# ============================================================================
# Main action routing
# ============================================================================

case "$ACTION" in
  CHECK_PRE_REQS)
    log_status "running" "validating" "Validating prerequisites..."
    check_prerequisites || exit 2
    log_status "success" "validating" "All prerequisites satisfied"
    log_success "[]"
    ;;

  STATUS)
    log_status "running" "verifying" "Verifying quickstart deployment status..."
    verify_deployment
    log_status "success" "verifying" "Verification complete"
    log_success "[]"
    ;;

  INSTALL)
    log_status "running" "validating" "Validating prerequisites..."
    check_prerequisites || exit 2

    log_status "running" "deploying" "Installing in $INSTALL_MODE mode..."
    deploy_quickstart

    log_status "running" "checking-status" "Waiting for pods to be ready..."
    check_deployment_status

    log_status "running" "finalizing" "Retrieving endpoints..."
    ENDPOINTS=$(get_endpoints)
    log_success "$ENDPOINTS"
    ;;

  UNINSTALL_DELETE_ALL)
    log_status "running" "uninstalling" "Removing quickstart and all data..."
    cleanup_quickstart "delete-all"

    log_status "running" "verifying" "Verifying clean uninstallation..."
    verify_deployment
    log_success "[]"
    ;;

  UNINSTALL_KEEP_DATA)
    log_status "running" "uninstalling" "Removing quickstart (keeping data volumes)..."
    cleanup_quickstart "keep-data"

    log_status "running" "verifying" "Verifying uninstallation (data preserved)..."
    verify_deployment
    log_success "[]"
    ;;

  UPGRADE)
    log_error "Deployment Action (UPGRADE) not supported."
    ;;

  *)
    log_error "Invalid ACTION: $ACTION (must be CHECK_PRE_REQS, STATUS, INSTALL, UNINSTALL_DELETE_ALL, UNINSTALL_KEEP_DATA)"
    ;;
esac
