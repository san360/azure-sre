using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OrderApi.Data;
using OrderApi.Models;

var builder = WebApplication.CreateBuilder(args);

// --- PostgreSQL via EF Core ---
var connectionString = builder.Configuration.GetConnectionString("OrdersDb")
    ?? Environment.GetEnvironmentVariable("ConnectionStrings__OrdersDb")
    ?? throw new InvalidOperationException("PostgreSQL connection string is not configured.");

builder.Services.AddDbContext<OrdersDbContext>(options =>
    options.UseNpgsql(connectionString));

// --- Application Insights ---
var appInsightsCs = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]
    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING");

if (!string.IsNullOrEmpty(appInsightsCs))
{
    builder.Services.AddApplicationInsightsTelemetry(options =>
    {
        options.ConnectionString = appInsightsCs;
    });
}

// --- Health Checks ---
builder.Services.AddHealthChecks()
    .AddNpgSql(connectionString, name: "postgresql", tags: new[] { "ready" });

// --- CORS (F-CORS-1) ---
var allowedOrigins = Environment.GetEnvironmentVariable("ALLOWED_ORIGINS") ?? "*";
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (allowedOrigins == "*")
            policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
        else
            policy.WithOrigins(allowedOrigins.Split(','))
                  .AllowAnyMethod()
                  .AllowAnyHeader();
    });
});

// --- Swagger (F-OPENAPI-1) ---
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "Contoso Meals — Order API",
        Version = "v1",
        Description = "Order lifecycle management service backed by PostgreSQL"
    });
});

// --- HttpClient for inter-service calls (F-ORCH-1, F-ORDER-2) ---
var paymentServiceBaseUrl = Environment.GetEnvironmentVariable("PaymentService__BaseUrl");
if (!string.IsNullOrEmpty(paymentServiceBaseUrl))
{
    builder.Services.AddHttpClient("payment-service", client =>
    {
        client.BaseAddress = new Uri(paymentServiceBaseUrl);
        client.Timeout = TimeSpan.FromSeconds(5);
    });
}

var menuApiBaseUrl = Environment.GetEnvironmentVariable("MenuApi__BaseUrl");
if (!string.IsNullOrEmpty(menuApiBaseUrl))
{
    builder.Services.AddHttpClient("menu-api", client =>
    {
        client.BaseAddress = new Uri(menuApiBaseUrl);
        client.Timeout = TimeSpan.FromSeconds(5);
    });
}

var app = builder.Build();

// --- Middleware pipeline ---
app.UseCors();
app.UseSwagger();
app.UseSwaggerUI();

// --- Auto-create schema and seed on startup ---
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<OrdersDbContext>();
    db.Database.EnsureCreated();

    if (!db.Customers.Any())
    {
        var seedCustomers = new[]
        {
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000001"), Name = "Default Customer", Email = "default@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000002"), Name = "Alice Johnson", Email = "alice.johnson@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000003"), Name = "Bob Martinez", Email = "bob.martinez@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000004"), Name = "Carlos Garcia", Email = "carlos.garcia@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000005"), Name = "Diana Williams", Email = "diana.williams@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000006"), Name = "Emma Davis", Email = "emma.davis@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000007"), Name = "Frank Brown", Email = "frank.brown@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000008"), Name = "Grace Lee", Email = "grace.lee@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000009"), Name = "Hiro Tanaka", Email = "hiro.tanaka@contosomeals.com", CreatedAt = DateTime.UtcNow },
            new Customer { Id = Guid.Parse("00000000-0000-0000-0000-000000000010"), Name = "Isla Rodriguez", Email = "isla.rodriguez@contosomeals.com", CreatedAt = DateTime.UtcNow }
        };
        db.Customers.AddRange(seedCustomers);
        db.SaveChanges();
    }

    if (!db.Orders.Any())
    {
        var seedOrders = new[]
        {
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000001"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000002"), RestaurantId = "restaurant-1", Status = "confirmed", TotalAmount = 27.97m, Items = "[{\"name\":\"Classic Burger\",\"price\":12.99},{\"name\":\"Truffle Fries\",\"price\":7.99},{\"name\":\"Milkshake\",\"price\":6.99}]", CreatedAt = DateTime.UtcNow.AddHours(-48), UpdatedAt = DateTime.UtcNow.AddHours(-48) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000002"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000003"), RestaurantId = "restaurant-2", Status = "confirmed", TotalAmount = 21.98m, Items = "[{\"name\":\"Dragon Roll\",\"price\":16.99},{\"name\":\"Miso Soup\",\"price\":4.99}]", CreatedAt = DateTime.UtcNow.AddHours(-36), UpdatedAt = DateTime.UtcNow.AddHours(-36) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000003"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000004"), RestaurantId = "restaurant-3", Status = "confirmed", TotalAmount = 23.98m, Items = "[{\"name\":\"Margherita Pizza\",\"price\":13.99},{\"name\":\"Caesar Salad\",\"price\":9.99}]", CreatedAt = DateTime.UtcNow.AddHours(-24), UpdatedAt = DateTime.UtcNow.AddHours(-24) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000004"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000005"), RestaurantId = "restaurant-4", Status = "pending", TotalAmount = 18.47m, Items = "[{\"name\":\"Carne Asada Taco\",\"price\":4.99},{\"name\":\"Al Pastor Taco\",\"price\":4.49},{\"name\":\"Guacamole & Chips\",\"price\":8.99}]", CreatedAt = DateTime.UtcNow.AddHours(-12), UpdatedAt = DateTime.UtcNow.AddHours(-12) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000005"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000006"), RestaurantId = "restaurant-5", Status = "confirmed", TotalAmount = 19.98m, Items = "[{\"name\":\"Pad Thai\",\"price\":14.99},{\"name\":\"Thai Iced Tea\",\"price\":4.99}]", CreatedAt = DateTime.UtcNow.AddHours(-8), UpdatedAt = DateTime.UtcNow.AddHours(-8) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000006"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000007"), RestaurantId = "restaurant-6", Status = "confirmed", TotalAmount = 20.98m, Items = "[{\"name\":\"Butter Chicken\",\"price\":16.99},{\"name\":\"Naan Bread\",\"price\":3.99}]", CreatedAt = DateTime.UtcNow.AddHours(-6), UpdatedAt = DateTime.UtcNow.AddHours(-6) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000007"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000008"), RestaurantId = "restaurant-9", Status = "payment_failed", TotalAmount = 33.98m, Items = "[{\"name\":\"Coq au Vin\",\"price\":24.99},{\"name\":\"French Onion Soup\",\"price\":8.99}]", CreatedAt = DateTime.UtcNow.AddHours(-4), UpdatedAt = DateTime.UtcNow.AddHours(-4) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000008"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000009"), RestaurantId = "restaurant-10", Status = "confirmed", TotalAmount = 14.99m, Items = "[{\"name\":\"Bibimbap\",\"price\":14.99}]", CreatedAt = DateTime.UtcNow.AddHours(-3), UpdatedAt = DateTime.UtcNow.AddHours(-3) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000009"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000010"), RestaurantId = "restaurant-8", Status = "pending", TotalAmount = 20.98m, Items = "[{\"name\":\"Falafel Wrap\",\"price\":11.99},{\"name\":\"Hummus & Pita\",\"price\":8.99}]", CreatedAt = DateTime.UtcNow.AddHours(-1), UpdatedAt = DateTime.UtcNow.AddHours(-1) },
            new Order { Id = Guid.Parse("10000000-0000-0000-0000-000000000010"), CustomerId = Guid.Parse("00000000-0000-0000-0000-000000000002"), RestaurantId = "restaurant-12", Status = "confirmed", TotalAmount = 44.98m, Items = "[{\"name\":\"Ribeye Steak\",\"price\":34.99},{\"name\":\"Wedge Salad\",\"price\":9.99}]", CreatedAt = DateTime.UtcNow.AddMinutes(-30), UpdatedAt = DateTime.UtcNow.AddMinutes(-30) }
        };
        db.Orders.AddRange(seedOrders);
        db.SaveChanges();
    }
}

// --- Health / Readiness endpoints ---
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
    .WithTags("Health");

app.MapGet("/ready", async (OrdersDbContext db) =>
{
    try
    {
        await db.Database.CanConnectAsync();
        return Results.Ok(new { status = "ready" });
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "unhealthy", error = ex.Message },
            statusCode: 503);
    }
})
.WithTags("Health");

// --- GET /orders — list orders with optional filtering (F-ORDER-1) ---
app.MapGet("/orders", async (OrdersDbContext db, Guid? customerId, string? status) =>
{
    IQueryable<Order> query = db.Orders;

    if (customerId.HasValue)
        query = query.Where(o => o.CustomerId == customerId.Value);

    if (!string.IsNullOrWhiteSpace(status))
        query = query.Where(o => o.Status == status);

    var orders = await query
        .OrderByDescending(o => o.CreatedAt)
        .Take(50)
        .ToListAsync();

    return Results.Ok(orders);
})
.WithTags("Orders");

// --- GET /orders/{id} — get order by ID ---
app.MapGet("/orders/{id:guid}", async (Guid id, OrdersDbContext db) =>
{
    var order = await db.Orders.FindAsync(id);
    return order is not null
        ? Results.Ok(order)
        : Results.NotFound(new { error = "Order not found" });
})
.WithTags("Orders");

// --- GET /orders/{id}/details — enriched order with restaurant name + payment status (F-ORDER-2) ---
app.MapGet("/orders/{id:guid}/details", async (Guid id, OrdersDbContext db, [FromServices] IHttpClientFactory? httpClientFactory) =>
{
    var order = await db.Orders.FindAsync(id);
    if (order is null)
        return Results.NotFound(new { error = "Order not found" });

    var customer = await db.Customers.FindAsync(order.CustomerId);

    // Resolve restaurant name from menu-api
    string? restaurantName = null;
    if (httpClientFactory is not null)
    {
        try
        {
            var menuClient = httpClientFactory.CreateClient("menu-api");
            if (menuClient.BaseAddress is not null)
            {
                var restaurantResponse = await menuClient.GetAsync($"/restaurants/{order.RestaurantId}");
                if (restaurantResponse.IsSuccessStatusCode)
                {
                    var restaurantData = await restaurantResponse.Content.ReadFromJsonAsync<JsonElement>();
                    restaurantName = restaurantData.GetProperty("name").GetString();
                }
            }
        }
        catch { /* menu-api unavailable — degrade gracefully */ }
    }

    // Resolve payment status from payment-service
    string? paymentStatus = null;
    if (httpClientFactory is not null)
    {
        try
        {
            var paymentClient = httpClientFactory.CreateClient("payment-service");
            if (paymentClient.BaseAddress is not null)
            {
                var paymentResponse = await paymentClient.GetAsync($"/payments/{order.Id}");
                if (paymentResponse.IsSuccessStatusCode)
                {
                    var paymentsData = await paymentResponse.Content.ReadFromJsonAsync<JsonElement>();
                    if (paymentsData.ValueKind == JsonValueKind.Array && paymentsData.GetArrayLength() > 0)
                    {
                        paymentStatus = paymentsData[0].GetProperty("status").GetString();
                    }
                }
            }
        }
        catch { /* payment-service unavailable — degrade gracefully */ }
    }

    // Parse items from JSON string
    object? parsedItems = null;
    try { parsedItems = JsonSerializer.Deserialize<JsonElement>(order.Items); }
    catch { parsedItems = order.Items; }

    return Results.Ok(new
    {
        order.Id,
        order.CustomerId,
        customerName = customer?.Name,
        order.RestaurantId,
        restaurantName,
        order.Status,
        order.TotalAmount,
        items = parsedItems,
        paymentStatus,
        order.CreatedAt,
        order.UpdatedAt
    });
})
.WithTags("Orders");

// --- POST /orders — create order with optional payment orchestration (F-ORCH-1) ---
app.MapPost("/orders", async (CreateOrderRequest request, OrdersDbContext db, [FromServices] IHttpClientFactory? httpClientFactory) =>
{
    var order = new Order
    {
        Id = Guid.NewGuid(),
        CustomerId = request.CustomerId,
        RestaurantId = request.RestaurantId,
        Items = JsonSerializer.Serialize(request.Items),
        TotalAmount = request.TotalAmount,
        Status = "pending",
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };

    db.Orders.Add(order);
    await db.SaveChangesAsync();

    // F-ORCH-1: If payment-service is configured, orchestrate payment
    object? paymentResult = null;
    if (httpClientFactory is not null && !string.IsNullOrEmpty(request.PaymentMethod))
    {
        try
        {
            var paymentClient = httpClientFactory.CreateClient("payment-service");
            if (paymentClient.BaseAddress is not null)
            {
                var paymentPayload = new
                {
                    orderId = order.Id,
                    amount = order.TotalAmount,
                    paymentMethod = request.PaymentMethod
                };

                var paymentResponse = await paymentClient.PostAsJsonAsync("/pay", paymentPayload);
                var paymentData = await paymentResponse.Content.ReadFromJsonAsync<JsonElement>();

                if (paymentResponse.IsSuccessStatusCode)
                {
                    order.Status = "confirmed";
                    paymentResult = new
                    {
                        paymentId = paymentData.GetProperty("paymentId").GetGuid(),
                        status = "completed"
                    };
                }
                else
                {
                    order.Status = "payment_failed";
                    var errorMsg = paymentData.TryGetProperty("error", out var errProp)
                        ? errProp.GetString()
                        : "Payment failed";
                    paymentResult = new
                    {
                        paymentId = paymentData.TryGetProperty("paymentId", out var pidProp) ? pidProp.GetGuid() : (Guid?)null,
                        status = "failed",
                        error = errorMsg
                    };
                }

                order.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync();
            }
        }
        catch (Exception ex)
        {
            order.Status = "payment_failed";
            order.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
            paymentResult = new { status = "failed", error = $"Payment service unavailable: {ex.Message}" };
        }
    }

    if (paymentResult is not null)
    {
        return Results.Created($"/orders/{order.Id}", new { order, payment = paymentResult });
    }

    return Results.Created($"/orders/{order.Id}", order);
})
.WithTags("Orders");

// --- PUT /orders/{id}/status — update order status ---
app.MapPut("/orders/{id:guid}/status", async (Guid id, UpdateStatusRequest request, OrdersDbContext db) =>
{
    var order = await db.Orders.FindAsync(id);
    if (order is null)
        return Results.NotFound(new { error = "Order not found" });

    order.Status = request.Status;
    order.UpdatedAt = DateTime.UtcNow;
    await db.SaveChangesAsync();

    return Results.Ok(order);
})
.WithTags("Orders");

// --- DELETE /orders/{id} — cancel a pending order (F-ORDER-4) ---
app.MapDelete("/orders/{id:guid}", async (Guid id, OrdersDbContext db) =>
{
    var order = await db.Orders.FindAsync(id);
    if (order is null)
        return Results.NotFound(new { error = "Order not found" });

    if (order.Status != "pending" && order.Status != "payment_failed")
    {
        return Results.Json(
            new { error = "Order cannot be cancelled", currentStatus = order.Status },
            statusCode: 409);
    }

    order.Status = "cancelled";
    order.UpdatedAt = DateTime.UtcNow;
    await db.SaveChangesAsync();

    return Results.Ok(new { order.Id, status = order.Status });
})
.WithTags("Orders");

// --- Customer endpoints (F-ORDER-3) ---
app.MapGet("/customers", async (OrdersDbContext db) =>
{
    var customers = await db.Customers
        .OrderByDescending(c => c.CreatedAt)
        .Take(50)
        .ToListAsync();

    return Results.Ok(customers);
})
.WithTags("Customers");

app.MapGet("/customers/{id:guid}", async (Guid id, OrdersDbContext db) =>
{
    var customer = await db.Customers.FindAsync(id);
    return customer is not null
        ? Results.Ok(customer)
        : Results.NotFound(new { error = "Customer not found" });
})
.WithTags("Customers");

app.MapPost("/customers", async (CreateCustomerRequest request, OrdersDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Email))
    {
        return Results.BadRequest(new { error = "Name and Email are required." });
    }

    var existing = await db.Customers.FirstOrDefaultAsync(c => c.Email == request.Email);
    if (existing is not null)
    {
        return Results.Json(
            new { error = "A customer with this email already exists", customerId = existing.Id },
            statusCode: 409);
    }

    var customer = new Customer
    {
        Id = Guid.NewGuid(),
        Name = request.Name,
        Email = request.Email,
        CreatedAt = DateTime.UtcNow
    };

    db.Customers.Add(customer);
    await db.SaveChangesAsync();

    return Results.Created($"/customers/{customer.Id}", customer);
})
.WithTags("Customers");

app.Run();

// --- Request DTOs ---
public record CreateOrderRequest(
    Guid CustomerId,
    string RestaurantId,
    object[] Items,
    decimal TotalAmount,
    string? PaymentMethod = null);

public record UpdateStatusRequest(string Status);

public record CreateCustomerRequest(string Name, string Email);
