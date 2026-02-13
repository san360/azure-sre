#!/bin/bash
set -euo pipefail

###############################################################################
# Contoso Meals - Node Pool Failure Alert Setup
#
# Creates Azure Monitor alert rules to detect AKS node pool failures:
#   1. Node NotReady alert — fires when nodes go NotReady
#   2. Node pool count alert — fires when workload node pool has 0 ready nodes
#   3. Pod unschedulable alert — fires when pods cannot be scheduled
#
# These alerts are connected to the SRE Agent action group so the agent
# can automatically detect, investigate, and remediate node pool issues.
#
# Usage:
#   ./scripts/setup-node-alerts.sh              # create all alerts
#   ./scripts/setup-node-alerts.sh --delete      # remove all alerts
#   ./scripts/setup-node-alerts.sh --verify      # check alert status
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Defaults
DELETE=false
VERIFY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete) DELETE=true; shift ;;
    --verify) VERIFY=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Load .env ──────────────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-contoso-meals}"
AKS_CLUSTER="${AKS_CLUSTER:-aks-contoso-meals}"
PREFIX="${PREFIX:-contoso-meals}"
LOCATION="${LOCATION:-swedencentral}"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Node Pool Failure Alert Setup                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Get Log Analytics workspace ID
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "law-${PREFIX}" \
  --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "$LAW_ID" ]; then
  echo "ERROR: Log Analytics workspace 'law-${PREFIX}' not found in '${RESOURCE_GROUP}'."
  echo "Deploy infrastructure first: ./scripts/deploy.sh"
  exit 1
fi

AKS_RESOURCE_ID=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --query "id" -o tsv 2>/dev/null || echo "")

echo "  Log Analytics:  law-${PREFIX}"
echo "  AKS Cluster:    ${AKS_CLUSTER}"
echo "  Resource Group:  ${RESOURCE_GROUP}"
echo ""

# ─── Verify Mode ───────────────────────────────────────────────────
if [ "$VERIFY" = true ]; then
  echo "━━━ Alert Status ━━━"
  echo ""
  for ALERT_NAME in "alert-node-not-ready-${PREFIX}" "alert-nodepool-zero-${PREFIX}" "alert-pod-unschedulable-${PREFIX}"; do
    STATUS=$(az monitor scheduled-query show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$ALERT_NAME" \
      --query "{name:name, enabled:enabled, severity:severity}" \
      -o json 2>/dev/null || echo "")
    if [ -n "$STATUS" ]; then
      ENABLED=$(echo "$STATUS" | jq -r '.enabled')
      SEVERITY=$(echo "$STATUS" | jq -r '.severity')
      echo "  ✓ ${ALERT_NAME}: enabled=${ENABLED}, severity=${SEVERITY}"
    else
      echo "  ✗ ${ALERT_NAME}: NOT FOUND"
    fi
  done
  exit 0
fi

# ─── Delete Mode ───────────────────────────────────────────────────
if [ "$DELETE" = true ]; then
  echo "━━━ Deleting Node Pool Alerts ━━━"
  for ALERT_NAME in "alert-node-not-ready-${PREFIX}" "alert-nodepool-zero-${PREFIX}" "alert-pod-unschedulable-${PREFIX}"; do
    echo -n "  ${ALERT_NAME}: "
    az monitor scheduled-query delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$ALERT_NAME" \
      --yes 2>/dev/null && echo "deleted" || echo "not found (skip)"
  done
  exit 0
fi

# ─── Get or create Action Group ────────────────────────────────────
ACTION_GROUP_ID=$(az monitor action-group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "ag-${PREFIX}-sre" \
  --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "$ACTION_GROUP_ID" ]; then
  echo "  Creating SRE action group..."
  az monitor action-group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "ag-${PREFIX}-sre" \
    --short-name "SREAgent" \
    --only-show-errors
  ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "ag-${PREFIX}-sre" \
    --query "id" -o tsv)
fi

echo "  Action Group:   ag-${PREFIX}-sre"
echo ""

# ─── Alert 1: Node NotReady ────────────────────────────────────────
echo "━━━ Creating Alert: Node NotReady ━━━"
cat <<'QUERY' > /tmp/node-notready-query.txt
KubeNodeInventory
| where Status contains "NotReady"
| where Computer contains "workload"
| summarize NotReadyCount = dcount(Computer) by bin(TimeGenerated, 5m)
| where NotReadyCount > 0
QUERY

az monitor scheduled-query create \
  --resource-group "$RESOURCE_GROUP" \
  --name "alert-node-not-ready-${PREFIX}" \
  --display-name "AKS Workload Node Pool - Node NotReady" \
  --scopes "$LAW_ID" \
  --condition "count 'node_notready' > 0" \
  --condition-query node_notready="$(cat /tmp/node-notready-query.txt)" \
  --evaluation-frequency 1m \
  --window-size 5m \
  --severity 1 \
  --action-groups "$ACTION_GROUP_ID" \
  --description "One or more nodes in the 'workload' user node pool are in NotReady state. This indicates node failure or deallocation. SRE Agent should investigate and remediate by scaling the node pool." \
  --tags CostControl=Ignore SecurityControl=Ignore Environment=demo Project="${PREFIX}" \
  --only-show-errors 2>/dev/null || echo "  (Alert may already exist — updating)"

echo "  ✓ alert-node-not-ready-${PREFIX} created"
echo ""

# ─── Alert 2: Node Pool Scaled to Zero ─────────────────────────────
echo "━━━ Creating Alert: Node Pool Scaled to Zero ━━━"
cat <<'QUERY' > /tmp/nodepool-zero-query.txt
KubeNodeInventory
| where Computer contains "workload"
| summarize NodeCount = dcount(Computer) by bin(TimeGenerated, 5m)
| where NodeCount == 0
QUERY

az monitor scheduled-query create \
  --resource-group "$RESOURCE_GROUP" \
  --name "alert-nodepool-zero-${PREFIX}" \
  --display-name "AKS Workload Node Pool Scaled to Zero Nodes" \
  --scopes "$LAW_ID" \
  --condition "count 'nodepool_zero' > 0" \
  --condition-query nodepool_zero="$(cat /tmp/nodepool-zero-query.txt)" \
  --evaluation-frequency 1m \
  --window-size 5m \
  --severity 1 \
  --action-groups "$ACTION_GROUP_ID" \
  --description "The 'workload' user node pool has 0 ready nodes. All application pods will be in Pending state. SRE Agent must scale the node pool back to at least 1 node." \
  --tags CostControl=Ignore SecurityControl=Ignore Environment=demo Project="${PREFIX}" \
  --only-show-errors 2>/dev/null || echo "  (Alert may already exist — updating)"

echo "  ✓ alert-nodepool-zero-${PREFIX} created"
echo ""

# ─── Alert 3: Pods Unschedulable ───────────────────────────────────
echo "━━━ Creating Alert: Pods Unschedulable ━━━"
cat <<'QUERY' > /tmp/pod-unschedulable-query.txt
KubeEvents
| where Namespace == "production"
| where Reason in ("FailedScheduling", "Unschedulable")
| where Message contains "nodes are available" or Message contains "Insufficient"
| summarize EventCount = count() by bin(TimeGenerated, 5m)
| where EventCount > 0
QUERY

az monitor scheduled-query create \
  --resource-group "$RESOURCE_GROUP" \
  --name "alert-pod-unschedulable-${PREFIX}" \
  --display-name "AKS Pods Unschedulable - No Available Nodes" \
  --scopes "$LAW_ID" \
  --condition "count 'pod_unsched' > 0" \
  --condition-query pod_unsched="$(cat /tmp/pod-unschedulable-query.txt)" \
  --evaluation-frequency 1m \
  --window-size 5m \
  --severity 1 \
  --action-groups "$ACTION_GROUP_ID" \
  --description "Pods in the 'production' namespace cannot be scheduled due to insufficient nodes. Likely caused by node pool scale-to-zero. SRE Agent should investigate node pool status and scale up." \
  --tags CostControl=Ignore SecurityControl=Ignore Environment=demo Project="${PREFIX}" \
  --only-show-errors 2>/dev/null || echo "  (Alert may already exist — updating)"

echo "  ✓ alert-pod-unschedulable-${PREFIX} created"
echo ""

# ─── Metric-based Alert: Node Pool Ready Count ────────────────────
echo "━━━ Creating Metric Alert: Node Count Dropped ━━━"

az monitor metrics alert create \
  --resource-group "$RESOURCE_GROUP" \
  --name "alert-metric-nodepool-count-${PREFIX}" \
  --description "AKS workload node pool node count has dropped to 0. This is a critical infrastructure failure requiring immediate remediation." \
  --scopes "$AKS_RESOURCE_ID" \
  --condition "avg node_count{nodepool=workload} < 1" \
  --evaluation-frequency 1m \
  --window-size 5m \
  --severity 0 \
  --action "$ACTION_GROUP_ID" \
  --tags CostControl=Ignore SecurityControl=Ignore Environment=demo Project="${PREFIX}" \
  --only-show-errors 2>/dev/null || echo "  (Metric alert may already exist — updating)"

echo "  ✓ alert-metric-nodepool-count-${PREFIX} created"
echo ""

# ─── Clean up temp files ───────────────────────────────────────────
rm -f /tmp/node-notready-query.txt /tmp/nodepool-zero-query.txt /tmp/pod-unschedulable-query.txt

# ─── Summary ────────────────────────────────────────────────────────
echo "━━━ Alert Setup Complete ━━━"
echo ""
echo "  Created 4 alerts for node pool failure detection:"
echo "    1. alert-node-not-ready-${PREFIX}          (Sev 1) — Node NotReady status"
echo "    2. alert-nodepool-zero-${PREFIX}            (Sev 1) — Node pool at 0 nodes"
echo "    3. alert-pod-unschedulable-${PREFIX}        (Sev 1) — Pods can't schedule"
echo "    4. alert-metric-nodepool-count-${PREFIX}    (Sev 0) — Metric: node count < 1"
echo ""
echo "  All alerts → Action Group: ag-${PREFIX}-sre → SRE Agent"
echo ""
echo "  Verify alerts:"
echo "    ./scripts/setup-node-alerts.sh --verify"
echo ""
echo "  Trigger a test:"
echo "    ./scripts/start-node-failure.sh"
echo ""
