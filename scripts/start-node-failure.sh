#!/bin/bash
set -euo pipefail

###############################################################################
# Contoso Meals - Node Pool Failure Chaos Experiment
#
# Simulates a catastrophic user node pool failure by:
#   1. Starting the Chaos Studio node pool experiment (pod-kills on workload nodes)
#   2. Scaling the 'workload' user node pool to 0 nodes via az aks nodepool scale
#
# This creates a realistic "node lost" scenario that the Azure SRE Agent
# should detect, investigate, and remediate by scaling the pool back to 1.
#
# Prerequisites:
#   - AKS cluster deployed with 'workload' user node pool
#   - Chaos Studio experiment 'exp-contoso-meals-nodepool-failure' exists
#   - Azure CLI authenticated with appropriate permissions
#
# Usage:
#   ./scripts/start-node-failure.sh                  # full: chaos + scale to 0
#   ./scripts/start-node-failure.sh --chaos-only     # only start chaos experiment
#   ./scripts/start-node-failure.sh --scale-only     # only scale pool to 0
#   ./scripts/start-node-failure.sh --restore         # restore pool to 1 node
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Defaults
SKIP_CHAOS=false
SKIP_SCALE=false
RESTORE=false
NODE_POOL_NAME="workload"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --chaos-only) SKIP_SCALE=true; shift ;;
    --scale-only) SKIP_CHAOS=true; shift ;;
    --restore)    RESTORE=true; shift ;;
    --pool-name)  NODE_POOL_NAME="$2"; shift 2 ;;
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
EXPERIMENT_NAME="exp-${PREFIX}-nodepool-failure"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Node Pool Failure Chaos Experiment                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  AKS Cluster:    ${AKS_CLUSTER}"
echo "  Resource Group:  ${RESOURCE_GROUP}"
echo "  Node Pool:       ${NODE_POOL_NAME}"
echo "  Experiment:      ${EXPERIMENT_NAME}"
echo ""

# ─── Restore Mode ──────────────────────────────────────────────────
if [ "$RESTORE" = true ]; then
  echo "━━━ Restoring node pool '${NODE_POOL_NAME}' to 1 node ━━━"
  echo ""
  
  CURRENT_COUNT=$(az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name "$NODE_POOL_NAME" \
    --query "count" -o tsv 2>/dev/null || echo "0")
  echo "  Current node count: ${CURRENT_COUNT}"
  
  if [ "$CURRENT_COUNT" -ge 1 ]; then
    echo "  Node pool already has ${CURRENT_COUNT} node(s). No action needed."
    exit 0
  fi
  
  echo "  Scaling node pool to 1..."
  az aks nodepool scale \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name "$NODE_POOL_NAME" \
    --node-count 1 \
    --no-wait \
    --only-show-errors
  
  echo "  ✓ Scale operation initiated. Nodes will be ready in ~2-3 minutes."
  echo ""
  echo "  Monitor progress:"
  echo "    az aks nodepool show -g ${RESOURCE_GROUP} --cluster-name ${AKS_CLUSTER} -n ${NODE_POOL_NAME} --query '{count:count,provisioningState:provisioningState}'"
  exit 0
fi

# ─── Pre-flight checks ─────────────────────────────────────────────
echo "━━━ Pre-flight Checks ━━━"

# Check node pool exists
echo -n "  Node pool '${NODE_POOL_NAME}': "
POOL_INFO=$(az aks nodepool show \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name "$NODE_POOL_NAME" \
  --query "{count:count, vmSize:vmSize, mode:mode, provisioningState:provisioningState}" \
  -o json 2>/dev/null || echo "")

if [ -z "$POOL_INFO" ]; then
  echo "NOT FOUND"
  echo "  ERROR: Node pool '${NODE_POOL_NAME}' does not exist on cluster '${AKS_CLUSTER}'."
  echo "  Deploy infrastructure first: ./scripts/deploy.sh"
  exit 1
fi

CURRENT_COUNT=$(echo "$POOL_INFO" | jq -r '.count')
POOL_MODE=$(echo "$POOL_INFO" | jq -r '.mode')
echo "found (${POOL_MODE} mode, ${CURRENT_COUNT} node(s))"

if [ "$CURRENT_COUNT" -eq 0 ]; then
  echo "  WARNING: Node pool already has 0 nodes. Nothing to destroy."
  echo "  Use --restore to scale back to 1."
  exit 0
fi

# Check pods on workload nodes
echo "  Pods on workload nodes:"
kubectl get pods -n production -o wide 2>/dev/null | grep -i "workload\|NAME" | sed 's/^/    /' || echo "    (no pods found on workload nodes)"
echo ""

if [ "$SKIP_CHAOS" = false ]; then
  echo -n "  Chaos experiment: "
  EXP_EXISTS=$(az rest \
    --method get \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}?api-version=2024-01-01" \
    --query "name" -o tsv 2>/dev/null || echo "")
  if [ -n "$EXP_EXISTS" ]; then
    echo "found (${EXPERIMENT_NAME})"
  else
    echo "NOT FOUND — will skip chaos experiment"
    SKIP_CHAOS=true
  fi
fi
echo ""

# ─── Step 1: Start Chaos Studio experiment ──────────────────────────
if [ "$SKIP_CHAOS" = false ]; then
  echo "━━━ Step 1: Starting Chaos Studio experiment ━━━"
  echo "  Experiment: ${EXPERIMENT_NAME}"
  
  az rest \
    --method post \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}/start?api-version=2024-01-01" \
    --only-show-errors 2>/dev/null

  echo "  ✓ Chaos experiment started — pods on workload nodes will be killed"
  echo "  Duration: ~5 minutes"
  echo ""
  
  # Brief wait for chaos to take effect
  echo "  Waiting 30s for chaos to destabilize pods..."
  sleep 30
fi

# ─── Step 2: Scale node pool to 0 ──────────────────────────────────
if [ "$SKIP_SCALE" = false ]; then
  echo "━━━ Step 2: Scaling '${NODE_POOL_NAME}' node pool to 0 ━━━"
  echo "  This will:"
  echo "    - Drain all workloads from the node pool"
  echo "    - Deallocate all VMs in the underlying VMSS"
  echo "    - Force pods into Pending state (no schedulable nodes)"
  echo ""
  
  az aks nodepool scale \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name "$NODE_POOL_NAME" \
    --node-count 0 \
    --no-wait \
    --only-show-errors

  echo "  ✓ Scale-to-0 initiated for node pool '${NODE_POOL_NAME}'"
  echo ""
fi

# ─── Summary ────────────────────────────────────────────────────────
echo "━━━ Chaos Injection Summary ━━━"
echo ""
echo "  ⚠  Node pool '${NODE_POOL_NAME}' is being scaled to 0"
echo "  ⚠  All pods scheduled on workload nodes will be evicted"
echo ""
echo "  Expected SRE Agent detection chain:"
echo "    1. Azure Monitor alert fires: 'AKS Node Pool Scaled to Zero'"
echo "    2. SRE Agent receives alert via Action Group webhook"
echo "    3. SRE Agent creates P1 Jira ticket (CONTOSO project)"
echo "    4. SRE Agent investigates: queries AKS node pool status"
echo "    5. SRE Agent remediates: scales node pool back to 1"
echo "    6. SRE Agent verifies: confirms pods are Running"
echo "    7. SRE Agent resolves: closes Jira ticket with summary"
echo ""
echo "  Monitor:"
echo "    kubectl get nodes -w"
echo "    kubectl get pods -n production -w"
echo "    az aks nodepool show -g ${RESOURCE_GROUP} --cluster-name ${AKS_CLUSTER} -n ${NODE_POOL_NAME} --query '{count:count,provisioningState:provisioningState}'"
echo ""
echo "  Restore (manual):"
echo "    ./scripts/start-node-failure.sh --restore"
echo "    # OR: az aks nodepool scale -g ${RESOURCE_GROUP} --cluster-name ${AKS_CLUSTER} -n ${NODE_POOL_NAME} --node-count 1"
echo ""
