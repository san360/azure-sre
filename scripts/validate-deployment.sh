#!/bin/bash
###############################################################################
# Contoso Meals SRE — Deployment Validation Script
# Validates all Azure resources, Kubernetes workloads, service endpoints,
# monitoring, chaos infrastructure, and SRE Agent configuration.
#
# Usage:
#   ./scripts/validate-deployment.sh                # Full validation
#   ./scripts/validate-deployment.sh --quick        # Skip endpoint tests
#   ./scripts/validate-deployment.sh --verbose      # Show extra details
#
# Inspired by: https://github.com/matthansen0/azure-sre-agent-sandbox/blob/main/scripts/validate-deployment.ps1
###############################################################################

set -uo pipefail

# ─── Configuration ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

QUICK_MODE=false
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --quick)   QUICK_MODE=true ;;
    --verbose) VERBOSE=true ;;
  esac
done

# Counters
PASS=0
FAIL=0
WARN=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { ((PASS++)); echo -e "  ${GREEN}✔ PASS${NC}  $1"; }
fail()  { ((FAIL++)); echo -e "  ${RED}✘ FAIL${NC}  $1"; }
warn()  { ((WARN++)); echo -e "  ${YELLOW}⚠ WARN${NC}  $1"; }
skip()  { ((SKIP++)); echo -e "  ${CYAN}⊘ SKIP${NC}  $1"; }
info()  { echo -e "  ${CYAN}ℹ${NC} $1"; }
section() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ─── Resolve Environment ───────────────────────────────────────────
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || azd env get-value resourceGroupName 2>/dev/null || echo "rg-contoso-meals")
AKS_CLUSTER_NAME=$(azd env get-value AZURE_AKS_CLUSTER_NAME 2>/dev/null || echo "aks-contoso-meals")
PREFIX="contoso-meals"
SANITIZED_PREFIX="contosomeals"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Contoso Meals — Deployment Validation          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  AKS Cluster:     $AKS_CLUSTER_NAME"
echo "  Timestamp:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$QUICK_MODE" = true ] && echo "  Mode:            Quick (endpoint tests skipped)"
echo ""

###############################################################################
# 1. AZURE RESOURCE EXISTENCE
###############################################################################
section "1. Azure Resource Existence"

check_resource() {
  local DISPLAY_NAME="$1"
  local RESOURCE_TYPE="$2"
  local RESOURCE_NAME="$3"

  if az resource show --resource-group "$RESOURCE_GROUP" --resource-type "$RESOURCE_TYPE" --name "$RESOURCE_NAME" -o none 2>/dev/null; then
    pass "$DISPLAY_NAME ($RESOURCE_NAME)"
  else
    fail "$DISPLAY_NAME ($RESOURCE_NAME) — not found"
  fi
}

# Core compute
check_resource "AKS Cluster" "Microsoft.ContainerService/managedClusters" "aks-${PREFIX}"
check_resource "Container App Environment" "Microsoft.App/managedEnvironments" "cae-${PREFIX}"

# Container Apps
check_resource "menu-api Container App" "Microsoft.App/containerApps" "menu-api"
check_resource "web-ui Container App" "Microsoft.App/containerApps" "web-ui"

# Data stores
check_resource "PostgreSQL Flexible Server" "Microsoft.DBforPostgreSQL/flexibleServers" "psql-${PREFIX}-db"
check_resource "Cosmos DB Account" "Microsoft.DocumentDB/databaseAccounts" "cosmos-${PREFIX}"

# Registry & secrets
check_resource "Container Registry" "Microsoft.ContainerRegistry/registries" "acr${SANITIZED_PREFIX}"
check_resource "Key Vault" "Microsoft.KeyVault/vaults" "kv-${SANITIZED_PREFIX}sc"

# Monitoring
check_resource "Log Analytics Workspace" "Microsoft.OperationalInsights/workspaces" "law-${PREFIX}"
check_resource "Application Insights" "Microsoft.Insights/components" "appi-${PREFIX}"
check_resource "Load Testing" "Microsoft.LoadTestService/loadTests" "lt-${PREFIX}"

# Identity
check_resource "SRE Agent Managed Identity" "Microsoft.ManagedIdentity/userAssignedIdentities" "id-${PREFIX}-sre-agent"

# Storage (Jira)
check_resource "Storage Account (Jira)" "Microsoft.Storage/storageAccounts" "st${SANITIZED_PREFIX}"

# Jira & MCP (optional)
JIRA_EXISTS=$(az containerapp show --name jira-sm --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")
if [ -n "$JIRA_EXISTS" ]; then
  pass "jira-sm Container App"
else
  warn "jira-sm Container App — not found (optional)"
fi

MCP_EXISTS=$(az containerapp show --name mcp-atlassian --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")
if [ -n "$MCP_EXISTS" ]; then
  pass "mcp-atlassian Container App"
else
  warn "mcp-atlassian Container App — not found (optional)"
fi

###############################################################################
# 2. SRE AGENT
###############################################################################
section "2. Azure SRE Agent"

SRE_AGENT_ID=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.App/agents" --query "[0].id" -o tsv 2>/dev/null || echo "")
if [ -n "$SRE_AGENT_ID" ]; then
  pass "SRE Agent resource exists (${PREFIX}-sre)"
  
  # Check identity assignment
  SRE_MI_PRINCIPAL=$(az identity show --name "id-${PREFIX}-sre-agent" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv 2>/dev/null || echo "")
  if [ -n "$SRE_MI_PRINCIPAL" ]; then
    pass "SRE Agent managed identity has principalId"
    
    # Check role assignments on the resource group
    ROLE_COUNT=$(az role assignment list --assignee "$SRE_MI_PRINCIPAL" --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [ "$ROLE_COUNT" -gt 0 ]; then
      pass "SRE Agent identity has $ROLE_COUNT role assignment(s) on resource group"
    else
      fail "SRE Agent identity has no role assignments on resource group"
    fi
  else
    fail "SRE Agent managed identity principalId not found"
  fi
else
  warn "SRE Agent resource not deployed (optional)"
fi

###############################################################################
# 3. COSMOS DB DATABASES & CONTAINERS
###############################################################################
section "3. Cosmos DB Configuration"

COSMOS_ACCOUNT="cosmos-${PREFIX}"

# Check catalogdb database
CATALOG_DB=$(az cosmosdb sql database show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --name "catalogdb" --query name -o tsv 2>/dev/null || echo "")
if [ "$CATALOG_DB" = "catalogdb" ]; then
  pass "Cosmos DB database 'catalogdb' exists"
else
  fail "Cosmos DB database 'catalogdb' — not found"
fi

# Check containers
for CONTAINER_NAME in "restaurants" "menus"; do
  CONTAINER=$(az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name "catalogdb" --name "$CONTAINER_NAME" --query name -o tsv 2>/dev/null || echo "")
  if [ "$CONTAINER" = "$CONTAINER_NAME" ]; then
    pass "Cosmos DB container '$CONTAINER_NAME'"
    if [ "$VERBOSE" = true ]; then
      PK=$(az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name "catalogdb" --name "$CONTAINER_NAME" --query "resource.partitionKey.paths[0]" -o tsv 2>/dev/null || echo "")
      info "  Partition key: $PK"
    fi
  else
    fail "Cosmos DB container '$CONTAINER_NAME' — not found"
  fi
done

###############################################################################
# 4. POSTGRESQL DATABASES
###############################################################################
section "4. PostgreSQL Configuration"

PG_SERVER="psql-${PREFIX}-db"
PG_FQDN=$(az postgres flexible-server show --name "$PG_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv 2>/dev/null || echo "")

if [ -n "$PG_FQDN" ]; then
  pass "PostgreSQL server reachable ($PG_FQDN)"
  
  # Check databases exist
  for DB_NAME in "ordersdb" "jiradb"; do
    DB=$(az postgres flexible-server db show --server-name "$PG_SERVER" --resource-group "$RESOURCE_GROUP" --database-name "$DB_NAME" --query name -o tsv 2>/dev/null || echo "")
    if [ "$DB" = "$DB_NAME" ]; then
      pass "PostgreSQL database '$DB_NAME'"
    else
      fail "PostgreSQL database '$DB_NAME' — not found"
    fi
  done
  
  # Check server status
  PG_STATE=$(az postgres flexible-server show --name "$PG_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv 2>/dev/null || echo "")
  if [ "$PG_STATE" = "Ready" ]; then
    pass "PostgreSQL server state: Ready"
  else
    fail "PostgreSQL server state: ${PG_STATE:-unknown}"
  fi
else
  fail "PostgreSQL server not found or not reachable"
fi

###############################################################################
# 5. AKS CLUSTER HEALTH
###############################################################################
section "5. AKS Cluster Health"

# Cluster provisioning state
AKS_STATE=$(az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv 2>/dev/null || echo "")
if [ "$AKS_STATE" = "Succeeded" ]; then
  pass "AKS cluster provisioning state: Succeeded"
else
  fail "AKS cluster provisioning state: ${AKS_STATE:-unknown}"
fi

# Node pools
for POOL in "system" "workload"; do
  POOL_STATE=$(az aks nodepool show --cluster-name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --nodepool-name "$POOL" --query provisioningState -o tsv 2>/dev/null || echo "")
  POOL_COUNT=$(az aks nodepool show --cluster-name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --nodepool-name "$POOL" --query count -o tsv 2>/dev/null || echo "0")
  if [ "$POOL_STATE" = "Succeeded" ]; then
    pass "Node pool '$POOL' — Succeeded ($POOL_COUNT nodes)"
  else
    fail "Node pool '$POOL' — ${POOL_STATE:-not found} ($POOL_COUNT nodes)"
  fi
done

# Get credentials for kubectl checks
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing --only-show-errors 2>/dev/null || true

###############################################################################
# 6. KUBERNETES NAMESPACE & SECRETS
###############################################################################
section "6. Kubernetes Namespace & Secrets"

# Production namespace
NS=$(kubectl get namespace production -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ "$NS" = "production" ]; then
  pass "Namespace 'production' exists"
else
  fail "Namespace 'production' not found"
fi

# Secrets
SECRET=$(kubectl get secret contoso-meals-secrets -n production -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ "$SECRET" = "contoso-meals-secrets" ]; then
  pass "Secret 'contoso-meals-secrets' exists"
  
  # Check expected keys
  for KEY in "orders-db-connection-string" "appinsights-connection-string"; do
    HAS_KEY=$(kubectl get secret contoso-meals-secrets -n production -o jsonpath="{.data['$KEY']}" 2>/dev/null || echo "")
    if [ -n "$HAS_KEY" ]; then
      pass "Secret key '$KEY' present"
    else
      fail "Secret key '$KEY' missing"
    fi
  done
else
  fail "Secret 'contoso-meals-secrets' not found in production namespace"
fi

###############################################################################
# 7. KUBERNETES DEPLOYMENTS & PODS
###############################################################################
section "7. Kubernetes Deployments & Pods"

for DEPLOY in "order-api" "payment-service"; do
  # Deployment exists and has ready replicas
  READY=$(kubectl get deployment "$DEPLOY" -n production -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get deployment "$DEPLOY" -n production -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  
  if [ "$READY" = "$DESIRED" ] && [ "$DESIRED" != "0" ]; then
    pass "$DEPLOY deployment — $READY/$DESIRED replicas ready"
  elif [ "$READY" != "0" ]; then
    warn "$DEPLOY deployment — $READY/$DESIRED replicas ready (partial)"
  else
    fail "$DEPLOY deployment — 0/$DESIRED replicas ready"
  fi
done

# Check for unhealthy pods
PROBLEM_PODS=$(kubectl get pods -n production --field-selector='status.phase!=Running,status.phase!=Succeeded' --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$PROBLEM_PODS" -eq 0 ]; then
  pass "No unhealthy pods in production namespace"
else
  warn "$PROBLEM_PODS unhealthy pod(s) detected in production namespace"
  if [ "$VERBOSE" = true ]; then
    kubectl get pods -n production --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || true
  fi
fi

# Check for CrashLoopBackOff
CRASH_PODS=$(kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.state.waiting.reason}{end}{"\n"}{end}' 2>/dev/null | grep -c "CrashLoopBackOff" || true)
CRASH_PODS=${CRASH_PODS:-0}
if [ "$CRASH_PODS" -eq 0 ]; then
  pass "No CrashLoopBackOff pods"
else
  fail "$CRASH_PODS pod(s) in CrashLoopBackOff"
fi

###############################################################################
# 8. KUBERNETES SERVICES & LOAD BALANCERS
###############################################################################
section "8. Kubernetes Services & LoadBalancers"

ORDER_API_IP=""
PAYMENT_SERVICE_IP=""

for SVC in "order-api" "payment-service"; do
  SVC_TYPE=$(kubectl get svc "$SVC" -n production -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
  EXTERNAL_IP=$(kubectl get svc "$SVC" -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  
  if [ "$SVC_TYPE" = "LoadBalancer" ] && [ -n "$EXTERNAL_IP" ]; then
    pass "$SVC LoadBalancer — external IP: $EXTERNAL_IP"
    if [ "$SVC" = "order-api" ]; then ORDER_API_IP="$EXTERNAL_IP"; fi
    if [ "$SVC" = "payment-service" ]; then PAYMENT_SERVICE_IP="$EXTERNAL_IP"; fi
  elif [ "$SVC_TYPE" = "LoadBalancer" ]; then
    warn "$SVC LoadBalancer — external IP not yet assigned"
  else
    fail "$SVC service type is '$SVC_TYPE' (expected LoadBalancer)"
  fi
done

###############################################################################
# 9. CONTAINER APP STATUS
###############################################################################
section "9. Container App Status"

for APP in "menu-api" "web-ui"; do
  APP_STATE=$(az containerapp show --name "$APP" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv 2>/dev/null || echo "")
  APP_FQDN=$(az containerapp show --name "$APP" --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
  REPLICAS=$(az containerapp replica list --name "$APP" --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [ -n "$APP_FQDN" ]; then
    pass "$APP — FQDN: $APP_FQDN (replicas: ${REPLICAS:-?})"
  else
    fail "$APP — no FQDN assigned"
  fi
done

# Optional: Jira & MCP
for APP in "jira-sm" "mcp-atlassian"; do
  APP_FQDN=$(az containerapp show --name "$APP" --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
  if [ -n "$APP_FQDN" ]; then
    pass "$APP — FQDN: $APP_FQDN"
  else
    skip "$APP — not deployed or no FQDN"
  fi
done

###############################################################################
# 10. CONTAINER APP ENVIRONMENT VARIABLES
###############################################################################
section "10. Container App Environment Variables"

# menu-api — check Cosmos DB connection string is injected (not placeholder)
MENU_COSMOS_ENV=$(az containerapp show --name menu-api --resource-group "$RESOURCE_GROUP" \
  --query "properties.template.containers[0].env[?name=='CosmosDb__ConnectionString'].value | [0]" -o tsv 2>/dev/null || echo "")
if [ -n "$MENU_COSMOS_ENV" ] && [ "$MENU_COSMOS_ENV" != "null" ]; then
  pass "menu-api — CosmosDb__ConnectionString is configured"
else
  fail "menu-api — CosmosDb__ConnectionString not set (run post-provision.sh)"
fi

# web-ui — check backend URLs are injected
for VAR in "MENU_API_URL" "ORDER_API_URL" "PAYMENT_API_URL"; do
  VAL=$(az containerapp show --name web-ui --resource-group "$RESOURCE_GROUP" \
    --query "properties.template.containers[0].env[?name=='$VAR'].value | [0]" -o tsv 2>/dev/null || echo "")
  if [ -n "$VAL" ] && [ "$VAL" != "null" ] && [[ ! "$VAL" =~ placeholder|pending ]]; then
    pass "web-ui — $VAR = $VAL"
  else
    warn "web-ui — $VAR not configured or still placeholder"
  fi
done

###############################################################################
# 11. ENDPOINT HEALTH CHECKS
###############################################################################
section "11. Endpoint Health Checks"

if [ "$QUICK_MODE" = true ]; then
  skip "Endpoint health checks (--quick mode)"
else
  MENU_API_FQDN=$(az containerapp show --name menu-api --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
  WEBUI_FQDN=$(az containerapp show --name web-ui --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")

  # Helper function for HTTP checks
  check_endpoint() {
    local NAME="$1"
    local URL="$2"
    local EXPECTED_CODE="${3:-200}"
    local TIMEOUT=10

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m "$TIMEOUT" "$URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "$EXPECTED_CODE" ]; then
      pass "$NAME → HTTP $HTTP_CODE ($URL)"
    elif [ "$HTTP_CODE" = "000" ]; then
      fail "$NAME → Connection timeout ($URL)"
    else
      warn "$NAME → HTTP $HTTP_CODE (expected $EXPECTED_CODE) ($URL)"
    fi
  }

  # menu-api endpoints
  if [ -n "$MENU_API_FQDN" ]; then
    check_endpoint "menu-api /health" "https://${MENU_API_FQDN}/health"
    check_endpoint "menu-api /ready" "https://${MENU_API_FQDN}/ready"
    check_endpoint "menu-api /restaurants" "https://${MENU_API_FQDN}/restaurants"
  else
    fail "menu-api FQDN not available — cannot test endpoints"
  fi

  # order-api endpoints (via AKS LoadBalancer)
  if [ -n "$ORDER_API_IP" ]; then
    check_endpoint "order-api /health" "http://${ORDER_API_IP}/health"
    check_endpoint "order-api /ready" "http://${ORDER_API_IP}/ready"
    check_endpoint "order-api /orders" "http://${ORDER_API_IP}/orders"
    check_endpoint "order-api /customers" "http://${ORDER_API_IP}/customers"
  else
    fail "order-api external IP not available — cannot test endpoints"
  fi

  # payment-service endpoints (via AKS LoadBalancer)
  if [ -n "$PAYMENT_SERVICE_IP" ]; then
    check_endpoint "payment-service /health" "http://${PAYMENT_SERVICE_IP}/health"
    check_endpoint "payment-service /ready" "http://${PAYMENT_SERVICE_IP}/ready"
    check_endpoint "payment-service /fault/status" "http://${PAYMENT_SERVICE_IP}/fault/status"
  else
    fail "payment-service external IP not available — cannot test endpoints"
  fi

  # web-ui frontend
  if [ -n "$WEBUI_FQDN" ]; then
    check_endpoint "web-ui frontend" "https://${WEBUI_FQDN}/"
  else
    fail "web-ui FQDN not available — cannot test"
  fi

  # web-ui proxy routes (through Nginx)
  if [ -n "$WEBUI_FQDN" ] && [ -n "$MENU_API_FQDN" ]; then
    check_endpoint "web-ui → /api/menu/restaurants" "https://${WEBUI_FQDN}/api/menu/restaurants"
  fi
  if [ -n "$WEBUI_FQDN" ] && [ -n "$ORDER_API_IP" ]; then
    check_endpoint "web-ui → /api/orders/health" "https://${WEBUI_FQDN}/api/orders/health"
  fi
  if [ -n "$WEBUI_FQDN" ] && [ -n "$PAYMENT_SERVICE_IP" ]; then
    check_endpoint "web-ui → /api/payments/health" "https://${WEBUI_FQDN}/api/payments/health"
  fi

  # Jira (optional — may take time to start)
  JIRA_FQDN=$(az containerapp show --name jira-sm --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
  if [ -n "$JIRA_FQDN" ]; then
    JIRA_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 15 "https://${JIRA_FQDN}/status" 2>/dev/null || echo "000")
    if [ "$JIRA_CODE" = "200" ] || [ "$JIRA_CODE" = "302" ]; then
      pass "jira-sm /status → HTTP $JIRA_CODE"
    elif [ "$JIRA_CODE" = "000" ]; then
      warn "jira-sm — timeout (Jira may still be initializing)"
    else
      warn "jira-sm /status → HTTP $JIRA_CODE"
    fi
  else
    skip "jira-sm endpoint test — not deployed"
  fi
fi

###############################################################################
# 12. INTER-SERVICE CONNECTIVITY (from pods)
###############################################################################
section "12. Inter-Service Connectivity"

if [ "$QUICK_MODE" = true ]; then
  skip "Inter-service connectivity tests (--quick mode)"
else
  # Test from order-api pod → payment-service internal DNS
  ORDER_POD=$(kubectl get pods -n production -l app=order-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$ORDER_POD" ]; then
    DNS_RESULT=$(kubectl exec "$ORDER_POD" -n production -- sh -c "wget -q -O- --timeout=5 http://payment-service.production.svc.cluster.local/health 2>/dev/null || curl -sf -m 5 http://payment-service.production.svc.cluster.local/health 2>/dev/null" 2>/dev/null || echo "")
    if echo "$DNS_RESULT" | grep -qi "healthy"; then
      pass "order-api → payment-service (internal DNS: healthy)"
    else
      warn "order-api → payment-service internal connectivity could not be verified"
    fi
  else
    skip "Inter-service test — no order-api pod found"
  fi
fi

###############################################################################
# 13. MONITORING & ALERT RULES
###############################################################################
section "13. Monitoring & Alert Rules"

# Action Group
AG=$(az monitor action-group show --name "ag-${PREFIX}-sre" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")
if [ "$AG" = "ag-${PREFIX}-sre" ]; then
  pass "Action group 'ag-${PREFIX}-sre'"
else
  fail "Action group 'ag-${PREFIX}-sre' — not found"
fi

# Scheduled Query Rules (log-based alerts)
EXPECTED_ALERTS=(
  "alert-pod-restart-${PREFIX}"
  "alert-payment-latency-${PREFIX}"
  "alert-payment-errors-${PREFIX}"
  "alert-node-not-ready-${PREFIX}"
  "alert-nodepool-zero-${PREFIX}"
  "alert-pod-unschedulable-${PREFIX}"
)

for ALERT in "${EXPECTED_ALERTS[@]}"; do
  ALERT_ENABLED=$(az monitor scheduled-query show --name "$ALERT" --resource-group "$RESOURCE_GROUP" --query "enabled" -o tsv 2>/dev/null || echo "")
  if [ "$ALERT_ENABLED" = "true" ]; then
    pass "Alert '$ALERT' — enabled"
  elif [ "$ALERT_ENABLED" = "false" ]; then
    warn "Alert '$ALERT' — exists but DISABLED"
  else
    fail "Alert '$ALERT' — not found"
  fi
done

# Availability web test (optional — only if paymentServiceUrl was provided)
WEBTEST=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/webtests" --query "[0].name" -o tsv 2>/dev/null || echo "")
if [ -n "$WEBTEST" ]; then
  pass "Availability web test: $WEBTEST"
else
  skip "Availability web test — not deployed (paymentServiceUrl may be empty)"
fi

# Metric alert for availability (optional)
METRIC_ALERT=$(az monitor metrics alert show --name "alert-payment-availability-${PREFIX}" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")
if [ -n "$METRIC_ALERT" ]; then
  pass "Metric alert 'alert-payment-availability-${PREFIX}'"
else
  skip "Metric alert 'alert-payment-availability-${PREFIX}' — not deployed"
fi

###############################################################################
# 14. APPLICATION INSIGHTS & LOG ANALYTICS
###############################################################################
section "14. Application Insights & Log Analytics"

# App Insights connection string available
AI_CS=$(az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --query "[0].connectionString" -o tsv 2>/dev/null || echo "")
if [ -n "$AI_CS" ]; then
  pass "Application Insights connection string available"
else
  fail "Application Insights connection string not found"
fi

# Log Analytics — check workspace is operational
LAW_STATE=$(az monitor log-analytics workspace show --workspace-name "law-${PREFIX}" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv 2>/dev/null || echo "")
if [ "$LAW_STATE" = "Succeeded" ]; then
  pass "Log Analytics workspace state: Succeeded"
else
  fail "Log Analytics workspace state: ${LAW_STATE:-not found}"
fi

###############################################################################
# 15. CHAOS STUDIO EXPERIMENTS
###############################################################################
section "15. Chaos Studio"

# Check chaos experiments
for EXP in "exp-${PREFIX}-payment-incident" "exp-${PREFIX}-nodepool-failure"; do
  EXP_STATE=$(az rest --method GET --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Chaos/experiments/${EXP}?api-version=2024-01-01" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "")
  if [ "$EXP_STATE" = "Succeeded" ]; then
    pass "Chaos experiment '$EXP' — provisioned"
  elif [ -n "$EXP_STATE" ]; then
    warn "Chaos experiment '$EXP' — state: $EXP_STATE"
  else
    warn "Chaos experiment '$EXP' — not found (chaos may be disabled)"
  fi
done

# Chaos Mesh Helm release on AKS
CHAOS_MESH=$(kubectl get pods -n chaos-testing -l app.kubernetes.io/instance=chaos-mesh --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$CHAOS_MESH" -gt 0 ]; then
  pass "Chaos Mesh installed — $CHAOS_MESH pod(s) in chaos-testing namespace"
else
  warn "Chaos Mesh not detected in chaos-testing namespace"
fi

###############################################################################
# 16. ACR IMAGES
###############################################################################
section "16. Container Registry Images"

ACR_NAME="acr${SANITIZED_PREFIX}"
for REPO in "contoso-meals-sre/order-api" "contoso-meals-sre/payment-service" "contoso-meals-sre/menu-api" "contoso-meals-sre/web-ui"; do
  TAGS=$(az acr repository show-tags --name "$ACR_NAME" --repository "$REPO" --query "[0]" -o tsv 2>/dev/null || echo "")
  if [ -n "$TAGS" ]; then
    pass "ACR image '$REPO' — has tags"
  else
    warn "ACR image '$REPO' — no tags found (not yet deployed?)"
  fi
done

###############################################################################
# 17. LOAD TESTING CONFIGURATION
###############################################################################
section "17. Azure Load Testing"

LT_RESOURCE="lt-${PREFIX}"
for TEST_ID in "baseline" "lunch-rush"; do
  TEST_EXISTS=$(az load test show --load-test-resource "$LT_RESOURCE" --resource-group "$RESOURCE_GROUP" --test-id "$TEST_ID" --query "testId" -o tsv 2>/dev/null || echo "")
  if [ "$TEST_EXISTS" = "$TEST_ID" ]; then
    pass "Load test '$TEST_ID' configured"
  else
    warn "Load test '$TEST_ID' — not configured (run post-deploy.sh)"
  fi
done

###############################################################################
# 18. .ENV FILE
###############################################################################
section "18. Environment File"

if [ -f "$ENV_FILE" ]; then
  pass ".env file exists at $ENV_FILE"
  
  # Check key entries
  for KEY in "MENU_API_URL" "ORDER_API_URL" "PAYMENT_API_URL" "WEB_UI_URL" "RESOURCE_GROUP"; do
    VAL=$(grep "^${KEY}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
    if [ -n "$VAL" ] && [[ ! "$VAL" =~ pending|placeholder ]]; then
      pass ".env $KEY is set"
    else
      warn ".env $KEY — missing or placeholder"
    fi
  done
else
  warn ".env file not found (run post-deploy.sh to generate)"
fi

###############################################################################
# 19. SEED DATA (optional — check if restaurants/customers exist)
###############################################################################
section "19. Seed Data"

if [ "$QUICK_MODE" = true ]; then
  skip "Seed data checks (--quick mode)"
else
  MENU_API_FQDN=$(az containerapp show --name menu-api --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
  
  if [ -n "$MENU_API_FQDN" ]; then
    RESTAURANT_COUNT=$(curl -sf -m 10 "https://${MENU_API_FQDN}/restaurants" 2>/dev/null | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")
    if [ "$RESTAURANT_COUNT" -gt 0 ]; then
      pass "Seed data found — $RESTAURANT_COUNT restaurant(s)"
    else
      warn "No restaurants found — run ./scripts/seed-data.sh"
    fi
  else
    skip "Seed data check — menu-api FQDN unavailable"
  fi

  if [ -n "$ORDER_API_IP" ]; then
    CUSTOMER_COUNT=$(curl -sf -m 10 "http://${ORDER_API_IP}/customers" 2>/dev/null | python3 -c "import sys,json; data=json.load(sys.stdin); items=data.get('items',data) if isinstance(data,dict) else data; print(len(items) if isinstance(items, list) else 0)" 2>/dev/null || echo "0")
    if [ "$CUSTOMER_COUNT" -gt 0 ]; then
      pass "Seed data found — $CUSTOMER_COUNT customer(s)"
    else
      warn "No customers found — run ./scripts/seed-data.sh"
    fi
  else
    skip "Seed data check — order-api IP unavailable"
  fi
fi

###############################################################################
# 20. FAULT INJECTION STATE
###############################################################################
section "20. Fault Injection State"

if [ "$QUICK_MODE" = true ]; then
  skip "Fault injection check (--quick mode)"
else
  if [ -n "$PAYMENT_SERVICE_IP" ]; then
    FAULT_STATUS=$(curl -sf -m 5 "http://${PAYMENT_SERVICE_IP}/fault/status" 2>/dev/null || echo "")
    if echo "$FAULT_STATUS" | grep -qi '"enabled"\s*:\s*false'; then
      pass "payment-service fault injection: DISABLED (clean state)"
    elif echo "$FAULT_STATUS" | grep -qi '"enabled"\s*:\s*true'; then
      warn "payment-service fault injection: ENABLED (may affect tests)"
    else
      warn "payment-service fault injection status could not be determined"
    fi
  else
    skip "Fault injection check — payment-service IP unavailable"
  fi
fi

###############################################################################
# SUMMARY
###############################################################################
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Validation Summary                             ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC}  ${GREEN}✔ Passed:${NC}  $(printf '%3d' $PASS)                                 ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${RED}✘ Failed:${NC}  $(printf '%3d' $FAIL)                                 ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${YELLOW}⚠ Warnings:${NC}$(printf '%3d' $WARN)                                 ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}⊘ Skipped:${NC} $(printf '%3d' $SKIP)                                 ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All critical checks passed!${NC}"
  [ "$WARN" -gt 0 ] && echo -e "${YELLOW}Review $WARN warning(s) above for non-critical issues.${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}${BOLD}$FAIL critical check(s) failed — review the output above.${NC}"
  echo ""
  exit 1
fi
