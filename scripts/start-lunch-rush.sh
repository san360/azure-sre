#!/bin/bash
set -euo pipefail

###############################################################################
# Contoso Meals - Part 3: "Lunch Rush Under Fire"
# Triggers Azure Load Testing + Chaos Studio pod-kill experiment.
#
# Flow:
#   1. Verify AKS pods are healthy
#   2. Start Azure Load Testing "lunch-rush" test (100 VUs, 10 min)
#   3. Wait for load to ramp up (~2 min)
#   4. Start Chaos Studio experiment (payment-service pod-kill)
#   5. Monitor pod health + load test status during the chaos window
#   6. After chaos ends, show recovery summary
#
# Usage:
#   ./scripts/start-lunch-rush.sh                    # full demo: load + chaos
#   ./scripts/start-lunch-rush.sh --load-only        # skip chaos, load only
#   ./scripts/start-lunch-rush.sh --chaos-only       # skip load, chaos only
#   ./scripts/start-lunch-rush.sh --chaos-delay 90   # wait 90s before chaos
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Defaults
CHAOS_DELAY_SEC=120
SKIP_LOAD=false
SKIP_CHAOS=false
LOAD_TEST_ID="lunch-rush"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --load-only)   SKIP_CHAOS=true; shift ;;
    --chaos-only)  SKIP_LOAD=true; shift ;;
    --chaos-delay) CHAOS_DELAY_SEC="$2"; shift 2 ;;
    --test-id)     LOAD_TEST_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Load .env ──────────────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "ERROR: .env file not found. Run ./scripts/post-deploy.sh first."
  exit 1
fi

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-contoso-meals}"
AKS_CLUSTER="${AKS_CLUSTER:-aks-contoso-meals}"
LOAD_TEST_RESOURCE="${LOAD_TEST_RESOURCE:-lt-contoso-meals}"
EXPERIMENT_NAME="exp-contoso-meals-pod-kill"
TEST_RUN_ID="${LOAD_TEST_ID}-$(date +%Y%m%d-%H%M%S)"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Part 3: Lunch Rush Under Fire                         ║"
echo "║   Azure Load Testing + Chaos Studio                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  Load Test:  ${LOAD_TEST_ID} (Azure Load Testing)  skip=${SKIP_LOAD}"
echo "  Test Run:   ${TEST_RUN_ID}"
echo "  Chaos:      payment-service pod-kill for 5 min     skip=${SKIP_CHAOS}"
echo "  Chaos delay: ${CHAOS_DELAY_SEC}s after load begins"
echo ""

# ─── Step 1: Pre-flight checks ─────────────────────────────────────
echo "━━━ Step 1: Pre-flight checks ━━━"

echo -n "  AKS pods (production): "
POD_STATUS=$(kubectl get pods -n production --no-headers 2>/dev/null || echo "")
TOTAL_PODS=$(echo "$POD_STATUS" | grep -c "." || echo "0")
READY_PODS=$(echo "$POD_STATUS" | grep -c "Running" || echo "0")
echo "${READY_PODS}/${TOTAL_PODS} Running"

if [ "$READY_PODS" -eq 0 ]; then
  echo "  ERROR: No running pods in production namespace. Deploy first."
  exit 1
fi

echo "  Pod details:"
kubectl get pods -n production -o wide 2>/dev/null | sed 's/^/    /'
echo ""

if [ "$SKIP_CHAOS" = false ]; then
  echo -n "  Chaos experiment: "
  EXP_EXISTS=$(az rest \
    --method get \
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}?api-version=2024-01-01" \
    --query "name" -o tsv 2>/dev/null || echo "")
  if [ -n "$EXP_EXISTS" ]; then
    echo "found (${EXPERIMENT_NAME})"
  else
    echo "NOT FOUND — will skip chaos"
    SKIP_CHAOS=true
  fi
fi

if [ "$SKIP_LOAD" = false ]; then
  echo -n "  Azure Load Test: "
  LT_EXISTS=$(az load test show \
    --load-test-resource "$LOAD_TEST_RESOURCE" \
    --resource-group "$RESOURCE_GROUP" \
    --test-id "$LOAD_TEST_ID" \
    --query "testId" -o tsv 2>/dev/null || echo "")
  if [ -n "$LT_EXISTS" ]; then
    echo "found (${LOAD_TEST_ID} in ${LOAD_TEST_RESOURCE})"
  else
    echo "NOT FOUND — test '${LOAD_TEST_ID}' not configured in ${LOAD_TEST_RESOURCE}"
    echo "  Run ./scripts/post-deploy.sh to configure load tests, or create manually."
    SKIP_LOAD=true
  fi
fi

echo ""

# ─── Step 2: Start Azure Load Testing run (background) ─────────────
LOAD_TEST_RUNNING=false
if [ "$SKIP_LOAD" = false ]; then
  echo "━━━ Step 2: Starting Azure Load Testing run ━━━"
  echo "  Resource:  ${LOAD_TEST_RESOURCE}"
  echo "  Test:      ${LOAD_TEST_ID}"
  echo "  Run ID:    ${TEST_RUN_ID}"
  echo ""

  az load test-run create \
    --load-test-resource "$LOAD_TEST_RESOURCE" \
    --resource-group "$RESOURCE_GROUP" \
    --test-id "$LOAD_TEST_ID" \
    --test-run-id "$TEST_RUN_ID" \
    --display-name "Lunch Rush - Part 3 Demo $(date +%H:%M)" \
    --description "Load test triggered by start-lunch-rush.sh for Part 3 demo" \
    --no-wait \
    --only-show-errors -o none 2>&1 || {
      echo "  WARNING: Failed to start load test run. Continuing without load..."
    }

  LOAD_TEST_RUNNING=true
  echo "  Load test run started (async). Monitoring in background."
  echo ""

  # Wait for test to reach EXECUTING state
  echo -n "  Waiting for test to start executing"
  for i in $(seq 1 20); do
    LT_STATUS=$(az load test-run show \
      --load-test-resource "$LOAD_TEST_RESOURCE" \
      --resource-group "$RESOURCE_GROUP" \
      --test-run-id "$TEST_RUN_ID" \
      --query "status" -o tsv 2>/dev/null || echo "UNKNOWN")
    if [ "$LT_STATUS" = "EXECUTING" ] || [ "$LT_STATUS" = "DONE" ] || [ "$LT_STATUS" = "FAILED" ]; then
      echo ""
      echo "  Load test status: ${LT_STATUS}"
      break
    fi
    echo -n "."
    sleep 10
  done
  echo ""
else
  echo "━━━ Step 2: Skipped (--chaos-only) ━━━"
  echo ""
fi

# ─── Step 3: Wait for load to ramp up, then start chaos ────────────
if [ "$SKIP_CHAOS" = false ]; then
  echo "━━━ Step 3: Waiting ${CHAOS_DELAY_SEC}s for load to ramp up before chaos ━━━"

  for i in $(seq "$CHAOS_DELAY_SEC" -10 1); do
    echo -ne "  Chaos starts in ${i}s...  \r"
    sleep $(( i > 10 ? 10 : i ))
  done
  echo ""
  echo ""

  # ─── Step 4: Start Chaos Studio experiment ──────────────────────
  echo "━━━ Step 4: Starting Chaos Studio experiment ━━━"
  echo "  Experiment: ${EXPERIMENT_NAME}"
  echo "  Action:     Kill ALL payment-service pods (every ~60s for 5 min)"
  echo ""

  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  EXPERIMENT_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}"

  # Start the experiment
  CHAOS_RESPONSE=$(az rest \
    --method post \
    --url "https://management.azure.com${EXPERIMENT_ID}/start?api-version=2024-01-01" \
    --output json 2>&1 || echo '{"error":"failed to start"}')

  CHAOS_STATUS_URL=$(echo "$CHAOS_RESPONSE" | jq -r '.statusUrl // empty' 2>/dev/null || echo "")

  if [ -n "$CHAOS_STATUS_URL" ]; then
    echo "  ✓ Chaos experiment started successfully"
    echo "  Status URL: ${CHAOS_STATUS_URL}"
  else
    echo "  Chaos experiment triggered (checking status...)"
    # Fall back to checking experiment status directly
    CHAOS_STATUS_URL="https://management.azure.com${EXPERIMENT_ID}/statuses?api-version=2024-01-01"
  fi
  echo ""

  # --- Chaos Experiment Details Log ---
  echo "  ─── Chaos Experiment Details ───"
  CHAOS_DETAIL=$(az rest \
    --method get \
    --url "https://management.azure.com${EXPERIMENT_ID}?api-version=2024-01-01" \
    --query "{name:name, status:properties.provisioningState, steps:properties.steps[0].branches[0].actions[0].parameters[0].value}" \
    -o json 2>/dev/null || echo '{}')
  echo "  Experiment JSON:"
  echo "$CHAOS_DETAIL" | jq '.' 2>/dev/null | sed 's/^/    /' || echo "    (could not parse)"
  echo ""

  # Show the Chaos Mesh jsonSpec clearly
  JSONSPEC=$(echo "$CHAOS_DETAIL" | jq -r '.steps // empty' 2>/dev/null || echo '')
  if [ -n "$JSONSPEC" ]; then
    echo "  Chaos Mesh spec:"
    echo "$JSONSPEC" | jq '.' 2>/dev/null | sed 's/^/    /' || echo "    $JSONSPEC"
    echo ""
  fi

  # ─── Step 5: Monitor during chaos window ────────────────────────
  echo "━━━ Step 5: Monitoring (chaos runs for ~5 minutes) ━━━"
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────┐"
  echo "  │  DEMO TIP: Switch to SRE Agent and ask:                │"
  echo "  │                                                         │"
  echo "  │  \"Customers are reporting that their food orders are    │"
  echo "  │   failing at checkout. The menu seems to work fine.     │"
  echo "  │   Can you investigate what's happening with order       │"
  echo "  │   processing and payments?\"                             │"
  echo "  │                                                         │"
  echo "  │  The agent will find the pod-kill chaos, correlate      │"
  echo "  │  with Application Insights errors, and explain the      │"
  echo "  │  business impact.                                       │"
  echo "  └─────────────────────────────────────────────────────────┘"
  echo ""

  CHAOS_DURATION=300  # 5 minutes
  MONITOR_INTERVAL=30
  ELAPSED=0

  while [ $ELAPSED -lt $CHAOS_DURATION ]; do
    sleep $MONITOR_INTERVAL
    ELAPSED=$((ELAPSED + MONITOR_INTERVAL))
    REMAINING=$((CHAOS_DURATION - ELAPSED))

    # Check pod status
    RUNNING=$(kubectl get pods -n production -l app=payment-service --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL=$(kubectl get pods -n production -l app=payment-service --no-headers 2>/dev/null | grep -c . || echo "0")
    RESTARTS=$(kubectl get pods -n production -l app=payment-service --no-headers 2>/dev/null | awk '{sum += $4} END {print sum+0}' || echo "0")

    # Check load test status if running
    LOAD_STATS=""
    if [ "$LOAD_TEST_RUNNING" = true ]; then
      LT_STATUS=$(az load test-run show \
        --load-test-resource "$LOAD_TEST_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --test-run-id "$TEST_RUN_ID" \
        --query "status" -o tsv 2>/dev/null || echo "UNKNOWN")
      LOAD_STATS="ALT: ${LT_STATUS}"
    fi

    # Get pod events (kills/restarts)
    RECENT_EVENTS=$(kubectl get events -n production --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' 2>/dev/null | grep payment-service | tail -3 || echo "")

    printf "  [%3ds/%ds] payment-service pods: %s/%s Running | restarts: %s" \
      "$ELAPSED" "$CHAOS_DURATION" "$RUNNING" "$TOTAL" "$RESTARTS"
    [ -n "$LOAD_STATS" ] && printf " | load: %s" "$LOAD_STATS"
    echo ""

    # Show recent pod events if any
    if [ -n "$RECENT_EVENTS" ]; then
      echo "$RECENT_EVENTS" | while IFS= read -r line; do
        echo "    ↳ $line"
      done
    fi

    # Check chaos experiment execution status
    if [ $(( ELAPSED % 60 )) -eq 0 ]; then
      CHAOS_EXEC_STATUS=$(az rest \
        --method get \
        --url "https://management.azure.com${EXPERIMENT_ID}/statuses?api-version=2024-01-01" \
        --query "value[0].{status:status, startedAt:properties.startedAt}" \
        -o json 2>/dev/null || echo '{}')
      echo "    ⚡ Chaos status: $(echo "$CHAOS_EXEC_STATUS" | jq -r '.status // "unknown"' 2>/dev/null)"
    fi
  done

  echo ""
  echo "  ✓ Chaos window complete (5 min)"
  echo ""
else
  echo "━━━ Step 3-5: Skipped (--load-only) ━━━"
  echo ""
fi

# ─── Step 6: Post-chaos summary ────────────────────────────────────
echo "━━━ Step 6: Recovery summary ━━━"
echo ""

echo "  Payment-service pods:"
kubectl get pods -n production -l app=payment-service 2>/dev/null | sed 's/^/    /'
echo ""

echo "  Order-api pods:"
kubectl get pods -n production -l app=order-api 2>/dev/null | sed 's/^/    /'
echo ""

# Show load test results
if [ "$LOAD_TEST_RUNNING" = true ]; then
  echo "  Azure Load Test run: ${TEST_RUN_ID}"
  LT_FINAL=$(az load test-run show \
    --load-test-resource "$LOAD_TEST_RESOURCE" \
    --resource-group "$RESOURCE_GROUP" \
    --test-run-id "$TEST_RUN_ID" \
    --query "{status:status, vUsers:virtualUsers, startTime:startDateTime, endTime:endDateTime}" \
    -o table 2>/dev/null || echo "  Could not fetch test run status")
  echo "$LT_FINAL" | sed 's/^/    /'
  echo ""
  echo "  View results: Azure Portal → Load Testing → ${LOAD_TEST_RESOURCE} → Test runs → ${TEST_RUN_ID}"
  echo ""
fi

# Final demo prompts
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Next Steps for Demo:                                    ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║                                                           ║"
echo "║  1. Ask SRE Agent to investigate (if not already):       ║"
echo "║     \"Customers report food orders failing at checkout.   ║"
echo "║      Menu works fine. Investigate order processing and   ║"
echo "║      payments.\"                                          ║"
echo "║                                                           ║"
echo "║  2. Closed-loop actions:                                  ║"
echo "║     \"Send a summary to Teams. Include business impact —  ║"
echo "║      what % of orders failed during the chaos. Create a  ║"
echo "║      GitHub issue recommending a PodDisruptionBudget     ║"
echo "║      for payment-service.\"                               ║"
echo "║                                                           ║"
echo "║  3. Verify recovery:                                      ║"
echo "║     \"The chaos experiment ended. Verify error rates are  ║"
echo "║      back to normal in Application Insights.\"            ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Cleanup trap — stop load test on script exit if still running
cleanup() {
  if [ "$LOAD_TEST_RUNNING" = true ]; then
    LT_STATUS=$(az load test-run show \
      --load-test-resource "$LOAD_TEST_RESOURCE" \
      --resource-group "$RESOURCE_GROUP" \
      --test-run-id "$TEST_RUN_ID" \
      --query "status" -o tsv 2>/dev/null || echo "DONE")
    if [ "$LT_STATUS" = "EXECUTING" ] || [ "$LT_STATUS" = "PROVISIONING" ] || [ "$LT_STATUS" = "CONFIGURING" ]; then
      echo "Stopping load test run (${TEST_RUN_ID})..."
      az load test-run stop \
        --load-test-resource "$LOAD_TEST_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --test-run-id "$TEST_RUN_ID" \
        --only-show-errors -o none 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

# Wait for load test to finish if still running
if [ "$LOAD_TEST_RUNNING" = true ]; then
  LT_STATUS=$(az load test-run show \
    --load-test-resource "$LOAD_TEST_RESOURCE" \
    --resource-group "$RESOURCE_GROUP" \
    --test-run-id "$TEST_RUN_ID" \
    --query "status" -o tsv 2>/dev/null || echo "DONE")
  if [ "$LT_STATUS" = "EXECUTING" ]; then
    echo "Load test still running. Press Ctrl+C to stop it and exit."
    echo "Waiting for test run to complete..."
    while true; do
      sleep 30
      LT_STATUS=$(az load test-run show \
        --load-test-resource "$LOAD_TEST_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --test-run-id "$TEST_RUN_ID" \
        --query "status" -o tsv 2>/dev/null || echo "DONE")
      echo "  Load test status: ${LT_STATUS}"
      if [ "$LT_STATUS" != "EXECUTING" ] && [ "$LT_STATUS" != "PROVISIONING" ] && [ "$LT_STATUS" != "CONFIGURING" ]; then
        echo "  Load test run complete."
        break
      fi
    done
  fi
fi
