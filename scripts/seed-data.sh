#!/bin/bash
set -euo pipefail

#######################################################################
# Contoso Meals - Dynamic Data Seeder
# Generates fresh randomized data before each load test run.
# Creates customers, restaurants, and menus via the service APIs.
#
# Usage: ./seed-data.sh [--customers N] [--restaurants N]
# Defaults: 20 customers, 15 restaurants
# Outputs: /tmp/contoso-seed-ids.env (IDs for load test consumption)
#######################################################################

NUM_CUSTOMERS="${SEED_CUSTOMERS:-20}"
NUM_RESTAURANTS="${SEED_RESTAURANTS:-15}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-contoso-meals}"
SEED_IDS_FILE="/tmp/contoso-seed-ids.env"
BATCH_TAG=$(date +%s)  # Unique tag per run

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --customers) NUM_CUSTOMERS="$2"; shift 2;;
    --restaurants) NUM_RESTAURANTS="$2"; shift 2;;
    --menu-api) MENU_API_URL="$2"; shift 2;;
    --order-api) ORDER_API_URL="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

echo "============================================="
echo "  Contoso Meals — Dynamic Data Seeder"
echo "============================================="
echo "  Batch Tag:    ${BATCH_TAG}"
echo "  Customers:    ${NUM_CUSTOMERS}"
echo "  Restaurants:  ${NUM_RESTAURANTS}"
echo ""

#######################################################################
# Discover endpoints (unless overridden)
#######################################################################
if [ -z "${MENU_API_URL:-}" ]; then
  echo "Discovering Menu API endpoint..."
  MENU_API_URL="https://$(az containerapp show \
    --name menu-api \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "localhost:5100")"
fi

if [ -z "${ORDER_API_URL:-}" ]; then
  echo "Discovering Order API endpoint..."
  ORDER_API_IP=$(kubectl get svc order-api -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$ORDER_API_IP" ]; then
    ORDER_API_URL="http://${ORDER_API_IP}"
  else
    echo "  AKS service is ClusterIP. Starting port-forward..."
    kubectl port-forward svc/order-api 8081:80 -n production &>/dev/null &
    PF_PID=$!
    sleep 3
    ORDER_API_URL="http://localhost:8081"
    trap "kill $PF_PID 2>/dev/null" EXIT
  fi
fi

echo ""
echo "Endpoints:"
echo "  Menu API:   $MENU_API_URL"
echo "  Order API:  $ORDER_API_URL"
echo ""

#######################################################################
# Data pools for randomization
#######################################################################
FIRST_NAMES=("Alice" "Bob" "Carlos" "Diana" "Emma" "Frank" "Grace" "Hiro" "Isla" "Jake"
             "Kim" "Leo" "Maya" "Noah" "Olivia" "Pavel" "Quinn" "Rosa" "Sam" "Tara"
             "Uma" "Victor" "Wendy" "Xavier" "Yuri" "Zara" "Aiden" "Bella" "Chloe" "David")

LAST_NAMES=("Smith" "Johnson" "Williams" "Brown" "Jones" "Garcia" "Miller" "Davis" "Rodriguez" "Martinez"
            "Hernandez" "Lopez" "Gonzalez" "Wilson" "Anderson" "Thomas" "Taylor" "Moore" "Jackson" "Martin")

CITIES=("Seattle" "Portland" "San Francisco" "Los Angeles" "Denver" "Austin" "Chicago" "New York" "Boston" "Miami")

CUISINES=("American" "Japanese" "Italian" "Mexican" "Thai" "Indian" "Chinese" "Mediterranean" "French" "Korean"
          "Vietnamese" "Ethiopian" "Greek" "Brazilian" "Peruvian")

RESTAURANT_PREFIXES=("Contoso" "Fabrikam" "Northwind" "Adventure" "Woodgrove" "Tailspin" "Litware" "Wingtip"
                     "Proseware" "Relecloud" "Munson" "VanArsdel" "Coho" "Trey" "Margie")

RESTAURANT_SUFFIXES=("Bistro" "Kitchen" "Grill" "Cafe" "Eatery" "Diner" "Tavern" "Bar & Grill" "House"
                     "Table" "Place" "Garden" "Brasserie" "Trattoria" "Cantina")

STREETS=("Main St" "Oak Ave" "1st Ave" "Pine St" "Market St" "Broadway" "Elm Dr" "Cedar Blvd"
         "River Rd" "Park Way" "Lake Dr" "Sunset Blvd" "Highland Ave" "Valley Rd" "Harbor Dr")

# Menu item categories and items
declare -A MENU_POOLS
MENU_POOLS[American]='Classic Burger:12.99:Burgers|Bacon Cheeseburger:14.99:Burgers|BBQ Ribs:22.99:Mains|Truffle Fries:7.99:Sides|Onion Rings:6.99:Sides|Grilled Chicken Sandwich:13.99:Sandwiches|Mac & Cheese:9.99:Sides|Milkshake:6.99:Drinks|Coleslaw:4.99:Sides|Apple Pie:7.99:Desserts'
MENU_POOLS[Japanese]='Salmon Nigiri:8.99:Nigiri|Dragon Roll:16.99:Rolls|Miso Soup:4.99:Soup|Edamame:5.99:Appetizers|Tonkotsu Ramen:15.99:Mains|Teriyaki Chicken:14.99:Mains|Gyoza:7.99:Appetizers|Matcha Latte:5.99:Drinks|Tempura Shrimp:12.99:Appetizers|Sashimi Platter:24.99:Platters'
MENU_POOLS[Italian]='Margherita Pizza:13.99:Pizza|Pepperoni Pizza:14.99:Pizza|Spaghetti Carbonara:16.99:Pasta|Garlic Knots:6.99:Sides|Caesar Salad:9.99:Salads|Tiramisu:8.99:Desserts|Bruschetta:7.99:Appetizers|Lasagna:17.99:Pasta|Risotto:15.99:Mains|Gelato:6.99:Desserts'
MENU_POOLS[Mexican]='Carne Asada Taco:4.99:Tacos|Al Pastor Taco:4.49:Tacos|Fish Taco:5.49:Tacos|Guacamole & Chips:8.99:Appetizers|Burrito Bowl:13.99:Bowls|Enchiladas:14.99:Mains|Quesadilla:10.99:Mains|Horchata:3.99:Drinks|Churros:5.99:Desserts|Elote:4.99:Sides'
MENU_POOLS[Thai]='Pad Thai:14.99:Noodles|Green Curry:15.99:Curries|Tom Yum Soup:8.99:Soup|Spring Rolls:6.99:Appetizers|Mango Sticky Rice:7.99:Desserts|Thai Iced Tea:4.99:Drinks|Massaman Curry:16.99:Curries|Papaya Salad:9.99:Salads|Satay Chicken:10.99:Appetizers|Basil Fried Rice:13.99:Rice'
MENU_POOLS[Indian]='Butter Chicken:16.99:Curries|Naan Bread:3.99:Bread|Samosa:5.99:Appetizers|Biryani:15.99:Rice|Tikka Masala:17.99:Curries|Mango Lassi:4.99:Drinks|Dal Tadka:11.99:Mains|Palak Paneer:14.99:Curries|Tandoori Chicken:18.99:Mains|Gulab Jamun:6.99:Desserts'
MENU_POOLS[Chinese]='Kung Pao Chicken:14.99:Mains|Dim Sum Platter:12.99:Appetizers|Hot & Sour Soup:6.99:Soup|Fried Rice:10.99:Rice|Mapo Tofu:13.99:Mains|Spring Roll:5.99:Appetizers|Peking Duck:28.99:Mains|Wonton Soup:7.99:Soup|Chow Mein:12.99:Noodles|Boba Tea:5.99:Drinks'
MENU_POOLS[Mediterranean]='Falafel Wrap:11.99:Wraps|Hummus Platter:8.99:Appetizers|Shawarma Plate:15.99:Mains|Greek Salad:9.99:Salads|Lamb Kebab:18.99:Mains|Baklava:6.99:Desserts|Pita & Dips:7.99:Appetizers|Fattoush:8.99:Salads|Grilled Halloumi:10.99:Appetizers|Tabbouleh:7.99:Salads'
MENU_POOLS[French]='Croque Monsieur:12.99:Sandwiches|French Onion Soup:9.99:Soup|Coq au Vin:24.99:Mains|Creme Brulee:8.99:Desserts|Croissant:4.99:Pastries|Ratatouille:14.99:Mains|Nicoise Salad:13.99:Salads|Escargot:12.99:Appetizers|Beef Bourguignon:26.99:Mains|Tarte Tatin:9.99:Desserts'
MENU_POOLS[Korean]='Bibimbap:14.99:Rice|Korean Fried Chicken:15.99:Mains|Kimchi Jjigae:12.99:Soup|Japchae:11.99:Noodles|Bulgogi:17.99:Mains|Mandu:7.99:Appetizers|Tteokbokki:9.99:Snacks|Korean Corn Dog:6.99:Snacks|Soju Cocktail:8.99:Drinks|Hotteok:5.99:Desserts'

# Fallback for cuisines not in the pool
DEFAULT_MENU='House Special:15.99:Mains|Garden Salad:8.99:Salads|Soup of the Day:6.99:Soup|Grilled Vegetables:11.99:Sides|Chef Selection:19.99:Mains|Fresh Juice:5.99:Drinks|Seasonal Dessert:7.99:Desserts|Bread Basket:4.99:Sides'

#######################################################################
# Helper functions
#######################################################################
random_element() {
  local arr=("$@")
  echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

random_rating() {
  # Generate rating between 3.5 and 5.0
  local base=$((RANDOM % 16 + 35))
  echo "scale=1; $base / 10" | bc
}

#######################################################################
# Seed Customers
#######################################################################
echo "--- Seeding ${NUM_CUSTOMERS} customers ---"
CUSTOMER_IDS=()
CUSTOMER_ERRORS=0

for i in $(seq 1 "$NUM_CUSTOMERS"); do
  FIRST=$(random_element "${FIRST_NAMES[@]}")
  LAST=$(random_element "${LAST_NAMES[@]}")
  NAME="${FIRST} ${LAST}"
  EMAIL="${FIRST,,}.${LAST,,}.${BATCH_TAG}.${i}@contosomeals.com"

  RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "${ORDER_API_URL}/customers" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${NAME}\",\"email\":\"${EMAIL}\"}" 2>/dev/null || echo -e "\n000")

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [[ "$HTTP_CODE" == "201" ]]; then
    CID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$CID" ]; then
      CUSTOMER_IDS+=("$CID")
    fi
  else
    CUSTOMER_ERRORS=$((CUSTOMER_ERRORS + 1))
  fi

  # Progress
  if [ $((i % 5)) -eq 0 ]; then
    echo "  Created $i/${NUM_CUSTOMERS} customers (${#CUSTOMER_IDS[@]} ok, ${CUSTOMER_ERRORS} errors)"
  fi
done

echo "  ✓ Customers created: ${#CUSTOMER_IDS[@]}/${NUM_CUSTOMERS}"
echo ""

#######################################################################
# Seed Restaurants & Menus
#######################################################################
echo "--- Seeding ${NUM_RESTAURANTS} restaurants with menus ---"
RESTAURANT_IDS=()
RESTAURANT_ERRORS=0

for i in $(seq 1 "$NUM_RESTAURANTS"); do
  PREFIX=$(random_element "${RESTAURANT_PREFIXES[@]}")
  SUFFIX=$(random_element "${RESTAURANT_SUFFIXES[@]}")
  CITY=$(random_element "${CITIES[@]}")
  CUISINE=$(random_element "${CUISINES[@]}")
  RATING=$(random_rating)
  STREET_NUM=$((RANDOM % 999 + 100))
  STREET=$(random_element "${STREETS[@]}")
  REST_ID="restaurant-load-${BATCH_TAG}-${i}"

  # Create restaurant
  REST_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "${MENU_API_URL}/restaurants" \
    -H "Content-Type: application/json" \
    -d "{
      \"id\": \"${REST_ID}\",
      \"name\": \"${PREFIX} ${SUFFIX}\",
      \"city\": \"${CITY}\",
      \"cuisine\": \"${CUISINE}\",
      \"rating\": ${RATING},
      \"address\": \"${STREET_NUM} ${STREET}, ${CITY}\",
      \"isOpen\": true
    }" 2>/dev/null || echo -e "\n000")

  REST_HTTP=$(echo "$REST_RESPONSE" | tail -1)

  if [[ "$REST_HTTP" == "201" ]]; then
    RESTAURANT_IDS+=("$REST_ID")

    # Build menu items JSON for this cuisine
    MENU_DATA="${MENU_POOLS[$CUISINE]:-$DEFAULT_MENU}"
    MENU_ITEMS_JSON="["
    FIRST_ITEM=true

    # Pick 5-8 random items from the cuisine pool
    IFS='|' read -ra ALL_ITEMS <<< "$MENU_DATA"
    NUM_ITEMS=$((RANDOM % 4 + 5))
    if [ "$NUM_ITEMS" -gt "${#ALL_ITEMS[@]}" ]; then
      NUM_ITEMS="${#ALL_ITEMS[@]}"
    fi

    # Shuffle and pick
    SHUFFLED_ITEMS=($(shuf -e "${ALL_ITEMS[@]}" | head -n "$NUM_ITEMS"))

    for item_data in "${SHUFFLED_ITEMS[@]}"; do
      IFS=':' read -r ITEM_NAME ITEM_PRICE ITEM_CAT <<< "$item_data"
      if [ "$FIRST_ITEM" = true ]; then
        FIRST_ITEM=false
      else
        MENU_ITEMS_JSON+=","
      fi
      MENU_ITEMS_JSON+="{\"name\":\"${ITEM_NAME}\",\"price\":${ITEM_PRICE},\"category\":\"${ITEM_CAT}\",\"description\":\"Freshly prepared ${ITEM_NAME,,}\"}"
    done
    MENU_ITEMS_JSON+="]"

    # Create menu for this restaurant
    MENU_ID="menu-load-${BATCH_TAG}-${i}"
    curl -s -o /dev/null --max-time 10 \
      -X POST "${MENU_API_URL}/menus" \
      -H "Content-Type: application/json" \
      -d "{
        \"id\": \"${MENU_ID}\",
        \"restaurantId\": \"${REST_ID}\",
        \"items\": ${MENU_ITEMS_JSON}
      }" 2>/dev/null || true
  else
    RESTAURANT_ERRORS=$((RESTAURANT_ERRORS + 1))
  fi

  if [ $((i % 5)) -eq 0 ]; then
    echo "  Created $i/${NUM_RESTAURANTS} restaurants (${#RESTAURANT_IDS[@]} ok, ${RESTAURANT_ERRORS} errors)"
  fi
done

echo "  ✓ Restaurants created: ${#RESTAURANT_IDS[@]}/${NUM_RESTAURANTS}"
echo ""

#######################################################################
# Seed Orders (using created customers and restaurants)
#######################################################################
NUM_ORDERS=10
echo "--- Seeding ${NUM_ORDERS} orders ---"
ORDER_IDS=()
ORDER_ERRORS=0

ORDER_ITEMS_POOL=(
  '[{"name":"Classic Burger","price":12.99},{"name":"Truffle Fries","price":7.99}]|20.98'
  '[{"name":"Dragon Roll","price":16.99},{"name":"Miso Soup","price":4.99}]|21.98'
  '[{"name":"Margherita Pizza","price":13.99},{"name":"Caesar Salad","price":9.99}]|23.98'
  '[{"name":"Carne Asada Taco","price":4.99},{"name":"Al Pastor Taco","price":4.49},{"name":"Guacamole & Chips","price":8.99}]|18.47'
  '[{"name":"Pad Thai","price":14.99},{"name":"Thai Iced Tea","price":4.99}]|19.98'
  '[{"name":"Butter Chicken","price":16.99},{"name":"Naan Bread","price":3.99}]|20.98'
  '[{"name":"Bibimbap","price":14.99}]|14.99'
  '[{"name":"Pho Bo","price":14.99},{"name":"Spring Rolls","price":6.99}]|21.98'
  '[{"name":"Ribeye Steak","price":34.99},{"name":"Wedge Salad","price":9.99}]|44.98'
  '[{"name":"Falafel Wrap","price":11.99},{"name":"Hummus & Pita","price":8.99}]|20.98'
)
PAYMENT_METHODS=("credit_card" "debit_card" "apple_pay" "google_pay")

# Build combined customer + restaurant pools (seeded + originals)
ALL_CUST_IDS=("${CUSTOMER_IDS[@]}")
ALL_REST_IDS=("${RESTAURANT_IDS[@]}")
# Add original seed restaurant IDs
ALL_REST_IDS+=("restaurant-1" "restaurant-2" "restaurant-3" "restaurant-4")

for i in $(seq 1 "$NUM_ORDERS"); do
  CUST_ID=$(random_element "${ALL_CUST_IDS[@]}")
  REST_ID=$(random_element "${ALL_REST_IDS[@]}")
  IDX=$((RANDOM % ${#ORDER_ITEMS_POOL[@]}))
  ITEM_DATA="${ORDER_ITEMS_POOL[$IDX]}"
  ITEMS="${ITEM_DATA%%|*}"
  AMOUNT="${ITEM_DATA##*|}"
  PAY_METHOD=$(random_element "${PAYMENT_METHODS[@]}")

  RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "${ORDER_API_URL}/orders" \
    -H "Content-Type: application/json" \
    -d "{\"customerId\":\"${CUST_ID}\",\"restaurantId\":\"${REST_ID}\",\"items\":${ITEMS},\"totalAmount\":${AMOUNT},\"paymentMethod\":\"${PAY_METHOD}\"}" \
    2>/dev/null || echo -e "\n000")

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [[ "$HTTP_CODE" == "201" ]]; then
    OID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$OID" ]; then
      ORDER_IDS+=("$OID")
    fi
  else
    ORDER_ERRORS=$((ORDER_ERRORS + 1))
  fi

  if [ $((i % 5)) -eq 0 ]; then
    echo "  Created $i/${NUM_ORDERS} orders (${#ORDER_IDS[@]} ok, ${ORDER_ERRORS} errors)"
  fi
done

echo "  ✓ Orders created: ${#ORDER_IDS[@]}/${NUM_ORDERS}"
echo ""

#######################################################################
# Export IDs for load test consumption
#######################################################################
echo "--- Writing seed IDs to ${SEED_IDS_FILE} ---"

{
  echo "# Auto-generated by seed-data.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Batch Tag: ${BATCH_TAG}"
  echo "SEED_BATCH_TAG=${BATCH_TAG}"

  # Customer IDs (newline-separated array)
  echo "SEED_CUSTOMER_COUNT=${#CUSTOMER_IDS[@]}"
  for idx in "${!CUSTOMER_IDS[@]}"; do
    echo "SEED_CUSTOMER_${idx}=${CUSTOMER_IDS[$idx]}"
  done

  # Restaurant IDs (newline-separated array)
  echo "SEED_RESTAURANT_COUNT=${#RESTAURANT_IDS[@]}"
  for idx in "${!RESTAURANT_IDS[@]}"; do
    echo "SEED_RESTAURANT_${idx}=${RESTAURANT_IDS[$idx]}"
  done

  # Also include the original seed restaurant IDs for backward compat
  echo "SEED_RESTAURANT_ORIG_0=restaurant-1"
  echo "SEED_RESTAURANT_ORIG_1=restaurant-2"
  echo "SEED_RESTAURANT_ORIG_2=restaurant-3"
  echo "SEED_RESTAURANT_ORIG_3=restaurant-4"
} > "$SEED_IDS_FILE"

# Also write CSV versions for JMeter
CUSTOMER_CSV="/tmp/contoso-customers.csv"
RESTAURANT_CSV="/tmp/contoso-restaurants.csv"

echo "customerId" > "$CUSTOMER_CSV"
for cid in "${CUSTOMER_IDS[@]}"; do
  echo "$cid" >> "$CUSTOMER_CSV"
done
# Add original default customer
echo "00000000-0000-0000-0000-000000000001" >> "$CUSTOMER_CSV"

echo "restaurantId" > "$RESTAURANT_CSV"
for rid in "${RESTAURANT_IDS[@]}"; do
  echo "$rid" >> "$RESTAURANT_CSV"
done
# Add original seed restaurants
echo "restaurant-1" >> "$RESTAURANT_CSV"
echo "restaurant-2" >> "$RESTAURANT_CSV"
echo "restaurant-3" >> "$RESTAURANT_CSV"
echo "restaurant-4" >> "$RESTAURANT_CSV"

echo "  ✓ ID files written:"
echo "    Env file:      ${SEED_IDS_FILE}"
echo "    Customer CSV:  ${CUSTOMER_CSV} ($(wc -l < "$CUSTOMER_CSV") rows)"
echo "    Restaurant CSV: ${RESTAURANT_CSV} ($(wc -l < "$RESTAURANT_CSV") rows)"

echo ""
echo "============================================="
echo "  Data Seeding Complete"
echo "============================================="
echo "  Customers:    ${#CUSTOMER_IDS[@]} new + 1 default"
echo "  Restaurants:  ${#RESTAURANT_IDS[@]} new + 4 seed"
echo "  Orders:       ${#ORDER_IDS[@]} new"
echo "  Batch Tag:    ${BATCH_TAG}"
echo ""
echo "  To use with load test:"
echo "    source ${SEED_IDS_FILE}"
echo "    ./scripts/generate-load.sh"
echo ""
