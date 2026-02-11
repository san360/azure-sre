import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getRestaurants, searchRestaurants } from '../api/client';
import type { Restaurant } from '../api/types';

const CITIES = ['All Cities', 'Seattle', 'Portland', 'San Francisco'];

export default function Home() {
  const [restaurants, setRestaurants] = useState<Restaurant[]>([]);
  const [selectedCity, setSelectedCity] = useState('All Cities');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);

    const city = selectedCity === 'All Cities' ? undefined : selectedCity;
    const request = search.trim()
      ? searchRestaurants(search.trim(), city)
      : getRestaurants(city);

    request
      .then(setRestaurants)
      .catch(e => setError(e.message))
      .finally(() => setLoading(false));
  }, [selectedCity, search]);

  function renderStars(rating: number) {
    const full = Math.floor(rating);
    const half = rating % 1 >= 0.25;
    return (
      <span className="text-yellow-500 text-sm">
        {'★'.repeat(full)}{half ? '½' : ''}
        <span className="text-gray-300">{'★'.repeat(5 - full - (half ? 1 : 0))}</span>
        <span className="ml-1 text-gray-600 text-xs">{rating.toFixed(1)}</span>
      </span>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 mb-4">Restaurants</h1>

        <input
          type="text"
          placeholder="Search restaurants by name or cuisine..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full max-w-md px-4 py-2 border border-gray-300 rounded-lg mb-4 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent"
        />

        <div className="flex gap-2 flex-wrap">
          {CITIES.map(city => (
            <button
              key={city}
              onClick={() => setSelectedCity(city)}
              className={`px-4 py-1.5 rounded-full text-sm font-medium transition ${
                selectedCity === city
                  ? 'bg-orange-500 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              {city}
            </button>
          ))}
        </div>
      </div>

      {loading && (
        <div className="flex justify-center py-12">
          <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
          Unable to load restaurants: {error}
          <button onClick={() => setSearch(s => s)} className="ml-2 underline">Retry</button>
        </div>
      )}

      {!loading && !error && restaurants.length === 0 && (
        <p className="text-gray-500 text-center py-8">No restaurants found.</p>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
        {restaurants.map(r => (
          <Link
            key={r.id}
            to={r.isOpen ? `/restaurants/${r.id}` : '#'}
            className={`block bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden transition hover:shadow-md ${
              !r.isOpen ? 'opacity-50 pointer-events-none' : ''
            }`}
          >
            <div className="p-4">
              <div className="flex items-start justify-between mb-2">
                <h3 className="font-semibold text-gray-900">{r.name}</h3>
                <span className={`text-xs px-2 py-0.5 rounded-full ${
                  r.isOpen ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
                }`}>
                  {r.isOpen ? 'Open' : 'Closed'}
                </span>
              </div>
              <div className="mb-2">{renderStars(r.rating)}</div>
              <p className="text-sm text-gray-600">{r.cuisine}</p>
              <p className="text-xs text-gray-400 mt-1">{r.city} &middot; {r.address}</p>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
