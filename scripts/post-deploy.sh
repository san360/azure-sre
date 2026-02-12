#!/bin/bash
set -euo pipefail

###############################################################################
# Contoso Meals - Post-Deploy Hook
# Runs after 'azd deploy' to configure web-ui with AKS backend URLs.
# Fetches LoadBalancer external IPs from AKS and sets ORDER_API_URL and
# PAYMENT_API_URL on the web-ui Container App.
###############################################################################

echo ""
echo "============================================="
echo "  Post-Deploy: Configuring Backend URLs"
echo "============================================="
echo ""

RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || azd env get-value resourceGroupName 2>/dev/null || echo "rg-contoso-meals")
AKS_CLUSTER_NAME=$(azd env get-value AZURE_AKS_CLUSTER_NAME 2>/dev/null || azd env get-value aksClusterName 2>/dev/null || echo "aks-contoso-meals")

echo "Resource Group: $RESOURCE_GROUP"
echo "AKS Cluster:    $AKS_CLUSTER_NAME"
echo ""

# Helper to run kubectl commands via az aks command invoke (private cluster)
run_kubectl() {
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --command "$1" 2>&1
}

# Wait for LoadBalancer external IPs (may take a moment after deploy)
echo "[1/2] Waiting for AKS LoadBalancer external IPs..."
ORDER_API_IP=""
PAYMENT_SERVICE_IP=""

for i in $(seq 1 30); do
  ORDER_API_IP=$(run_kubectl "kubectl get svc order-api -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 2>/dev/null | tr -d "'" || echo "")
  PAYMENT_SERVICE_IP=$(run_kubectl "kubectl get svc payment-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 2>/dev/null | tr -d "'" || echo "")

  if [ -n "$ORDER_API_IP" ] && [ -n "$PAYMENT_SERVICE_IP" ]; then
    break
  fi
  echo "  Waiting for external IPs... (attempt $i/30)"
  sleep 10
done

echo "  Order API IP:      ${ORDER_API_IP:-not assigned}"
echo "  Payment Service IP: ${PAYMENT_SERVICE_IP:-not assigned}"
echo ""

# Update web-ui Container App with backend URLs
echo "[2/2] Updating web-ui Container App with backend API URLs..."

MENU_API_FQDN=$(az containerapp show \
  --name menu-api \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "")

ENV_VARS=""
[ -n "$MENU_API_FQDN" ] && ENV_VARS="MENU_API_URL=https://${MENU_API_FQDN}"
[ -n "$ORDER_API_IP" ] && ENV_VARS="$ENV_VARS ORDER_API_URL=http://${ORDER_API_IP}"
[ -n "$PAYMENT_SERVICE_IP" ] && ENV_VARS="$ENV_VARS PAYMENT_API_URL=http://${PAYMENT_SERVICE_IP}"

if [ -n "$ENV_VARS" ]; then
  az containerapp update \
    --name web-ui \
    --resource-group "$RESOURCE_GROUP" \
    --set-env-vars $ENV_VARS \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to update web-ui env vars."
  echo "  web-ui backend URLs configured."
else
  echo "  WARNING: No backend URLs available. web-ui proxy may not work."
fi

echo ""
echo "============================================="
echo "  Post-Deploy Complete"
echo "============================================="
echo ""
