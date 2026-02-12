#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Full Deployment Script
# Deploys all Azure infrastructure + AKS workloads + configures services
#######################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Ensure BuildKit is used for cross-platform Docker builds (arm64 host → amd64 images)
export DOCKER_BUILDKIT=1

# Configuration
RESOURCE_GROUP="rg-contoso-meals"
AKS_CLUSTER="aks-contoso-meals"
PREFIX="contoso-meals"
LOCATION="swedencentral"
POSTGRES_LOCATION="swedencentral"
POSTGRES_ADMIN="contosoadmin"
POSTGRES_PASSWORD="P@ssw0rd1234!"

echo "============================================="
echo "  Contoso Meals - Full Deployment"
echo "============================================="
echo ""

# Step 1: Deploy infrastructure via Bicep
echo "[1/8] Deploying Azure infrastructure (Bicep + AVM)..."
az deployment sub create \
  --location "$LOCATION" \
  --template-file "$PROJECT_ROOT/infra/main.bicep" \
  --parameters "$PROJECT_ROOT/infra/main.parameters.json" \
  --name "contoso-meals-$(date +%Y%m%d%H%M%S)" \
  --verbose

echo "  Infrastructure deployment complete."

# Step 2: Retrieve deployment outputs
echo "[2/8] Retrieving deployment outputs..."
POSTGRES_FQDN=$(az deployment sub show \
  --name "$(az deployment sub list --query "[?contains(name,'contoso-meals')].name | [0]" -o tsv)" \
  --query "properties.outputs.postgresServerFqdn.value" -o tsv)

MENU_API_FQDN=$(az deployment sub show \
  --name "$(az deployment sub list --query "[?contains(name,'contoso-meals')].name | [0]" -o tsv)" \
  --query "properties.outputs.menuApiFqdn.value" -o tsv)

SRE_MI_CLIENT_ID=$(az deployment sub show \
  --name "$(az deployment sub list --query "[?contains(name,'contoso-meals')].name | [0]" -o tsv)" \
  --query "properties.outputs.sreAgentIdentityClientId.value" -o tsv 2>/dev/null || echo "")

SRE_AGENT_PORTAL_URL=$(az deployment sub show \
  --name "$(az deployment sub list --query "[?contains(name,'contoso-meals')].name | [0]" -o tsv)" \
  --query "properties.outputs.sreAgentPortalUrl.value" -o tsv 2>/dev/null || echo "")

echo "  PostgreSQL FQDN:        $POSTGRES_FQDN"
echo "  Menu API FQDN:          $MENU_API_FQDN"
echo "  SRE Agent MI Client ID: $SRE_MI_CLIENT_ID"
if [ -n "$SRE_AGENT_PORTAL_URL" ]; then
  echo "  SRE Agent Portal URL:   $SRE_AGENT_PORTAL_URL"
fi

# Step 3: Get AKS credentials (AKS Automatic uses Entra ID RBAC)
echo "[3/8] Getting AKS credentials..."
echo "  NOTE: AKS Automatic uses Entra ID RBAC. Ensure you have"
echo "        'Azure Kubernetes Service RBAC Cluster Admin' role on the cluster."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --overwrite-existing

# Step 4: Create namespace
echo "[4/8] Creating Kubernetes namespace..."
kubectl apply -f "$PROJECT_ROOT/manifests/namespace.yaml"

# Step 5: Create secrets
echo "[5/8] Creating Kubernetes secrets..."

# Get Application Insights connection string
APPINSIGHTS_CS=$(az monitor app-insights component show \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].connectionString" -o tsv 2>/dev/null || echo "")

if [ -z "$APPINSIGHTS_CS" ]; then
  echo "  WARNING: Application Insights connection string not found. Using placeholder."
  APPINSIGHTS_CS="InstrumentationKey=00000000-0000-0000-0000-000000000000"
fi

# Generate secrets from template
POSTGRES_CONNECTION_STRING="Host=${POSTGRES_FQDN};Database=ordersdb;Username=${POSTGRES_ADMIN};Password=${POSTGRES_PASSWORD};SSL Mode=Require;Trust Server Certificate=true"

kubectl create secret generic contoso-meals-secrets \
  --namespace production \
  --from-literal="orders-db-connection-string=${POSTGRES_CONNECTION_STRING}" \
  --from-literal="appinsights-connection-string=${APPINSIGHTS_CS}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  Secrets created."

# Step 6: Build and push container images (if ACR exists)
echo "[6/8] Checking for Azure Container Registry..."
ACR_NAME=$(az acr list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -n "$ACR_NAME" ]; then
  echo "  ACR found: $ACR_NAME. Building and pushing images..."

  az acr build --registry "$ACR_NAME" \
    --image contoso-meals/order-api:latest \
    --platform linux/amd64 \
    "$PROJECT_ROOT/app/order-api/"

  az acr build --registry "$ACR_NAME" \
    --image contoso-meals/payment-service:latest \
    --platform linux/amd64 \
    "$PROJECT_ROOT/app/payment-service/"

  az acr build --registry "$ACR_NAME" \
    --image contoso-meals/web-ui:latest \
    --platform linux/amd64 \
    "$PROJECT_ROOT/app/web-ui/"

  # Update manifests with ACR name
  sed -i "s|\${ACR_NAME}|${ACR_NAME}|g" "$PROJECT_ROOT/manifests/order-api.yaml"
  sed -i "s|\${ACR_NAME}|${ACR_NAME}|g" "$PROJECT_ROOT/manifests/payment-service.yaml"
else
  echo "  No ACR found. Using pre-built images or placeholder images."
  echo "  To deploy with real images, create an ACR and re-run this script."

  # Replace image references with the .NET sample app as placeholder
  sed -i "s|\${ACR_NAME}.azurecr.io/contoso-meals/order-api:latest|mcr.microsoft.com/dotnet/samples:aspnetapp|g" "$PROJECT_ROOT/manifests/order-api.yaml"
  sed -i "s|\${ACR_NAME}.azurecr.io/contoso-meals/payment-service:latest|mcr.microsoft.com/dotnet/samples:aspnetapp|g" "$PROJECT_ROOT/manifests/payment-service.yaml"
fi

# Step 7: Deploy AKS workloads
echo "[7/8] Deploying AKS workloads..."
kubectl apply -f "$PROJECT_ROOT/manifests/order-api.yaml"
kubectl apply -f "$PROJECT_ROOT/manifests/payment-service.yaml"

echo "  Waiting for deployments to be ready..."
kubectl rollout status deployment/order-api -n production --timeout=120s || true
kubectl rollout status deployment/payment-service -n production --timeout=120s || true

# Step 7b: Wait for LoadBalancer external IPs and configure web-ui backend URLs
echo "[7b/8] Waiting for AKS LoadBalancer external IPs..."
ORDER_API_IP=""
PAYMENT_SERVICE_IP=""
for i in $(seq 1 30); do
  ORDER_API_IP=$(kubectl get svc order-api -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  PAYMENT_SERVICE_IP=$(kubectl get svc payment-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$ORDER_API_IP" ] && [ -n "$PAYMENT_SERVICE_IP" ]; then
    break
  fi
  echo "  Waiting for external IPs... (attempt $i/30)"
  sleep 10
done

if [ -n "$ORDER_API_IP" ] && [ -n "$PAYMENT_SERVICE_IP" ]; then
  echo "  Order API external IP:      $ORDER_API_IP"
  echo "  Payment Service external IP: $PAYMENT_SERVICE_IP"
  echo "  Updating web-ui Container App with AKS backend URLs..."
  az containerapp update \
    --name web-ui \
    --resource-group "$RESOURCE_GROUP" \
    --set-env-vars \
      "ORDER_API_URL=http://${ORDER_API_IP}" \
      "PAYMENT_API_URL=http://${PAYMENT_SERVICE_IP}" \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to update web-ui with AKS backend URLs."
  echo "  web-ui backend URLs configured."
else
  echo "  WARNING: Could not retrieve AKS external IPs. web-ui may not connect to order-api/payment-service."
  echo "  order-api IP: ${ORDER_API_IP:-not assigned}"
  echo "  payment-service IP: ${PAYMENT_SERVICE_IP:-not assigned}"
fi

# Step 7c: Update web-ui Container App with built image
if [ -n "$ACR_NAME" ]; then
  echo "  Updating web-ui Container App image..."
  az containerapp update \
    --name web-ui \
    --resource-group "$RESOURCE_GROUP" \
    --image "${ACR_NAME}.azurecr.io/contoso-meals/web-ui:latest" \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to update web-ui container app image."
fi

# Step 8: Verify deployment
echo "[8/8] Verifying deployment..."
echo ""
echo "--- Kubernetes Resources ---"
kubectl get pods -n production
echo ""
kubectl get services -n production
echo ""

# Print Jira info if enabled
JIRA_FQDN=$(az containerapp show \
  --name jira-sm \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "")

MCP_FQDN=$(az containerapp show \
  --name mcp-atlassian \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "")

WEBUI_FQDN=$(az containerapp show \
  --name web-ui \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "")

echo "============================================="
echo "  Deployment Complete!"
echo "============================================="
echo ""
echo "Resources:"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  AKS Cluster:     $AKS_CLUSTER"
echo "  PostgreSQL:      $POSTGRES_FQDN"
echo "  Menu API:        https://$MENU_API_FQDN"
[ -n "${ORDER_API_IP:-}" ] && echo "  Order API:       http://$ORDER_API_IP"
[ -n "${PAYMENT_SERVICE_IP:-}" ] && echo "  Payment Service: http://$PAYMENT_SERVICE_IP"
[ -n "$WEBUI_FQDN" ] && echo "  Web UI:          https://$WEBUI_FQDN"
[ -n "$JIRA_FQDN" ] && echo "  Jira SM:         https://$JIRA_FQDN"
[ -n "$MCP_FQDN" ] && echo "  MCP Atlassian:   https://$MCP_FQDN/mcp"
echo ""
if [ -n "$SRE_MI_CLIENT_ID" ]; then
  echo "SRE Agent MCP Connector:"
  echo "  Identity:        id-contoso-meals-sre-agent"
  echo "  AZURE_CLIENT_ID: $SRE_MI_CLIENT_ID"
  echo ""
fi
if [ -n "$SRE_AGENT_PORTAL_URL" ]; then
  echo "SRE Agent (deployed via Bicep):"
  echo "  Portal URL:      $SRE_AGENT_PORTAL_URL"
  echo "  Access Level:    High (Reader + Contributor + Log Analytics Reader)"
  echo "  Mode:            Review"
  echo ""
  echo "Next steps:"
  echo "  1. Run baseline load test:  ./scripts/generate-load.sh 30"
  echo "  2. Set up Jira:             ./scripts/setup-jira.sh"
  echo "  3. Open SRE Agent in portal and configure MCP, Teams, Knowledge Base"
  echo "     (see demo-proposal.md Part 1)"
else
  echo "Next steps:"
  echo "  1. Run baseline load test:  ./scripts/generate-load.sh 30"
  echo "  2. Set up Jira:             ./scripts/setup-jira.sh"
  echo "  3. Create SRE Agent in Azure Portal"
  echo "  4. Configure MCP, Teams, Knowledge Base (see demo-proposal.md Part 1)"
fi
echo ""
