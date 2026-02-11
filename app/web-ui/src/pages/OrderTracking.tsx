import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { getOrderDetails } from '../api/client';
import type { OrderDetails } from '../api/types';

const STATUS_STEPS = ['pending', 'confirmed', 'preparing', 'ready', 'delivered'];

const STATUS_COLORS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  confirmed: 'bg-blue-100 text-blue-800',
  preparing: 'bg-orange-100 text-orange-800',
  ready: 'bg-green-100 text-green-800',
  delivered: 'bg-gray-100 text-gray-800',
  cancelled: 'bg-red-100 text-red-800',
  payment_failed: 'bg-red-100 text-red-800',
};

export default function OrderTracking() {
  const { orderId } = useParams<{ orderId: string }>();
  const [order, setOrder] = useState<OrderDetails | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!orderId) return;

    function fetchOrder() {
      getOrderDetails(orderId!)
        .then(d => { setOrder(d); setError(null); })
        .catch(e => setError(e.message))
        .finally(() => setLoading(false));
    }

    fetchOrder();
    const interval = setInterval(fetchOrder, 5000);
    return () => clearInterval(interval);
  }, [orderId]);

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (error || !order) {
    return (
      <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
        {error || 'Order not found'}
      </div>
    );
  }

  const currentStepIndex = STATUS_STEPS.indexOf(order.status);
  const isTerminal = ['delivered', 'cancelled', 'payment_failed'].includes(order.status);

  function parseItems(): Array<{ name: string; price: number; quantity: number }> {
    try {
      if (typeof order!.items === 'string') {
        return JSON.parse(order!.items);
      }
      if (Array.isArray(order!.items)) {
        return order!.items.map(i => {
          if ('menuItem' in i) {
            return { name: i.menuItem.name, price: i.menuItem.price, quantity: i.quantity };
          }
          return i as unknown as { name: string; price: number; quantity: number };
        });
      }
    } catch { /* fall through */ }
    return [];
  }

  const items = parseItems();

  return (
    <div className="max-w-lg mx-auto">
      <Link to="/orders" className="text-sm text-orange-600 hover:underline mb-4 inline-block">
        &larr; All orders
      </Link>

      <h1 className="text-2xl font-bold text-gray-900 mb-2">
        Order #{orderId?.slice(0, 8)}
      </h1>

      {/* Status badge */}
      <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium mb-6 ${STATUS_COLORS[order.status] || 'bg-gray-100 text-gray-800'}`}>
        {order.status.replace('_', ' ')}
      </span>

      {/* Progress bar */}
      {!isTerminal && (
        <div className="mb-8">
          <div className="flex items-center justify-between">
            {STATUS_STEPS.map((step, i) => (
              <div key={step} className="flex flex-col items-center flex-1">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                  i <= currentStepIndex
                    ? 'bg-orange-500 text-white'
                    : 'bg-gray-200 text-gray-500'
                }`}>
                  {i <= currentStepIndex ? '✓' : i + 1}
                </div>
                <span className="text-xs text-gray-500 mt-1 capitalize">{step}</span>
              </div>
            ))}
          </div>
          <div className="mt-2 h-1 bg-gray-200 rounded-full overflow-hidden">
            <div
              className="h-full bg-orange-500 transition-all duration-500"
              style={{ width: `${((currentStepIndex + 1) / STATUS_STEPS.length) * 100}%` }}
            />
          </div>
        </div>
      )}

      {/* Order details card */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-4">
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-500">Restaurant</span>
            <span className="font-medium">{order.restaurantName || order.restaurantId}</span>
          </div>
          {order.customerName && (
            <div className="flex justify-between">
              <span className="text-gray-500">Customer</span>
              <span className="font-medium">{order.customerName}</span>
            </div>
          )}
          <div className="flex justify-between">
            <span className="text-gray-500">Placed</span>
            <span className="font-medium">{new Date(order.createdAt).toLocaleString()}</span>
          </div>
          {order.paymentStatus && (
            <div className="flex justify-between">
              <span className="text-gray-500">Payment</span>
              <span className={`font-medium ${order.paymentStatus === 'completed' ? 'text-green-600' : 'text-red-600'}`}>
                {order.paymentStatus}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Items */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
        <h2 className="font-semibold text-gray-900 mb-3">Items</h2>
        <div className="space-y-1">
          {items.map((item, idx) => (
            <div key={idx} className="flex justify-between text-sm">
              <span className="text-gray-700">{item.name} x{item.quantity}</span>
              <span className="font-medium">${(item.price * item.quantity).toFixed(2)}</span>
            </div>
          ))}
        </div>
        <div className="border-t border-gray-200 mt-3 pt-3 flex justify-between font-bold">
          <span>Total</span>
          <span>${order.totalAmount.toFixed(2)}</span>
        </div>
      </div>
    </div>
  );
}
