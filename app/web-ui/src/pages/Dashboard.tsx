import { useState, useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { getOrders, getCustomers } from '../api/client';
import type { Order, Customer } from '../api/types';

const STATUS_COLORS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  confirmed: 'bg-blue-100 text-blue-800',
  preparing: 'bg-orange-100 text-orange-800',
  ready: 'bg-green-100 text-green-800',
  delivered: 'bg-gray-100 text-gray-700',
  cancelled: 'bg-red-100 text-red-800',
  payment_failed: 'bg-red-100 text-red-800',
};

type Tab = 'orders' | 'customers';
type StatusFilter = 'all' | string;

export default function Dashboard() {
  const [tab, setTab] = useState<Tab>('orders');
  const [orders, setOrders] = useState<Order[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [totalOrders, setTotalOrders] = useState(0);
  const [totalCustomers, setTotalCustomers] = useState(0);
  const [orderPage, setOrderPage] = useState(1);
  const [customerPage, setCustomerPage] = useState(1);
  const pageSize = 50;
  const [loadingOrders, setLoadingOrders] = useState(true);
  const [loadingCustomers, setLoadingCustomers] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [customerSearch, setCustomerSearch] = useState('');

  // Build a customer lookup map
  const customerMap = useMemo(() => {
    const map = new Map<string, Customer>();
    customers.forEach(c => map.set(c.id, c));
    return map;
  }, [customers]);

  useEffect(() => {
    setLoadingOrders(true);
    getOrders(undefined, undefined, orderPage, pageSize)
      .then(res => { setOrders(res.items); setTotalOrders(res.totalCount); })
      .catch(e => setError(e.message))
      .finally(() => setLoadingOrders(false));
  }, [orderPage]);

  useEffect(() => {
    setLoadingCustomers(true);
    getCustomers(customerPage, pageSize)
      .then(res => { setCustomers(res.items); setTotalCustomers(res.totalCount); })
      .catch(e => setError(prev => prev || e.message))
      .finally(() => setLoadingCustomers(false));
  }, [customerPage]);

  // Refresh data
  function refresh() {
    setLoadingOrders(true);
    setLoadingCustomers(true);
    setError(null);
    getOrders(undefined, undefined, orderPage, pageSize)
      .then(res => { setOrders(res.items); setTotalOrders(res.totalCount); })
      .catch(e => setError(e.message))
      .finally(() => setLoadingOrders(false));
    getCustomers(customerPage, pageSize)
      .then(res => { setCustomers(res.items); setTotalCustomers(res.totalCount); })
      .catch(e => setError(prev => prev || e.message))
      .finally(() => setLoadingCustomers(false));
  }

  // Derived stats
  const stats = useMemo(() => {
    const totalRevenue = orders
      .filter(o => o.status !== 'cancelled' && o.status !== 'payment_failed')
      .reduce((sum, o) => sum + o.totalAmount, 0);
    const statusCounts: Record<string, number> = {};
    orders.forEach(o => {
      statusCounts[o.status] = (statusCounts[o.status] || 0) + 1;
    });
    return { totalOrders, totalRevenue, totalCustomers, statusCounts };
  }, [orders, customers, totalOrders, totalCustomers]);

  // Filtered orders
  const filteredOrders = useMemo(() => {
    if (statusFilter === 'all') return orders;
    return orders.filter(o => o.status === statusFilter);
  }, [orders, statusFilter]);

  // Filtered customers
  const filteredCustomers = useMemo(() => {
    if (!customerSearch.trim()) return customers;
    const q = customerSearch.toLowerCase();
    return customers.filter(
      c => c.name.toLowerCase().includes(q) || c.email.toLowerCase().includes(q)
    );
  }, [customers, customerSearch]);

  // Unique statuses for filter
  const statuses = useMemo(() => {
    const set = new Set(orders.map(o => o.status));
    return Array.from(set).sort();
  }, [orders]);

  // Parse items to get count
  function itemCount(itemsJson: string): number {
    try {
      const parsed = JSON.parse(itemsJson);
      if (Array.isArray(parsed)) return parsed.reduce((s: number, i: { quantity?: number }) => s + (i.quantity || 1), 0);
    } catch { /* ignore */ }
    return 0;
  }

  // Count orders per customer
  const ordersPerCustomer = useMemo(() => {
    const map = new Map<string, number>();
    orders.forEach(o => {
      map.set(o.customerId, (map.get(o.customerId) || 0) + 1);
    });
    return map;
  }, [orders]);

  // Revenue per customer
  const revenuePerCustomer = useMemo(() => {
    const map = new Map<string, number>();
    orders
      .filter(o => o.status !== 'cancelled' && o.status !== 'payment_failed')
      .forEach(o => {
        map.set(o.customerId, (map.get(o.customerId) || 0) + o.totalAmount);
      });
    return map;
  }, [orders]);

  const loading = loadingOrders || loadingCustomers;

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <button
          onClick={refresh}
          disabled={loading}
          className="px-4 py-2 text-sm bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50 transition"
        >
          {loading ? 'Refreshing...' : 'Refresh'}
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg mb-6 text-sm">
          {error}
        </div>
      )}

      {/* Summary cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <p className="text-sm text-gray-500">Total Orders</p>
          <p className="text-2xl font-bold text-gray-900">{stats.totalOrders}</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <p className="text-sm text-gray-500">Revenue</p>
          <p className="text-2xl font-bold text-green-600">${stats.totalRevenue.toFixed(2)}</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <p className="text-sm text-gray-500">Customers</p>
          <p className="text-2xl font-bold text-gray-900">{stats.totalCustomers}</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <p className="text-sm text-gray-500">Active Orders</p>
          <p className="text-2xl font-bold text-orange-600">
            {(stats.statusCounts['pending'] || 0) +
              (stats.statusCounts['confirmed'] || 0) +
              (stats.statusCounts['preparing'] || 0) +
              (stats.statusCounts['ready'] || 0)}
          </p>
        </div>
      </div>

      {/* Status breakdown pills */}
      {Object.keys(stats.statusCounts).length > 0 && (
        <div className="flex gap-2 flex-wrap mb-6">
          {Object.entries(stats.statusCounts)
            .sort(([, a], [, b]) => b - a)
            .map(([status, count]) => (
              <span
                key={status}
                className={`inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium ${STATUS_COLORS[status] || 'bg-gray-100 text-gray-800'}`}
              >
                {status.replace('_', ' ')} <span className="font-bold">{count}</span>
              </span>
            ))}
        </div>
      )}

      {/* Tabs */}
      <div className="flex gap-1 mb-4 bg-gray-100 p-1 rounded-lg w-fit">
        <button
          onClick={() => setTab('orders')}
          className={`px-4 py-2 text-sm font-medium rounded-md transition ${
            tab === 'orders' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          Orders ({totalOrders})
        </button>
        <button
          onClick={() => setTab('customers')}
          className={`px-4 py-2 text-sm font-medium rounded-md transition ${
            tab === 'customers' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          Customers ({totalCustomers})
        </button>
      </div>

      {/* Orders tab */}
      {tab === 'orders' && (
        <div>
          {/* Status filter */}
          <div className="flex gap-2 flex-wrap mb-4">
            <button
              onClick={() => setStatusFilter('all')}
              className={`px-3 py-1 rounded-full text-xs font-medium transition ${
                statusFilter === 'all' ? 'bg-orange-500 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              All
            </button>
            {statuses.map(s => (
              <button
                key={s}
                onClick={() => setStatusFilter(s)}
                className={`px-3 py-1 rounded-full text-xs font-medium transition capitalize ${
                  statusFilter === s ? 'bg-orange-500 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                {s.replace('_', ' ')}
              </button>
            ))}
          </div>

          {loading ? (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filteredOrders.length === 0 ? (
            <p className="text-gray-500 text-center py-8">No orders found.</p>
          ) : (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-gray-50 border-b border-gray-200">
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Order</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Restaurant</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Items</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {filteredOrders.map(order => {
                      const customer = customerMap.get(order.customerId);
                      return (
                        <tr key={order.id} className="hover:bg-gray-50 transition">
                          <td className="px-4 py-3">
                            <Link
                              to={`/orders/${order.id}`}
                              className="text-orange-600 hover:underline font-medium"
                            >
                              #{order.id.slice(0, 8)}
                            </Link>
                          </td>
                          <td className="px-4 py-3">
                            {customer ? (
                              <div>
                                <p className="font-medium text-gray-900">{customer.name}</p>
                                <p className="text-xs text-gray-500">{customer.email}</p>
                              </div>
                            ) : (
                              <span className="text-gray-400 text-xs">{order.customerId.slice(0, 8)}...</span>
                            )}
                          </td>
                          <td className="px-4 py-3 text-gray-700">{order.restaurantId}</td>
                          <td className="px-4 py-3 text-gray-700">{itemCount(order.items)}</td>
                          <td className="px-4 py-3 font-semibold text-gray-900">
                            ${order.totalAmount.toFixed(2)}
                          </td>
                          <td className="px-4 py-3">
                            <span
                              className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium capitalize ${
                                STATUS_COLORS[order.status] || 'bg-gray-100 text-gray-800'
                              }`}
                            >
                              {order.status.replace('_', ' ')}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                            {new Date(order.createdAt).toLocaleDateString()}{' '}
                            {new Date(order.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
          {/* Order pagination */}
          {!loading && totalOrders > pageSize && (
            <div className="flex items-center justify-between mt-4">
              <p className="text-sm text-gray-500">
                Showing {(orderPage - 1) * pageSize + 1}–{Math.min(orderPage * pageSize, totalOrders)} of {totalOrders} orders
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setOrderPage(p => Math.max(1, p - 1))}
                  disabled={orderPage <= 1}
                  className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-40 transition"
                >
                  Previous
                </button>
                <button
                  onClick={() => setOrderPage(p => p + 1)}
                  disabled={orderPage * pageSize >= totalOrders}
                  className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-40 transition"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Customers tab */}
      {tab === 'customers' && (
        <div>
          <input
            type="text"
            placeholder="Search by name or email..."
            value={customerSearch}
            onChange={e => setCustomerSearch(e.target.value)}
            className="w-full max-w-md px-4 py-2 border border-gray-300 rounded-lg mb-4 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent"
          />

          {loadingCustomers ? (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filteredCustomers.length === 0 ? (
            <p className="text-gray-500 text-center py-8">No customers found.</p>
          ) : (
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-gray-50 border-b border-gray-200">
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Name</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Email</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Orders</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Total Spent</th>
                      <th className="text-left px-4 py-3 font-medium text-gray-600">Joined</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {filteredCustomers.map(customer => (
                      <tr key={customer.id} className="hover:bg-gray-50 transition">
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <div className="w-8 h-8 rounded-full bg-orange-100 text-orange-600 flex items-center justify-center font-semibold text-sm">
                              {customer.name.charAt(0).toUpperCase()}
                            </div>
                            <span className="font-medium text-gray-900">{customer.name}</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-gray-600">{customer.email}</td>
                        <td className="px-4 py-3 text-gray-700 font-medium">
                          {ordersPerCustomer.get(customer.id) || 0}
                        </td>
                        <td className="px-4 py-3 font-semibold text-gray-900">
                          ${(revenuePerCustomer.get(customer.id) || 0).toFixed(2)}
                        </td>
                        <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                          {new Date(customer.createdAt).toLocaleDateString()}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
          {/* Customer pagination */}
          {!loadingCustomers && totalCustomers > pageSize && (
            <div className="flex items-center justify-between mt-4">
              <p className="text-sm text-gray-500">
                Showing {(customerPage - 1) * pageSize + 1}–{Math.min(customerPage * pageSize, totalCustomers)} of {totalCustomers} customers
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setCustomerPage(p => Math.max(1, p - 1))}
                  disabled={customerPage <= 1}
                  className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-40 transition"
                >
                  Previous
                </button>
                <button
                  onClick={() => setCustomerPage(p => p + 1)}
                  disabled={customerPage * pageSize >= totalCustomers}
                  className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-40 transition"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
