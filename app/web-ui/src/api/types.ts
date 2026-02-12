export interface Restaurant {
  id: string;
  name: string;
  city: string;
  cuisine: string;
  rating: number;
  address: string;
  isOpen: boolean;
}

export interface MenuItem {
  name: string;
  price: number;
  category: string;
  description: string;
}

export interface Menu {
  id: string;
  restaurantId: string;
  items: MenuItem[];
  lastUpdated: string;
}

export interface CartItem {
  menuItem: MenuItem;
  quantity: number;
}

export interface Order {
  id: string;
  customerId: string;
  restaurantId: string;
  status: string;
  totalAmount: number;
  items: string;
  createdAt: string;
  updatedAt: string;
}

export interface OrderDetails extends Omit<Order, 'items'> {
  customerName: string | null;
  restaurantName: string | null;
  items: CartItem[] | string;
  paymentStatus: string | null;
}

export interface Customer {
  id: string;
  name: string;
  email: string;
  createdAt: string;
}

export interface PaymentResult {
  paymentId: string;
  status: string;
  error?: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface CreateOrderResponse {
  order: Order;
  payment?: PaymentResult;
}
