import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { createOrder, createCustomer } from '../api/client';
import type { Order } from '../api/types';

export default function Checkout() {
  const { cart, totalAmount, clearCart } = useCart();
  const navigate = useNavigate();

  const [name, setName] = useState(() => localStorage.getItem('contoso-name') || '');
  const [email, setEmail] = useState(() => localStorage.getItem('contoso-email') || '');
  const [paymentMethod, setPaymentMethod] = useState('credit_card');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (cart.items.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-gray-500 mb-4">Your cart is empty.</p>
        <Link to="/" className="text-orange-600 hover:underline">Browse restaurants</Link>
      </div>
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || !email.trim()) {
      setError('Name and email are required.');
      return;
    }
    if (!cart.restaurantId) return;

    setLoading(true);
    setError(null);

    try {
      // Save customer info locally
      localStorage.setItem('contoso-name', name);
      localStorage.setItem('contoso-email', email);

      // Create or get customer
      let customerId: string;
      try {
        const customer = await createCustomer(name.trim(), email.trim());
        customerId = customer.id;
        localStorage.setItem('contoso-customerId', customerId);
      } catch {
        // Customer may already exist; use stored ID
        customerId = localStorage.getItem('contoso-customerId') || '00000000-0000-0000-0000-000000000001';
      }

      const result = await createOrder({
        customerId,
        restaurantId: cart.restaurantId,
        items: cart.items.map(i => ({
          name: i.menuItem.name,
          price: i.menuItem.price,
          quantity: i.quantity,
        })),
        totalAmount,
        paymentMethod,
      });

      const orderId = result.order?.id ?? (result as unknown as Order).id;
      clearCart();
      navigate(`/orders/${orderId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to place order. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-lg mx-auto">
      <Link to="/" className="text-sm text-orange-600 hover:underline mb-4 inline-block">
        &larr; Continue shopping
      </Link>

      <h1 className="text-2xl font-bold text-gray-900 mb-6">Checkout</h1>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
        <h2 className="font-semibold text-gray-900 mb-2">Order from {cart.restaurantName}</h2>
        <div className="space-y-1">
          {cart.items.map(ci => (
            <div key={ci.menuItem.name} className="flex justify-between text-sm">
              <span className="text-gray-700">{ci.menuItem.name} x{ci.quantity}</span>
              <span className="font-medium">${(ci.menuItem.price * ci.quantity).toFixed(2)}</span>
            </div>
          ))}
        </div>
        <div className="border-t border-gray-200 mt-3 pt-3 flex justify-between font-bold text-lg">
          <span>Total</span>
          <span>${totalAmount.toFixed(2)}</span>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <h2 className="font-semibold text-gray-900 mb-3">Your Details</h2>
          <div className="space-y-3">
            <div>
              <label className="block text-sm text-gray-600 mb-1">Name</label>
              <input
                type="text"
                value={name}
                onChange={e => setName(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500"
                required
              />
            </div>
            <div>
              <label className="block text-sm text-gray-600 mb-1">Email</label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500"
                required
              />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <h2 className="font-semibold text-gray-900 mb-3">Payment</h2>
          <div className="flex gap-4">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="payment"
                value="credit_card"
                checked={paymentMethod === 'credit_card'}
                onChange={e => setPaymentMethod(e.target.value)}
                className="accent-orange-500"
              />
              <span className="text-sm">Credit Card</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="payment"
                value="debit_card"
                checked={paymentMethod === 'debit_card'}
                onChange={e => setPaymentMethod(e.target.value)}
                className="accent-orange-500"
              />
              <span className="text-sm">Debit Card</span>
            </label>
          </div>
        </div>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={loading}
          className="w-full bg-orange-500 text-white py-3 rounded-lg font-semibold hover:bg-orange-600 disabled:bg-orange-300 transition"
        >
          {loading ? 'Placing order...' : `Place Order — $${totalAmount.toFixed(2)}`}
        </button>
      </form>
    </div>
  );
}
