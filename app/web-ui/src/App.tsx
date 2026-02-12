import { Routes, Route, Link } from 'react-router-dom'
import { useCart } from './context/CartContext'
import Home from './pages/Home'
import RestaurantMenu from './pages/RestaurantMenu'
import Checkout from './pages/Checkout'
import OrderTracking from './pages/OrderTracking'
import OrderHistory from './pages/OrderHistory'
import Dashboard from './pages/Dashboard'

export default function App() {
  const { totalItems } = useCart();

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
          <Link to="/" className="text-xl font-bold text-orange-600">
            Contoso Meals
          </Link>
          <div className="flex items-center gap-4">
            <Link to="/dashboard" className="text-sm text-gray-600 hover:text-gray-900">
              Dashboard
            </Link>
            <Link to="/orders" className="text-sm text-gray-600 hover:text-gray-900">
              My Orders
            </Link>
            <Link to="/checkout" className="relative text-sm text-gray-600 hover:text-gray-900">
              Cart
              {totalItems > 0 && (
                <span className="absolute -top-2 -right-4 bg-orange-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
                  {totalItems}
                </span>
              )}
            </Link>
          </div>
        </div>
      </nav>
      <main className="max-w-6xl mx-auto px-4 py-6">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/restaurants/:restaurantId" element={<RestaurantMenu />} />
          <Route path="/checkout" element={<Checkout />} />
          <Route path="/orders/:orderId" element={<OrderTracking />} />
          <Route path="/orders" element={<OrderHistory />} />
          <Route path="/dashboard" element={<Dashboard />} />
        </Routes>
      </main>
    </div>
  );
}
