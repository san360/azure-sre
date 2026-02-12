#!/bin/bash
set -euo pipefail

###############################################################################
# Contoso Meals - Post-Provision Hook
# Runs after 'azd provision' to set up AKS namespace, secrets, ACR access,
# and inject connection strings into menu-api Container App
#
# Uses 'az aks command invoke' for kubectl operations because the AKS cluster
# has public network access disabled.
###############################################################################

echo ""
echo "============================================="
echo "  Post-Provision: Configuring Services"
echo "============================================="
echo ""

# Read values from azd environment
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || azd env get-value resourceGroupName 2>/dev/null || echo "rg-contoso-meals")
AKS_CLUSTER_NAME=$(azd env get-value AZURE_AKS_CLUSTER_NAME 2>/dev/null || azd env get-value aksClusterName 2>/dev/null || echo "aks-contoso-meals")
ACR_NAME=$(azd env get-value AZURE_CONTAINER_REGISTRY_NAME 2>/dev/null || echo "acrcontosomeals")
POSTGRES_FQDN=$(azd env get-value postgresServerFqdn 2>/dev/null || echo "")
COSMOS_DB_NAME=$(azd env get-value cosmosDbAccountName 2>/dev/null || echo "cosmos-contoso-meals")

echo "Resource Group:  $RESOURCE_GROUP"
echo "AKS Cluster:     $AKS_CLUSTER_NAME"
echo "ACR:             $ACR_NAME"
echo "PostgreSQL FQDN: $POSTGRES_FQDN"
echo "Cosmos DB:       $COSMOS_DB_NAME"
echo ""

# Helper to run kubectl commands via az aks command invoke (private cluster)
run_kubectl() {
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --command "$1" 2>&1
}

# Step 1: Attach ACR to AKS (allows AKS to pull images without imagePullSecrets)
echo "[1/5] Attaching ACR to AKS..."
az aks update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --attach-acr "$ACR_NAME" \
  --only-show-errors 2>/dev/null || echo "  WARNING: ACR attach failed (may require Owner role or already attached)"

# Step 2: Create namespace and secrets via command invoke
echo "[2/5] Creating Kubernetes namespace and secrets..."

# Create production namespace
run_kubectl "kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -" || echo "  WARNING: namespace creation had issues"

# Build connection strings
POSTGRES_ADMIN="contosoadmin"
POSTGRES_PASSWORD='P@ssw0rd1234!'

if [ -n "$POSTGRES_FQDN" ]; then
  ORDERS_DB_CS="Host=${POSTGRES_FQDN};Database=ordersdb;Username=${POSTGRES_ADMIN};Password=${POSTGRES_PASSWORD};SSL Mode=Require;Trust Server Certificate=true"
else
  echo "  WARNING: PostgreSQL FQDN not available. Using placeholder."
  ORDERS_DB_CS="Host=placeholder;Database=ordersdb;Username=placeholder;Password=placeholder"
fi

# Get Application Insights connection string from Azure
APPINSIGHTS_CS=$(az monitor app-insights component show \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].connectionString" -o tsv 2>/dev/null || echo "")

if [ -z "$APPINSIGHTS_CS" ]; then
  echo "  WARNING: App Insights connection string not found. Using placeholder."
  APPINSIGHTS_CS="InstrumentationKey=00000000-0000-0000-0000-000000000000"
fi

echo "[3/5] Creating Kubernetes secrets..."
# Create/update secrets via command invoke
run_kubectl "kubectl create secret generic contoso-meals-secrets \
  --namespace production \
  --from-literal='orders-db-connection-string=${ORDERS_DB_CS}' \
  --from-literal='appinsights-connection-string=${APPINSIGHTS_CS}' \
  --dry-run=client -o yaml | kubectl apply -f -" || echo "  WARNING: secret creation had issues"

# Step 4: Inject connection strings into menu-api Container App
echo "[4/5] Configuring menu-api Container App with connection strings..."
COSMOS_CS=$(az cosmosdb keys list \
  --name "$COSMOS_DB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" -o tsv 2>/dev/null || echo "")

if [ -n "$COSMOS_CS" ]; then
  az containerapp update \
    --name menu-api \
    --resource-group "$RESOURCE_GROUP" \
    --set-env-vars \
      "CosmosDb__ConnectionString=$COSMOS_CS" \
      "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CS" \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to update menu-api env vars."
  echo "  menu-api environment variables configured."
else
  echo "  WARNING: Cosmos DB connection string not found. menu-api may not connect to data store."
fi

# Step 4b: Configure web-ui Container App with backend API URLs
echo "[4b/5] Configuring web-ui Container App with backend API URLs..."
MENU_API_FQDN=$(az containerapp show \
  --name menu-api \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "")

if [ -n "$MENU_API_FQDN" ]; then
  az containerapp update \
    --name web-ui \
    --resource-group "$RESOURCE_GROUP" \
    --set-env-vars \
      "MENU_API_URL=https://${MENU_API_FQDN}" \
      "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CS" \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to update web-ui env vars."
  echo "  web-ui environment variables configured."
else
  echo "  WARNING: menu-api FQDN not found. web-ui proxy may not connect to menu-api."
fi

# Step 5: Store connection strings in azd env for reference
echo "[5/5] Storing connection strings in azd environment..."
azd env set APPLICATIONINSIGHTS_CONNECTION_STRING "$APPINSIGHTS_CS" 2>/dev/null || true
azd env set COSMOS_CONNECTION_STRING "${COSMOS_CS:-}" 2>/dev/null || true

echo ""
echo "============================================="
echo "  Post-Provision Complete"
echo "============================================="
echo ""
echo "AKS namespace 'production' created with secrets."
echo "ACR '$ACR_NAME' attached to AKS '$AKS_CLUSTER_NAME'."
echo ""

# Print SRE Agent identity info for MCP connector setup
SRE_MI_CLIENT_ID=$(az identity show \
  --name "id-contoso-meals-sre-agent" \
  --resource-group "$RESOURCE_GROUP" \
  --query clientId -o tsv 2>/dev/null || echo "")

if [ -n "$SRE_MI_CLIENT_ID" ]; then
  echo "============================================="
  echo "  SRE Agent MCP Connector Configuration"
  echo "============================================="
  echo ""
  echo "  Use these values when configuring the Azure MCP connector"
  echo "  in the SRE Agent portal (Settings → Connectors):"
  echo ""
  echo "  Managed Identity:  id-contoso-meals-sre-agent (select from dropdown)"
  echo "  AZURE_CLIENT_ID:   $SRE_MI_CLIENT_ID"
  echo "  AZURE_TOKEN_CREDENTIALS: ManagedIdentityCredential"
  echo ""
  azd env set SRE_AGENT_MI_CLIENT_ID "$SRE_MI_CLIENT_ID" 2>/dev/null || true
fi
