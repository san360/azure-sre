using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using MenuApi.Models;
using MenuApi.Services;

var builder = WebApplication.CreateBuilder(args);

// Application Insights
builder.Services.AddApplicationInsightsTelemetry();

// CORS (F-CORS-1)
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

// Swagger (F-OPENAPI-1)
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "Contoso Meals — Menu API",
        Version = "v1",
        Description = "Restaurant and menu catalog service backed by Cosmos DB"
    });
});

// Cosmos DB
var cosmosConnectionString = Environment.GetEnvironmentVariable("CosmosDb__ConnectionString")
    ?? builder.Configuration.GetValue<string>("CosmosDb:ConnectionString")
    ?? throw new InvalidOperationException("CosmosDb connection string is not configured. Set the CosmosDb__ConnectionString environment variable.");

var databaseName = Environment.GetEnvironmentVariable("CosmosDb__DatabaseName")
    ?? builder.Configuration.GetValue<string>("CosmosDb:DatabaseName")
    ?? "catalogdb";

var cosmosClientOptions = new CosmosClientOptions
{
    SerializerOptions = new CosmosSerializationOptions
    {
        PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
    }
};

var cosmosClient = new CosmosClient(cosmosConnectionString, cosmosClientOptions);
builder.Services.AddSingleton(cosmosClient);
builder.Services.AddSingleton(sp => new CosmosDbService(sp.GetRequiredService<CosmosClient>(), databaseName));

// Health checks
builder.Services.AddHealthChecks()
    .AddCheck("liveness", () => HealthCheckResult.Healthy("Service is alive"), tags: new[] { "liveness" })
    .AddCheck("cosmos-db", new CosmosDbHealthCheck(cosmosClient, databaseName), tags: new[] { "readiness" });

var app = builder.Build();

// Middleware pipeline
app.UseCors();
app.UseSwagger();
app.UseSwaggerUI();

// Seed data on startup
using (var scope = app.Services.CreateScope())
{
    var cosmosDbService = scope.ServiceProvider.GetRequiredService<CosmosDbService>();
    try
    {
        await cosmosDbService.SeedDataAsync();
        app.Logger.LogInformation("Cosmos DB seed data initialized successfully.");
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning(ex, "Failed to seed Cosmos DB data. The service will continue without seed data.");
    }
}

// Health endpoints
app.MapGet("/health", () => Results.Ok(new { status = "Healthy", timestamp = DateTime.UtcNow }))
    .WithName("Liveness")
    .WithTags("Health");

app.MapGet("/ready", async (CosmosDbService cosmosDbService) =>
{
    var isReady = await cosmosDbService.CheckConnectivityAsync();
    if (isReady)
    {
        return Results.Ok(new { status = "Ready", timestamp = DateTime.UtcNow });
    }
    return Results.Json(new { status = "Unavailable", timestamp = DateTime.UtcNow }, statusCode: 503);
})
.WithName("Readiness")
.WithTags("Health");

// Restaurant endpoints
app.MapGet("/restaurants", async (CosmosDbService cosmosDbService, string? city) =>
{
    var restaurants = await cosmosDbService.GetRestaurantsAsync(city);
    return Results.Ok(restaurants);
})
.WithName("GetRestaurants")
.WithTags("Restaurants");

// F-MENU-1: Restaurant search (must be before /restaurants/{id} to avoid route conflict)
app.MapGet("/restaurants/search", async (CosmosDbService cosmosDbService, string? q, string? city) =>
{
    var restaurants = await cosmosDbService.SearchRestaurantsAsync(q, city);
    return Results.Ok(restaurants);
})
.WithName("SearchRestaurants")
.WithTags("Restaurants");

app.MapGet("/restaurants/{id}", async (CosmosDbService cosmosDbService, string id, string? city) =>
{
    var restaurant = await cosmosDbService.GetRestaurantAsync(id, city);
    if (restaurant is null)
    {
        return Results.NotFound(new { error = "Restaurant not found", id });
    }
    return Results.Ok(restaurant);
})
.WithName("GetRestaurant")
.WithTags("Restaurants");

app.MapPost("/restaurants", async (CosmosDbService cosmosDbService, Restaurant restaurant) =>
{
    if (string.IsNullOrWhiteSpace(restaurant.Name) || string.IsNullOrWhiteSpace(restaurant.City))
    {
        return Results.BadRequest(new { error = "Name and City are required fields." });
    }

    if (string.IsNullOrWhiteSpace(restaurant.Id))
    {
        restaurant.Id = Guid.NewGuid().ToString();
    }

    var created = await cosmosDbService.CreateRestaurantAsync(restaurant);
    return Results.Created($"/restaurants/{created.Id}", created);
})
.WithName("CreateRestaurant")
.WithTags("Restaurants");

// F-MENU-2: Update restaurant
app.MapPut("/restaurants/{id}", async (CosmosDbService cosmosDbService, string id, Restaurant updated) =>
{
    if (string.IsNullOrWhiteSpace(updated.City))
    {
        return Results.BadRequest(new { error = "City is required for partition key targeting." });
    }

    var existing = await cosmosDbService.GetRestaurantAsync(id, updated.City);
    if (existing is null)
    {
        return Results.NotFound(new { error = "Restaurant not found", id });
    }

    updated.Id = id;
    var result = await cosmosDbService.UpdateRestaurantAsync(updated);
    return Results.Ok(result);
})
.WithName("UpdateRestaurant")
.WithTags("Restaurants");

// Menu endpoints
app.MapGet("/menus/{restaurantId}", async (CosmosDbService cosmosDbService, string restaurantId) =>
{
    var menu = await cosmosDbService.GetMenuAsync(restaurantId);
    if (menu is null)
    {
        return Results.NotFound(new { error = "Menu not found", restaurantId });
    }
    return Results.Ok(menu);
})
.WithName("GetMenu")
.WithTags("Menus");

app.MapGet("/menus/{restaurantId}/items", async (CosmosDbService cosmosDbService, string restaurantId, string? category) =>
{
    var menu = await cosmosDbService.GetMenuAsync(restaurantId);
    if (menu is null)
    {
        return Results.NotFound(new { error = "Menu not found", restaurantId });
    }

    var items = menu.Items.AsEnumerable();
    if (!string.IsNullOrWhiteSpace(category))
    {
        items = items.Where(i => i.Category.Equals(category, StringComparison.OrdinalIgnoreCase));
    }

    return Results.Ok(items);
})
.WithName("GetMenuItems")
.WithTags("Menus");

app.MapPost("/menus", async (CosmosDbService cosmosDbService, MenuApi.Models.Menu menu) =>
{
    if (string.IsNullOrWhiteSpace(menu.RestaurantId))
    {
        return Results.BadRequest(new { error = "RestaurantId is required." });
    }

    if (string.IsNullOrWhiteSpace(menu.Id))
    {
        menu.Id = Guid.NewGuid().ToString();
    }

    var created = await cosmosDbService.CreateMenuAsync(menu);
    return Results.Created($"/menus/{created.RestaurantId}", created);
})
.WithName("CreateMenu")
.WithTags("Menus");

app.Run();

// Cosmos DB health check implementation
public class CosmosDbHealthCheck : IHealthCheck
{
    private readonly CosmosClient _cosmosClient;
    private readonly string _databaseName;

    public CosmosDbHealthCheck(CosmosClient cosmosClient, string databaseName)
    {
        _cosmosClient = cosmosClient;
        _databaseName = databaseName;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            var database = _cosmosClient.GetDatabase(_databaseName);
            await database.ReadAsync(cancellationToken: cancellationToken);
            return HealthCheckResult.Healthy("Cosmos DB is reachable.");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Cosmos DB is not reachable.", ex);
        }
    }
}
