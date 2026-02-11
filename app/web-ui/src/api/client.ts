import type { Restaurant, Menu, Order, OrderDetails, Customer, CreateOrderResponse } from './types';

const MENU_API = import.meta.env.VITE_MENU_API_URL || '/api/menu';
const ORDER_API = import.meta.env.VITE_ORDER_API_URL || '/api/orders';
const PAYMENT_API = import.meta.env.VITE_PAYMENT_API_URL || '/api/payments';

async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  return res.json();
}

// --- Restaurant / Menu ---
export async function getRestaurants(city?: string): Promise<Restaurant[]> {
  const params = city ? `?city=${encodeURIComponent(city)}` : '';
  return fetchJson<Restaurant[]>(`${MENU_API}/restaurants${params}`);
}

export async function searchRestaurants(q?: string, city?: string): Promise<Restaurant[]> {
  const params = new URLSearchParams();
  if (q) params.set('q', q);
  if (city) params.set('city', city);
  const qs = params.toString();
  return fetchJson<Restaurant[]>(`${MENU_API}/restaurants/search${qs ? `?${qs}` : ''}`);
}

export async function getRestaurant(id: string): Promise<Restaurant> {
  return fetchJson<Restaurant>(`${MENU_API}/restaurants/${id}`);
}

export async function getMenu(restaurantId: string): Promise<Menu> {
  return fetchJson<Menu>(`${MENU_API}/menus/${restaurantId}`);
}

// --- Orders ---
export async function getOrders(customerId?: string, status?: string): Promise<Order[]> {
  const params = new URLSearchParams();
  if (customerId) params.set('customerId', customerId);
  if (status) params.set('status', status);
  const qs = params.toString();
  return fetchJson<Order[]>(`${ORDER_API}/orders${qs ? `?${qs}` : ''}`);
}

export async function getOrder(id: string): Promise<Order> {
  return fetchJson<Order>(`${ORDER_API}/orders/${id}`);
}

export async function getOrderDetails(id: string): Promise<OrderDetails> {
  return fetchJson<OrderDetails>(`${ORDER_API}/orders/${id}/details`);
}

export async function createOrder(payload: {
  customerId: string;
  restaurantId: string;
  items: { name: string; price: number; quantity: number }[];
  totalAmount: number;
  paymentMethod?: string;
}): Promise<CreateOrderResponse> {
  return fetchJson<CreateOrderResponse>(`${ORDER_API}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

export async function cancelOrder(id: string): Promise<{ id: string; status: string }> {
  return fetchJson<{ id: string; status: string }>(`${ORDER_API}/orders/${id}`, {
    method: 'DELETE',
  });
}

// --- Customers ---
export async function getCustomer(id: string): Promise<Customer> {
  return fetchJson<Customer>(`${ORDER_API}/customers/${id}`);
}

export async function createCustomer(name: string, email: string): Promise<Customer> {
  return fetchJson<Customer>(`${ORDER_API}/customers`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email }),
  });
}

// --- Payments ---
export async function getPayments(orderId: string) {
  return fetchJson<Array<{ id: string; orderId: string; amount: number; status: string; processedAt: string }>>(
    `${PAYMENT_API}/payments/${orderId}`
  );
}
