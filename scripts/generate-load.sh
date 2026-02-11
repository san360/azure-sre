#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Generate Baseline Load
# Sends steady traffic to all service endpoints for metrics baseline
# Usage: ./generate-load.sh [duration_minutes] [requests_per_second]
#######################################################################

DURATION_MINUTES="${1:-30}"
RPS="${2:-5}"
RESOURCE_GROUP="rg-contoso-meals"

echo "============================================="
echo "  Contoso Meals - Baseline Load Generator"
echo "============================================="
echo "  Duration: ${DURATION_MINUTES} minutes"
echo "  Rate:     ~${RPS} requests/second"
echo ""

# Get service endpoints
echo "Discovering service endpoints..."

# Menu API (Container App)
MENU_API_URL="https://$(az containerapp show \
  --name menu-api \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "menu-api.unknown")"

# AKS services (port-forward or external IP)
# For AKS, we need either an ingress or port-forward. Use kubectl proxy approach.
ORDER_API_URL=""
PAYMENT_URL=""

# Check if AKS services have external IPs
ORDER_API_IP=$(kubectl get svc order-api -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
PAYMENT_IP=$(kubectl get svc payment-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$ORDER_API_IP" ]; then
  ORDER_API_URL="http://${ORDER_API_IP}"
  PAYMENT_URL="http://${PAYMENT_IP}"
else
  echo "  AKS services are ClusterIP. Starting port-forwards..."
  kubectl port-forward svc/order-api 8081:80 -n production &
  PF_ORDER_PID=$!
  kubectl port-forward svc/payment-service 8082:80 -n production &
  PF_PAYMENT_PID=$!
  sleep 3
  ORDER_API_URL="http://localhost:8081"
  PAYMENT_URL="http://localhost:8082"

  # Cleanup port-forwards on exit
  trap "kill $PF_ORDER_PID $PF_PAYMENT_PID 2>/dev/null; echo 'Port-forwards stopped.'" EXIT
fi

echo ""
echo "Endpoints:"
echo "  Menu API:        $MENU_API_URL"
echo "  Order API:       $ORDER_API_URL"
echo "  Payment Service: $PAYMENT_URL"
echo ""

TOTAL_SECONDS=$((DURATION_MINUTES * 60))
SLEEP_INTERVAL=$(echo "scale=3; 1/$RPS" | bc)
END_TIME=$(($(date +%s) + TOTAL_SECONDS))

echo "Starting load generation... (Ctrl+C to stop)"
echo ""

REQUEST_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0

while [ $(date +%s) -lt $END_TIME ]; do
  # Rotate through endpoints
  case $((REQUEST_COUNT % 5)) in
    0|1)
      # 40% menu browsing (read-heavy, most common)
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$MENU_API_URL/restaurants" 2>/dev/null || echo "000")
      ENDPOINT="GET /restaurants"
      ;;
    2)
      # 20% menu items
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$MENU_API_URL/menus/rest-001" 2>/dev/null || echo "000")
      ENDPOINT="GET /menus"
      ;;
    3)
      # 20% create order
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -X POST "$ORDER_API_URL/orders" \
        -H "Content-Type: application/json" \
        -d '{"customerId":"00000000-0000-0000-0000-000000000001","restaurantId":"rest-001","items":"[{\"name\":\"Classic Burger\",\"price\":12.99}]","totalAmount":12.99}' \
        2>/dev/null || echo "000")
      ENDPOINT="POST /orders"
      ;;
    4)
      # 20% process payment
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -X POST "$PAYMENT_URL/pay" \
        -H "Content-Type: application/json" \
        -d '{"orderId":"00000000-0000-0000-0000-000000000001","amount":12.99,"paymentMethod":"credit_card"}' \
        2>/dev/null || echo "000")
      ENDPOINT="POST /pay"
      ;;
  esac

  REQUEST_COUNT=$((REQUEST_COUNT + 1))
  if [[ "$STATUS" == 2* ]] || [[ "$STATUS" == "200" ]] || [[ "$STATUS" == "201" ]]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # Progress update every 50 requests
  if [ $((REQUEST_COUNT % 50)) -eq 0 ]; then
    ELAPSED=$(($(date +%s) - (END_TIME - TOTAL_SECONDS)))
    REMAINING=$((END_TIME - $(date +%s)))
    echo "  [${ELAPSED}s] Requests: $REQUEST_COUNT | Success: $SUCCESS_COUNT | Failed: $FAIL_COUNT | Remaining: ${REMAINING}s"
  fi

  sleep "$SLEEP_INTERVAL"
done

echo ""
echo "============================================="
echo "  Load Generation Complete"
echo "============================================="
echo "  Total Requests:  $REQUEST_COUNT"
echo "  Successful:      $SUCCESS_COUNT"
echo "  Failed:          $FAIL_COUNT"
echo "  Success Rate:    $(echo "scale=1; $SUCCESS_COUNT * 100 / $REQUEST_COUNT" | bc)%"
echo "  Duration:        ${DURATION_MINUTES} minutes"
echo ""
echo "Check Azure Monitor / Application Insights for metrics."
