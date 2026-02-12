using Microsoft.Azure.Cosmos;
using MenuApi.Models;
using Menu = MenuApi.Models.Menu;

namespace MenuApi.Services;

public class CosmosDbService
{
    private readonly Container _restaurantsContainer;
    private readonly Container _menusContainer;
    private readonly Database _database;

    public CosmosDbService(CosmosClient cosmosClient, string databaseName)
    {
        _database = cosmosClient.GetDatabase(databaseName);
        _restaurantsContainer = _database.GetContainer("restaurants");
        _menusContainer = _database.GetContainer("menus");
    }

    public async Task<IEnumerable<Restaurant>> GetRestaurantsAsync(string? city = null)
    {
        var results = new List<Restaurant>();

        QueryDefinition query;
        if (!string.IsNullOrWhiteSpace(city))
        {
            query = new QueryDefinition("SELECT * FROM c WHERE c.city = @city")
                .WithParameter("@city", city);
        }
        else
        {
            query = new QueryDefinition("SELECT * FROM c");
        }

        var queryOptions = new QueryRequestOptions();
        if (!string.IsNullOrWhiteSpace(city))
        {
            queryOptions.PartitionKey = new PartitionKey(city);
        }

        using var iterator = _restaurantsContainer.GetItemQueryIterator<Restaurant>(query, requestOptions: queryOptions);
        while (iterator.HasMoreResults)
        {
            var response = await iterator.ReadNextAsync();
            results.AddRange(response);
        }

        return results;
    }

    // F-MENU-1: Search restaurants by name or cuisine with optional city filter
    public async Task<IEnumerable<Restaurant>> SearchRestaurantsAsync(string? searchQuery, string? city = null)
    {
        var results = new List<Restaurant>();

        var conditions = new List<string>();
        var queryDef = new QueryDefinition("SELECT * FROM c");

        if (!string.IsNullOrWhiteSpace(city))
        {
            conditions.Add("c.city = @city");
        }

        if (!string.IsNullOrWhiteSpace(searchQuery))
        {
            conditions.Add("(CONTAINS(LOWER(c.name), LOWER(@q)) OR CONTAINS(LOWER(c.cuisine), LOWER(@q)))");
        }

        var sql = "SELECT * FROM c";
        if (conditions.Count > 0)
        {
            sql += " WHERE " + string.Join(" AND ", conditions);
        }

        queryDef = new QueryDefinition(sql);

        if (!string.IsNullOrWhiteSpace(city))
        {
            queryDef = queryDef.WithParameter("@city", city);
        }
        if (!string.IsNullOrWhiteSpace(searchQuery))
        {
            queryDef = queryDef.WithParameter("@q", searchQuery);
        }

        var queryOptions = new QueryRequestOptions();
        if (!string.IsNullOrWhiteSpace(city))
        {
            queryOptions.PartitionKey = new PartitionKey(city);
        }

        using var iterator = _restaurantsContainer.GetItemQueryIterator<Restaurant>(queryDef, requestOptions: queryOptions);
        while (iterator.HasMoreResults)
        {
            var response = await iterator.ReadNextAsync();
            results.AddRange(response);
        }

        return results;
    }

    public async Task<Restaurant?> GetRestaurantAsync(string id, string? city = null)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(city))
            {
                var response = await _restaurantsContainer.ReadItemAsync<Restaurant>(id, new PartitionKey(city));
                return response.Resource;
            }

            // Cross-partition query when city is not provided
            var query = new QueryDefinition("SELECT * FROM c WHERE c.id = @id")
                .WithParameter("@id", id);

            using var iterator = _restaurantsContainer.GetItemQueryIterator<Restaurant>(query);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                var restaurant = response.FirstOrDefault();
                if (restaurant != null) return restaurant;
            }

            return null;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    // F-MENU-2: Update a restaurant
    public async Task<Restaurant> UpdateRestaurantAsync(Restaurant restaurant)
    {
        var response = await _restaurantsContainer.ReplaceItemAsync(
            restaurant,
            restaurant.Id,
            new PartitionKey(restaurant.City));
        return response.Resource;
    }

    public async Task<Menu?> GetMenuAsync(string restaurantId)
    {
        try
        {
            var query = new QueryDefinition("SELECT * FROM c WHERE c.restaurantId = @restaurantId")
                .WithParameter("@restaurantId", restaurantId);

            var queryOptions = new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(restaurantId)
            };

            using var iterator = _menusContainer.GetItemQueryIterator<Menu>(query, requestOptions: queryOptions);
            while (iterator.HasMoreResults)
            {
                var response = await iterator.ReadNextAsync();
                var menu = response.FirstOrDefault();
                if (menu != null) return menu;
            }

            return null;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<Restaurant> CreateRestaurantAsync(Restaurant restaurant)
    {
        var response = await _restaurantsContainer.CreateItemAsync(restaurant, new PartitionKey(restaurant.City));
        return response.Resource;
    }

    public async Task<Menu> CreateMenuAsync(Menu menu)
    {
        menu.LastUpdated = DateTime.UtcNow;
        var response = await _menusContainer.CreateItemAsync(menu, new PartitionKey(menu.RestaurantId));
        return response.Resource;
    }

    public async Task<bool> CheckConnectivityAsync()
    {
        try
        {
            await _database.ReadAsync();
            return true;
        }
        catch
        {
            return false;
        }
    }

    public async Task SeedDataAsync()
    {
        // Ensure database and containers exist
        var dbResponse = await _database.Client.CreateDatabaseIfNotExistsAsync(_database.Id);
        var db = dbResponse.Database;

        await db.CreateContainerIfNotExistsAsync("restaurants", "/city");
        await db.CreateContainerIfNotExistsAsync("menus", "/restaurantId");

        // Re-acquire container references after ensuring they exist
        var restaurantsContainer = db.GetContainer("restaurants");
        var menusContainer = db.GetContainer("menus");

        // Check if restaurants container already has data
        var checkQuery = new QueryDefinition("SELECT VALUE COUNT(1) FROM c");
        using var countIterator = restaurantsContainer.GetItemQueryIterator<int>(checkQuery);
        var countResponse = await countIterator.ReadNextAsync();
        if (countResponse.FirstOrDefault() > 0)
        {
            return; // Data already seeded
        }

        // Seed restaurants
        var restaurants = GetSeedRestaurants();
        foreach (var restaurant in restaurants)
        {
            await restaurantsContainer.CreateItemAsync(restaurant, new PartitionKey(restaurant.City));
        }

        // Seed menus
        var menus = GetSeedMenus(restaurants);
        foreach (var menu in menus)
        {
            await menusContainer.CreateItemAsync(menu, new PartitionKey(menu.RestaurantId));
        }
    }

    private static List<Restaurant> GetSeedRestaurants()
    {
        return new List<Restaurant>
        {
            new()
            {
                Id = "restaurant-1",
                Name = "Contoso Burger Palace",
                City = "Seattle",
                Cuisine = "American",
                Rating = 4.5,
                Address = "123 Pike Street, Seattle, WA 98101",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-2",
                Name = "Fabrikam Sushi Bar",
                City = "Seattle",
                Cuisine = "Japanese",
                Rating = 4.7,
                Address = "456 Pine Street, Seattle, WA 98101",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-3",
                Name = "Northwind Pizza Co",
                City = "Portland",
                Cuisine = "Italian",
                Rating = 4.3,
                Address = "789 Burnside Street, Portland, OR 97209",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-4",
                Name = "Adventure Works Taco Shop",
                City = "San Francisco",
                Cuisine = "Mexican",
                Rating = 4.6,
                Address = "321 Mission Street, San Francisco, CA 94105",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-5",
                Name = "Woodgrove Thai Kitchen",
                City = "Seattle",
                Cuisine = "Thai",
                Rating = 4.4,
                Address = "555 Westlake Ave, Seattle, WA 98109",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-6",
                Name = "Tailspin Curry House",
                City = "Portland",
                Cuisine = "Indian",
                Rating = 4.8,
                Address = "234 Alberta Street, Portland, OR 97211",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-7",
                Name = "Litware Dim Sum",
                City = "San Francisco",
                Cuisine = "Chinese",
                Rating = 4.5,
                Address = "888 Grant Ave, San Francisco, CA 94108",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-8",
                Name = "Relecloud Mediterranean Grill",
                City = "Los Angeles",
                Cuisine = "Mediterranean",
                Rating = 4.6,
                Address = "412 Sunset Blvd, Los Angeles, CA 90028",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-9",
                Name = "Proseware French Bistro",
                City = "New York",
                Cuisine = "French",
                Rating = 4.7,
                Address = "71 Sullivan Street, New York, NY 10012",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-10",
                Name = "Wingtip Korean BBQ",
                City = "Los Angeles",
                Cuisine = "Korean",
                Rating = 4.5,
                Address = "3500 W 6th Street, Los Angeles, CA 90020",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-11",
                Name = "Coho Pho House",
                City = "Seattle",
                Cuisine = "Vietnamese",
                Rating = 4.3,
                Address = "1200 S Jackson Street, Seattle, WA 98144",
                IsOpen = true
            },
            new()
            {
                Id = "restaurant-12",
                Name = "Margie Steak & Grill",
                City = "Denver",
                Cuisine = "American",
                Rating = 4.4,
                Address = "1515 Market Street, Denver, CO 80202",
                IsOpen = true
            }
        };
    }

    private static List<Menu> GetSeedMenus(List<Restaurant> restaurants)
    {
        return new List<Menu>
        {
            new()
            {
                Id = "menu-1",
                RestaurantId = "restaurant-1",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Classic Burger", Price = 12.99m, Category = "Burgers", Description = "Angus beef patty with lettuce, tomato, and special sauce" },
                    new() { Name = "Bacon Cheeseburger", Price = 14.99m, Category = "Burgers", Description = "Angus beef with crispy bacon and cheddar cheese" },
                    new() { Name = "Truffle Fries", Price = 7.99m, Category = "Sides", Description = "Hand-cut fries with truffle oil and parmesan" },
                    new() { Name = "Milkshake", Price = 6.99m, Category = "Drinks", Description = "Hand-spun vanilla, chocolate, or strawberry" },
                    new() { Name = "Impossible Burger", Price = 15.99m, Category = "Burgers", Description = "Plant-based patty with all the fixings" }
                }
            },
            new()
            {
                Id = "menu-2",
                RestaurantId = "restaurant-2",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Salmon Nigiri", Price = 8.99m, Category = "Nigiri", Description = "Fresh Atlantic salmon over seasoned rice" },
                    new() { Name = "Dragon Roll", Price = 16.99m, Category = "Specialty Rolls", Description = "Eel and cucumber topped with avocado and unagi sauce" },
                    new() { Name = "Miso Soup", Price = 4.99m, Category = "Soup", Description = "Traditional miso with tofu and wakame" },
                    new() { Name = "Edamame", Price = 5.99m, Category = "Appetizers", Description = "Steamed soybeans with sea salt" }
                }
            },
            new()
            {
                Id = "menu-3",
                RestaurantId = "restaurant-3",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Margherita Pizza", Price = 13.99m, Category = "Pizza", Description = "San Marzano tomatoes, fresh mozzarella, and basil" },
                    new() { Name = "Pepperoni Pizza", Price = 14.99m, Category = "Pizza", Description = "Classic pepperoni with mozzarella on hand-tossed dough" },
                    new() { Name = "Garlic Knots", Price = 6.99m, Category = "Sides", Description = "Fresh-baked knots with garlic butter and herbs" },
                    new() { Name = "Caesar Salad", Price = 9.99m, Category = "Salads", Description = "Romaine, parmesan, croutons, and house-made dressing" },
                    new() { Name = "Tiramisu", Price = 8.99m, Category = "Desserts", Description = "Classic Italian dessert with espresso-soaked ladyfingers" }
                }
            },
            new()
            {
                Id = "menu-4",
                RestaurantId = "restaurant-4",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Carne Asada Taco", Price = 4.99m, Category = "Tacos", Description = "Grilled steak with onion, cilantro, and salsa verde" },
                    new() { Name = "Al Pastor Taco", Price = 4.49m, Category = "Tacos", Description = "Marinated pork with pineapple and fresh onion" },
                    new() { Name = "Fish Taco", Price = 5.49m, Category = "Tacos", Description = "Beer-battered cod with cabbage slaw and chipotle crema" },
                    new() { Name = "Guacamole & Chips", Price = 8.99m, Category = "Appetizers", Description = "House-made guacamole with fresh tortilla chips" },
                    new() { Name = "Horchata", Price = 3.99m, Category = "Drinks", Description = "Traditional rice drink with cinnamon" }
                }
            },
            new()
            {
                Id = "menu-5",
                RestaurantId = "restaurant-5",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Pad Thai", Price = 14.99m, Category = "Noodles", Description = "Stir-fried rice noodles with shrimp, peanuts, and tamarind sauce" },
                    new() { Name = "Green Curry", Price = 15.99m, Category = "Curries", Description = "Coconut green curry with bamboo shoots and Thai basil" },
                    new() { Name = "Tom Yum Soup", Price = 8.99m, Category = "Soup", Description = "Spicy lemongrass soup with shrimp and mushrooms" },
                    new() { Name = "Mango Sticky Rice", Price = 7.99m, Category = "Desserts", Description = "Sweet coconut rice with fresh mango slices" },
                    new() { Name = "Thai Iced Tea", Price = 4.99m, Category = "Drinks", Description = "Classic sweetened Thai tea with cream" }
                }
            },
            new()
            {
                Id = "menu-6",
                RestaurantId = "restaurant-6",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Butter Chicken", Price = 16.99m, Category = "Curries", Description = "Tender chicken in rich tomato-cream sauce" },
                    new() { Name = "Garlic Naan", Price = 3.99m, Category = "Bread", Description = "Freshly baked flatbread with garlic butter" },
                    new() { Name = "Vegetable Samosa", Price = 5.99m, Category = "Appetizers", Description = "Crispy pastry filled with spiced potatoes and peas" },
                    new() { Name = "Lamb Biryani", Price = 18.99m, Category = "Rice", Description = "Fragrant basmati rice with spiced lamb" },
                    new() { Name = "Mango Lassi", Price = 4.99m, Category = "Drinks", Description = "Creamy yogurt smoothie with fresh mango" },
                    new() { Name = "Gulab Jamun", Price = 6.99m, Category = "Desserts", Description = "Sweet milk dumplings in rose-cardamom syrup" }
                }
            },
            new()
            {
                Id = "menu-7",
                RestaurantId = "restaurant-7",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Dim Sum Platter", Price = 12.99m, Category = "Appetizers", Description = "Assortment of steamed dumplings" },
                    new() { Name = "Kung Pao Chicken", Price = 14.99m, Category = "Mains", Description = "Spicy chicken with peanuts and Sichuan peppers" },
                    new() { Name = "Hot & Sour Soup", Price = 6.99m, Category = "Soup", Description = "Classic tangy soup with tofu and mushrooms" },
                    new() { Name = "Mapo Tofu", Price = 13.99m, Category = "Mains", Description = "Silken tofu in spicy chili-bean sauce" },
                    new() { Name = "Boba Tea", Price = 5.99m, Category = "Drinks", Description = "Classic milk tea with tapioca pearls" }
                }
            },
            new()
            {
                Id = "menu-8",
                RestaurantId = "restaurant-8",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Falafel Wrap", Price = 11.99m, Category = "Wraps", Description = "Crispy falafel with tahini and pickled vegetables" },
                    new() { Name = "Lamb Kebab Plate", Price = 18.99m, Category = "Mains", Description = "Grilled lamb with hummus, rice, and salad" },
                    new() { Name = "Hummus & Pita", Price = 8.99m, Category = "Appetizers", Description = "Creamy hummus with warm pita bread" },
                    new() { Name = "Greek Salad", Price = 9.99m, Category = "Salads", Description = "Tomatoes, olives, feta, and cucumber with oregano dressing" },
                    new() { Name = "Baklava", Price = 6.99m, Category = "Desserts", Description = "Layered phyllo with honey and pistachios" }
                }
            },
            new()
            {
                Id = "menu-9",
                RestaurantId = "restaurant-9",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Croque Monsieur", Price = 12.99m, Category = "Sandwiches", Description = "Ham and gruyère with béchamel on brioche" },
                    new() { Name = "French Onion Soup", Price = 9.99m, Category = "Soup", Description = "Caramelized onion soup with gruyère crouton" },
                    new() { Name = "Coq au Vin", Price = 24.99m, Category = "Mains", Description = "Braised chicken in red wine with mushrooms" },
                    new() { Name = "Crème Brûlée", Price = 8.99m, Category = "Desserts", Description = "Classic vanilla custard with caramelized sugar" },
                    new() { Name = "Ratatouille", Price = 14.99m, Category = "Mains", Description = "Provençal vegetable stew with herbs" }
                }
            },
            new()
            {
                Id = "menu-10",
                RestaurantId = "restaurant-10",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Korean BBQ Combo", Price = 24.99m, Category = "Mains", Description = "Bulgogi, galbi, and pork belly with banchan" },
                    new() { Name = "Bibimbap", Price = 14.99m, Category = "Rice", Description = "Rice bowl with vegetables, egg, and gochujang" },
                    new() { Name = "Kimchi Jjigae", Price = 12.99m, Category = "Soup", Description = "Spicy kimchi stew with pork and tofu" },
                    new() { Name = "Korean Fried Chicken", Price = 15.99m, Category = "Mains", Description = "Double-fried chicken in sweet-spicy glaze" },
                    new() { Name = "Tteokbokki", Price = 9.99m, Category = "Snacks", Description = "Spicy rice cakes in gochujang sauce" }
                }
            },
            new()
            {
                Id = "menu-11",
                RestaurantId = "restaurant-11",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Pho Bo", Price = 14.99m, Category = "Soup", Description = "Beef pho with rice noodles, herbs, and bone broth" },
                    new() { Name = "Banh Mi", Price = 10.99m, Category = "Sandwiches", Description = "Vietnamese baguette with grilled pork and pickled vegetables" },
                    new() { Name = "Spring Rolls", Price = 6.99m, Category = "Appetizers", Description = "Fresh rice paper rolls with shrimp and herbs" },
                    new() { Name = "Bun Bo Hue", Price = 15.99m, Category = "Soup", Description = "Spicy lemongrass beef noodle soup" },
                    new() { Name = "Vietnamese Coffee", Price = 4.99m, Category = "Drinks", Description = "Dark roast with sweetened condensed milk" }
                }
            },
            new()
            {
                Id = "menu-12",
                RestaurantId = "restaurant-12",
                LastUpdated = DateTime.UtcNow,
                Items = new List<Models.MenuItem>
                {
                    new() { Name = "Ribeye Steak", Price = 34.99m, Category = "Steaks", Description = "12oz prime ribeye, charbroiled to order" },
                    new() { Name = "BBQ Baby Back Ribs", Price = 26.99m, Category = "Mains", Description = "Slow-smoked ribs with house BBQ sauce" },
                    new() { Name = "Loaded Baked Potato", Price = 8.99m, Category = "Sides", Description = "Baked potato with sour cream, bacon, and chives" },
                    new() { Name = "Wedge Salad", Price = 9.99m, Category = "Salads", Description = "Iceberg wedge with blue cheese and bacon" },
                    new() { Name = "Chocolate Lava Cake", Price = 10.99m, Category = "Desserts", Description = "Warm chocolate cake with molten center" },
                    new() { Name = "Craft Beer Flight", Price = 12.99m, Category = "Drinks", Description = "Four local craft beer samples" }
                }
            }
        };
    }
}
