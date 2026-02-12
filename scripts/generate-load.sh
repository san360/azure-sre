#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Generate Baseline Load
# Sends steady traffic to all service endpoints for metrics baseline.
# Automatically seeds fresh data before each run for realistic testing.
# Usage: ./generate-load.sh [duration_minutes] [requests_per_second]
#######################################################################

DURATION_MINUTES="${1:-30}"
RPS="${2:-5}"
RESOURCE_GROUP="rg-contoso-meals"
SEED_IDS_FILE="/tmp/contoso-seed-ids.env"
SKIP_SEED="${SKIP_SEED:-false}"

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

#######################################################################
# Seed fresh data before load test
#######################################################################
if [ "$SKIP_SEED" != "true" ]; then
  echo "--- Seeding fresh data for this load test run ---"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "${SCRIPT_DIR}/seed-data.sh" ]; then
    bash "${SCRIPT_DIR}/seed-data.sh" \
      --menu-api "$MENU_API_URL" \
      --order-api "$ORDER_API_URL" \
      --customers 20 \
      --restaurants 15
    echo ""
  else
    echo "  Warning: seed-data.sh not found. Using existing data only."
  fi
else
  echo "  Skipping data seeding (SKIP_SEED=true)"
fi

#######################################################################
# Build dynamic data pools from seeded + original IDs
#######################################################################
CUSTOMER_IDS=(
  "00000000-0000-0000-0000-000000000001"
  "00000000-0000-0000-0000-000000000002"
  "00000000-0000-0000-0000-000000000003"
  "00000000-0000-0000-0000-000000000004"
  "00000000-0000-0000-0000-000000000005"
  "00000000-0000-0000-0000-000000000006"
  "00000000-0000-0000-0000-000000000007"
  "00000000-0000-0000-0000-000000000008"
  "00000000-0000-0000-0000-000000000009"
  "00000000-0000-0000-0000-000000000010"
)

RESTAURANT_IDS=("restaurant-1" "restaurant-2" "restaurant-3" "restaurant-4"
                "restaurant-5" "restaurant-6" "restaurant-7" "restaurant-8"
                "restaurant-9" "restaurant-10" "restaurant-11" "restaurant-12")

# Load dynamically created IDs from seed script if available
if [ -f "$SEED_IDS_FILE" ]; then
  source "$SEED_IDS_FILE"
  for i in $(seq 0 $((${SEED_CUSTOMER_COUNT:-0} - 1))); do
    VAR="SEED_CUSTOMER_${i}"
    if [ -n "${!VAR:-}" ]; then
      CUSTOMER_IDS+=("${!VAR}")
    fi
  done
  for i in $(seq 0 $((${SEED_RESTAURANT_COUNT:-0} - 1))); do
    VAR="SEED_RESTAURANT_${i}"
    if [ -n "${!VAR:-}" ]; then
      RESTAURANT_IDS+=("${!VAR}")
    fi
  done
  echo "  Loaded ${SEED_CUSTOMER_COUNT:-0} seeded customers + ${SEED_RESTAURANT_COUNT:-0} seeded restaurants"
fi

CITIES=("Seattle" "Portland" "San Francisco" "Los Angeles" "Denver" "New York")
ORDER_ITEMS_POOL=(
  '[{"name":"Classic Burger","price":12.99}]'
  '[{"name":"Dragon Roll","price":16.99},{"name":"Miso Soup","price":4.99}]'
  '[{"name":"Margherita Pizza","price":13.99},{"name":"Caesar Salad","price":9.99}]'
  '[{"name":"Carne Asada Taco","price":4.99},{"name":"Al Pastor Taco","price":4.49},{"name":"Guacamole & Chips","price":8.99}]'
  '[{"name":"Pad Thai","price":14.99},{"name":"Thai Iced Tea","price":4.99}]'
  '[{"name":"Butter Chicken","price":16.99},{"name":"Garlic Naan","price":3.99}]'
  '[{"name":"Bibimbap","price":14.99}]'
  '[{"name":"Pho Bo","price":14.99},{"name":"Spring Rolls","price":6.99}]'
  '[{"name":"Ribeye Steak","price":34.99},{"name":"Wedge Salad","price":9.99}]'
  '[{"name":"Falafel Wrap","price":11.99},{"name":"Hummus & Pita","price":8.99}]'
)
AMOUNTS=("12.99" "21.98" "23.98" "18.47" "19.98" "20.98" "14.99" "21.98" "44.98" "20.98")
PAYMENT_METHODS=("credit_card" "debit_card" "apple_pay" "google_pay")

# Helper: pick a random element from an array
pick_random() {
  local arr=("$@")
  echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

echo "  Data pool: ${#CUSTOMER_IDS[@]} customers, ${#RESTAURANT_IDS[@]} restaurants"
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
  # Rotate through endpoints with randomized data
  case $((REQUEST_COUNT % 5)) in
    0|1)
      # 40% menu browsing (read-heavy, most common)
      CITY=$(pick_random "${CITIES[@]}")
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$MENU_API_URL/restaurants?city=${CITY}" 2>/dev/null || echo "000")
      ENDPOINT="GET /restaurants?city=${CITY}"
      ;;
    2)
      # 20% menu items for a random restaurant
      REST_ID=$(pick_random "${RESTAURANT_IDS[@]}")
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$MENU_API_URL/menus/${REST_ID}" 2>/dev/null || echo "000")
      ENDPOINT="GET /menus/${REST_ID}"
      ;;
    3)
      # 20% create order with random customer, restaurant, and items
      CUST_ID=$(pick_random "${CUSTOMER_IDS[@]}")
      REST_ID=$(pick_random "${RESTAURANT_IDS[@]}")
      IDX=$((RANDOM % ${#ORDER_ITEMS_POOL[@]}))
      ITEMS="${ORDER_ITEMS_POOL[$IDX]}"
      AMOUNT="${AMOUNTS[$IDX]}"
      PAY_METHOD=$(pick_random "${PAYMENT_METHODS[@]}")
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -X POST "$ORDER_API_URL/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"${CUST_ID}\",\"restaurantId\":\"${REST_ID}\",\"items\":${ITEMS},\"totalAmount\":${AMOUNT},\"paymentMethod\":\"${PAY_METHOD}\"}" \
        2>/dev/null || echo "000")
      ENDPOINT="POST /orders (cust=${CUST_ID:0:8}..)"
      ;;
    4)
      # 20% process payment with random amount and method
      ORDER_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(printf '%08x-%04x-%04x-%04x-%012x' $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM)")
      IDX=$((RANDOM % ${#AMOUNTS[@]}))
      AMOUNT="${AMOUNTS[$IDX]}"
      PAY_METHOD=$(pick_random "${PAYMENT_METHODS[@]}")
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -X POST "$PAYMENT_URL/pay" \
        -H "Content-Type: application/json" \
        -d "{\"orderId\":\"${ORDER_UUID}\",\"amount\":${AMOUNT},\"paymentMethod\":\"${PAY_METHOD}\"}" \
        2>/dev/null || echo "000")
      ENDPOINT="POST /pay (${PAY_METHOD})"
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
