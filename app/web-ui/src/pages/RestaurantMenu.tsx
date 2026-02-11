import { useState, useEffect, useMemo } from 'react';
import { useParams, Link } from 'react-router-dom';
import { getRestaurant, getMenu } from '../api/client';
import { useCart } from '../context/CartContext';
import type { Restaurant, Menu, MenuItem } from '../api/types';

export default function RestaurantMenu() {
  const { restaurantId } = useParams<{ restaurantId: string }>();
  const [restaurant, setRestaurant] = useState<Restaurant | null>(null);
  const [menu, setMenu] = useState<Menu | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeCategory, setActiveCategory] = useState<string | null>(null);

  const { cart, addItem, updateQuantity, totalAmount } = useCart();

  useEffect(() => {
    if (!restaurantId) return;
    setLoading(true);
    setError(null);

    Promise.all([getRestaurant(restaurantId), getMenu(restaurantId)])
      .then(([r, m]) => {
        setRestaurant(r);
        setMenu(m);
        if (m.items.length > 0) {
          setActiveCategory(m.items[0].category);
        }
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false));
  }, [restaurantId]);

  const categories = useMemo(() => {
    if (!menu) return [];
    return [...new Set(menu.items.map(i => i.category))];
  }, [menu]);

  const filteredItems = useMemo(() => {
    if (!menu) return [];
    if (!activeCategory) return menu.items;
    return menu.items.filter(i => i.category === activeCategory);
  }, [menu, activeCategory]);

  function getCartQty(itemName: string) {
    return cart.items.find(i => i.menuItem.name === itemName)?.quantity ?? 0;
  }

  function handleAdd(item: MenuItem) {
    if (restaurant) {
      addItem(restaurant.id, restaurant.name, item);
    }
  }

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (error || !restaurant || !menu) {
    return (
      <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
        {error || 'Restaurant not found'}
      </div>
    );
  }

  return (
    <div>
      <Link to="/" className="text-sm text-orange-600 hover:underline mb-4 inline-block">
        &larr; Back to restaurants
      </Link>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{restaurant.name}</h1>
            <p className="text-gray-600 mt-1">
              {restaurant.cuisine} &middot; {'★'.repeat(Math.floor(restaurant.rating))}
              <span className="text-gray-400 ml-1">{restaurant.rating.toFixed(1)}</span>
            </p>
            <p className="text-sm text-gray-400 mt-1">{restaurant.address}</p>
          </div>
          <span className={`text-xs px-2 py-0.5 rounded-full ${
            restaurant.isOpen ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
          }`}>
            {restaurant.isOpen ? 'Open' : 'Closed'}
          </span>
        </div>

        {!restaurant.isOpen && (
          <div className="mt-4 bg-yellow-50 border border-yellow-200 text-yellow-700 px-4 py-2 rounded-lg text-sm">
            This restaurant is currently closed. Menu is read-only.
          </div>
        )}
      </div>

      <div className="flex gap-6">
        {/* Menu section */}
        <div className="flex-1">
          <div className="flex gap-2 flex-wrap mb-4">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setActiveCategory(cat)}
                className={`px-3 py-1 rounded-full text-sm font-medium transition ${
                  activeCategory === cat
                    ? 'bg-orange-500 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>

          <div className="space-y-3">
            {filteredItems.map(item => {
              const qty = getCartQty(item.name);
              return (
                <div key={item.name} className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 flex items-center justify-between">
                  <div className="flex-1">
                    <div className="flex items-baseline gap-2">
                      <h3 className="font-medium text-gray-900">{item.name}</h3>
                      <span className="text-orange-600 font-semibold">${item.price.toFixed(2)}</span>
                    </div>
                    <p className="text-sm text-gray-500 mt-0.5">{item.description}</p>
                  </div>

                  <div className="flex items-center gap-2 ml-4">
                    {qty > 0 ? (
                      <>
                        <button
                          onClick={() => updateQuantity(item.name, qty - 1)}
                          className="w-8 h-8 rounded-full bg-gray-200 text-gray-700 flex items-center justify-center hover:bg-gray-300"
                        >-</button>
                        <span className="w-6 text-center font-medium">{qty}</span>
                        <button
                          onClick={() => handleAdd(item)}
                          className="w-8 h-8 rounded-full bg-orange-500 text-white flex items-center justify-center hover:bg-orange-600"
                        >+</button>
                      </>
                    ) : (
                      <button
                        onClick={() => handleAdd(item)}
                        disabled={!restaurant.isOpen}
                        className="px-4 py-1.5 bg-orange-500 text-white text-sm rounded-lg hover:bg-orange-600 disabled:bg-gray-300 disabled:cursor-not-allowed"
                      >
                        Add
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Cart sidebar */}
        {cart.items.length > 0 && cart.restaurantId === restaurantId && (
          <div className="w-72 shrink-0 hidden lg:block">
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 sticky top-4">
              <h2 className="font-semibold text-gray-900 mb-3">Your Order</h2>
              <div className="space-y-2">
                {cart.items.map(ci => (
                  <div key={ci.menuItem.name} className="flex justify-between text-sm">
                    <span className="text-gray-700">
                      {ci.menuItem.name} x{ci.quantity}
                    </span>
                    <span className="text-gray-900 font-medium">
                      ${(ci.menuItem.price * ci.quantity).toFixed(2)}
                    </span>
                  </div>
                ))}
              </div>
              <div className="border-t border-gray-200 mt-3 pt-3 flex justify-between font-semibold">
                <span>Subtotal</span>
                <span>${totalAmount.toFixed(2)}</span>
              </div>
              <Link
                to="/checkout"
                className="mt-4 block w-full text-center bg-orange-500 text-white py-2 rounded-lg font-medium hover:bg-orange-600 transition"
              >
                Checkout &rarr;
              </Link>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
