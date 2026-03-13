#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Jira Service Management Setup
# Configures Jira SM after first boot: creates project, workflows, users
#######################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

RESOURCE_GROUP="rg-contoso-meals"
JIRA_ADMIN_USER="admin"

# Read password from .env if available, otherwise use default
if [ -f "$ENV_FILE" ]; then
  JIRA_ADMIN_PASSWORD=$(grep '^JIRA_ADMIN_PASSWORD=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || true)
fi
JIRA_ADMIN_PASSWORD="${JIRA_ADMIN_PASSWORD:-admin}"

echo "============================================="
echo "  Contoso Meals - Jira SM Setup"
echo "============================================="
echo ""

# Get Jira URL
JIRA_FQDN=$(az containerapp show \
  --name jira-sm \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null)

if [ -z "$JIRA_FQDN" ]; then
  echo "ERROR: Jira SM container app not found in $RESOURCE_GROUP"
  exit 1
fi

JIRA_URL="https://${JIRA_FQDN}"
echo "Jira URL: $JIRA_URL"

# Wait for Jira to be ready
echo ""
echo "[1/5] Waiting for Jira to be ready..."
MAX_WAIT=300
WAITED=0
while true; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$JIRA_URL/status" --max-time 10 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  Jira is ready!"
    break
  fi
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ERROR: Jira did not become ready within ${MAX_WAIT}s"
    echo "  HTTP status: $HTTP_CODE"
    echo "  Check container logs: az containerapp logs show --name jira-sm --resource-group $RESOURCE_GROUP"
    exit 1
  fi
  echo "  Waiting... (${WAITED}s / ${MAX_WAIT}s, HTTP: $HTTP_CODE)"
  sleep 15
  WAITED=$((WAITED + 15))
done

# Check if Jira setup wizard needs to be completed
echo ""
echo "[2/5] Checking Jira setup status..."
SETUP_STATUS=$(curl -s "$JIRA_URL/rest/api/2/serverInfo" \
  -u "${JIRA_ADMIN_USER}:${JIRA_ADMIN_PASSWORD}" \
  --max-time 10 2>/dev/null || echo "")

if echo "$SETUP_STATUS" | grep -q "baseUrl"; then
  echo "  Jira is already configured."
else
  echo "  NOTE: Jira setup wizard may need to be completed manually."
  echo "  Open $JIRA_URL in a browser and complete the setup wizard."
  echo "  Then re-run this script."
  echo ""
  echo "  Quick setup guide:"
  echo "  1. Choose 'I\'ll set it up myself'"
  echo "  2. Select 'My Own Database' (PostgreSQL is already configured)"
  echo "  3. Set application title: 'Contoso Meals ITSM'"
  echo "  4. Set base URL: $JIRA_URL"
  echo "  5. Create admin account (username: admin)"
  echo ""
  echo "  After setup, re-run: ./scripts/setup-jira.sh"
  exit 0
fi

# Create CONTOSO project
echo ""
echo "[3/5] Creating CONTOSO project..."
PROJECT_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$JIRA_URL/rest/api/2/project/CONTOSO" \
  -u "${JIRA_ADMIN_USER}:${JIRA_ADMIN_PASSWORD}" \
  --max-time 10 2>/dev/null)

if [ "$PROJECT_EXISTS" = "200" ]; then
  echo "  CONTOSO project already exists."
else
  CREATE_RESULT=$(curl -s -w "\n%{http_code}" \
    -X POST "$JIRA_URL/rest/api/2/project" \
    -u "${JIRA_ADMIN_USER}:${JIRA_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "key": "CONTOSO",
      "name": "Contoso Meals Operations",
      "projectTypeKey": "service_desk",
      "projectTemplateKey": "com.atlassian.servicedesk:itil-v2-service-desk-project",
      "description": "Contoso Meals incident management and SRE operations",
      "lead": "'"${JIRA_ADMIN_USER}"'",
      "assigneeType": "PROJECT_LEAD"
    }' --max-time 30 2>/dev/null)

  HTTP_CODE=$(echo "$CREATE_RESULT" | tail -1)
  BODY=$(echo "$CREATE_RESULT" | sed '$d')

  if [ "$HTTP_CODE" = "201" ]; then
    echo "  CONTOSO project created successfully."
  else
    echo "  WARNING: Project creation returned HTTP $HTTP_CODE"
    echo "  Response: $BODY"
    echo "  You may need to create the project manually in the Jira UI."
  fi
fi

# Create custom labels
echo ""
echo "[4/5] Verifying issue types and priorities..."
ISSUE_TYPES=$(curl -s "$JIRA_URL/rest/api/2/issuetype" \
  -u "${JIRA_ADMIN_USER}:${JIRA_ADMIN_PASSWORD}" \
  --max-time 10 2>/dev/null)
echo "  Available issue types: $(echo "$ISSUE_TYPES" | python3 -c "import sys,json; [print(t['name']) for t in json.load(sys.stdin)]" 2>/dev/null || echo "(unable to parse)")"

PRIORITIES=$(curl -s "$JIRA_URL/rest/api/2/priority" \
  -u "${JIRA_ADMIN_USER}:${JIRA_ADMIN_PASSWORD}" \
  --max-time 10 2>/dev/null)
echo "  Available priorities: $(echo "$PRIORITIES" | python3 -c "import sys,json; [print(t['name']) for t in json.load(sys.stdin)]" 2>/dev/null || echo "(unable to parse)")"

# Configure mcp-atlassian with Jira API token (admin password for Jira Server)
echo ""
echo "[5/5] Configuring mcp-atlassian with Jira API token..."
echo ""
echo "  JIRA_URL:       $JIRA_URL"
echo "  JIRA_USERNAME:  $JIRA_ADMIN_USER"
echo ""

echo "  Updating mcp-atlassian secret..."
az containerapp secret set \
  --name mcp-atlassian \
  --resource-group "$RESOURCE_GROUP" \
  --secrets "jira-api-token=${JIRA_ADMIN_PASSWORD}" \
  --only-show-errors 2>/dev/null || echo "  WARNING: Failed to set mcp-atlassian secret."

echo "  Restarting mcp-atlassian..."
ACTIVE_REVISION=$(az containerapp revision list \
  --name mcp-atlassian \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?properties.active].name" -o tsv 2>/dev/null | head -1)

if [ -n "$ACTIVE_REVISION" ]; then
  az containerapp revision restart \
    --name mcp-atlassian \
    --resource-group "$RESOURCE_GROUP" \
    --revision "$ACTIVE_REVISION" \
    --only-show-errors 2>/dev/null || echo "  WARNING: Failed to restart mcp-atlassian revision."
  echo "  mcp-atlassian restarted with updated Jira API token."
else
  echo "  WARNING: No active revision found for mcp-atlassian."
fi

# ─── Update .env file with Jira credentials ───────────────────────
if [ -f "$ENV_FILE" ]; then
  # Remove existing Jira credential entries
  sed -i '/^JIRA_ADMIN_USER=/d' "$ENV_FILE"
  sed -i '/^JIRA_ADMIN_PASSWORD=/d' "$ENV_FILE"
  # Append updated values
  echo "JIRA_ADMIN_USER=${JIRA_ADMIN_USER}" >> "$ENV_FILE"
  echo "JIRA_ADMIN_PASSWORD=${JIRA_ADMIN_PASSWORD}" >> "$ENV_FILE"
  echo "  .env updated with JIRA_ADMIN_USER and JIRA_ADMIN_PASSWORD"
else
  echo "  WARNING: .env file not found at $ENV_FILE — skipping .env update"
fi

echo ""
echo "============================================="
echo "  Jira SM Setup Complete"
echo "============================================="
echo ""
echo "  Jira URL:     $JIRA_URL"
echo "  Project:      CONTOSO"
echo "  Admin User:   $JIRA_ADMIN_USER"
echo ""
echo "  Next: Configure mcp-atlassian connector in SRE Agent"
echo "  See demo-proposal.md Part 4, Scene 4.2"
