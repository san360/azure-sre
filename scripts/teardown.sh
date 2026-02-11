#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Teardown Script
# Deletes all Azure resources for the demo environment
#######################################################################

RESOURCE_GROUP="rg-contoso-meals"

echo "============================================="
echo "  Contoso Meals - Teardown"
echo "============================================="
echo ""
echo "This will DELETE all resources in: $RESOURCE_GROUP"
echo ""

# Check if the resource group exists
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "Resource group '$RESOURCE_GROUP' does not exist. Nothing to tear down."
  exit 0
fi

# Prompt for confirmation unless --yes flag is passed
if [[ "${1:-}" != "--yes" ]]; then
  read -p "Are you sure? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Deleting resource group '$RESOURCE_GROUP'..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo "Deletion initiated (running in background)."
echo ""
echo "To check status:"
echo "  az group show --name $RESOURCE_GROUP 2>/dev/null && echo 'Still deleting...' || echo 'Deleted successfully'"
echo ""
echo "Approximate cost while running: \$20-35/day. Teardown saves money."
