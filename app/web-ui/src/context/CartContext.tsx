import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import type { MenuItem, CartItem } from '../api/types';

interface CartState {
  restaurantId: string | null;
  restaurantName: string | null;
  items: CartItem[];
}

interface CartContextType {
  cart: CartState;
  addItem: (restaurantId: string, restaurantName: string, item: MenuItem) => void;
  removeItem: (itemName: string) => void;
  updateQuantity: (itemName: string, quantity: number) => void;
  clearCart: () => void;
  totalAmount: number;
  totalItems: number;
}

const CartContext = createContext<CartContextType | null>(null);

const EMPTY_CART: CartState = { restaurantId: null, restaurantName: null, items: [] };

export function CartProvider({ children }: { children: ReactNode }) {
  const [cart, setCart] = useState<CartState>(() => {
    try {
      const saved = localStorage.getItem('contoso-cart');
      return saved ? JSON.parse(saved) : EMPTY_CART;
    } catch {
      return EMPTY_CART;
    }
  });

  const persist = (next: CartState) => {
    setCart(next);
    localStorage.setItem('contoso-cart', JSON.stringify(next));
  };

  const addItem = useCallback((restaurantId: string, restaurantName: string, item: MenuItem) => {
    setCart(prev => {
      // If switching restaurants, clear the cart
      if (prev.restaurantId && prev.restaurantId !== restaurantId) {
        const next: CartState = {
          restaurantId,
          restaurantName,
          items: [{ menuItem: item, quantity: 1 }],
        };
        localStorage.setItem('contoso-cart', JSON.stringify(next));
        return next;
      }

      const existing = prev.items.find(i => i.menuItem.name === item.name);
      let nextItems: CartItem[];
      if (existing) {
        nextItems = prev.items.map(i =>
          i.menuItem.name === item.name ? { ...i, quantity: i.quantity + 1 } : i
        );
      } else {
        nextItems = [...prev.items, { menuItem: item, quantity: 1 }];
      }

      const next: CartState = { restaurantId, restaurantName, items: nextItems };
      localStorage.setItem('contoso-cart', JSON.stringify(next));
      return next;
    });
  }, []);

  const removeItem = useCallback((itemName: string) => {
    setCart(prev => {
      const next: CartState = {
        ...prev,
        items: prev.items.filter(i => i.menuItem.name !== itemName),
      };
      if (next.items.length === 0) {
        localStorage.removeItem('contoso-cart');
        return EMPTY_CART;
      }
      localStorage.setItem('contoso-cart', JSON.stringify(next));
      return next;
    });
  }, []);

  const updateQuantity = useCallback((itemName: string, quantity: number) => {
    setCart(prev => {
      if (quantity <= 0) {
        const next: CartState = {
          ...prev,
          items: prev.items.filter(i => i.menuItem.name !== itemName),
        };
        if (next.items.length === 0) {
          localStorage.removeItem('contoso-cart');
          return EMPTY_CART;
        }
        localStorage.setItem('contoso-cart', JSON.stringify(next));
        return next;
      }

      const next: CartState = {
        ...prev,
        items: prev.items.map(i =>
          i.menuItem.name === itemName ? { ...i, quantity } : i
        ),
      };
      localStorage.setItem('contoso-cart', JSON.stringify(next));
      return next;
    });
  }, []);

  const clearCart = useCallback(() => {
    localStorage.removeItem('contoso-cart');
    persist(EMPTY_CART);
  }, []);

  const totalAmount = cart.items.reduce((sum, i) => sum + i.menuItem.price * i.quantity, 0);
  const totalItems = cart.items.reduce((sum, i) => sum + i.quantity, 0);

  return (
    <CartContext.Provider value={{ cart, addItem, removeItem, updateQuantity, clearCart, totalAmount, totalItems }}>
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) throw new Error('useCart must be used within CartProvider');
  return context;
}
