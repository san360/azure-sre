using Microsoft.EntityFrameworkCore;
using PaymentService.Data;
using PaymentService.Models;

var builder = WebApplication.CreateBuilder(args);

// --- Fault injection state (in-memory, toggleable at runtime) ---
var faultEnabled = false;
var faultRate = 0; // percentage 0-100

// --- Services ---
var connectionString = builder.Configuration.GetConnectionString("OrdersDb")
    ?? Environment.GetEnvironmentVariable("ConnectionStrings__OrdersDb")
    ?? "Host=localhost;Database=orders;Username=postgres;Password=postgres";

builder.Services.AddDbContext<PaymentsDbContext>(options =>
    options.UseNpgsql(connectionString));

builder.Services.AddApplicationInsightsTelemetry();

builder.Services.AddHealthChecks()
    .AddNpgSql(connectionString, name: "postgres", tags: ["ready"]);

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
        Title = "Contoso Meals \u2014 Payment Service",
        Version = "v1",
        Description = "Payment processing service with fault injection for SRE demos"
    });
});

var app = builder.Build();

// Middleware pipeline
app.UseCors();
app.UseSwagger();
app.UseSwaggerUI();

// --- Auto-create schema on startup ---
// NOTE: EnsureCreated() is a no-op if the database already exists (e.g. order-api
// created it first). We must explicitly create the Payments table if missing.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<PaymentsDbContext>();
    db.Database.EnsureCreated();

    // EnsureCreated won't add tables to an existing DB created by another DbContext.
    // Fall back to raw SQL to guarantee the Payments table exists.
    try
    {
        await db.Database.ExecuteSqlRawAsync(@"
            CREATE TABLE IF NOT EXISTS ""Payments"" (
                ""Id""              uuid            NOT NULL PRIMARY KEY,
                ""OrderId""         uuid            NOT NULL,
                ""Amount""          decimal(18,2)   NOT NULL,
                ""Status""          varchar(50)     NOT NULL DEFAULT 'pending',
                ""PaymentMethod""   varchar(100)    NOT NULL DEFAULT '',
                ""FailureReason""   varchar(500)    NULL,
                ""ProcessedAt""     timestamp       NOT NULL
            );
            CREATE INDEX IF NOT EXISTS ""IX_Payments_OrderId"" ON ""Payments"" (""OrderId"");
        ");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Schema bootstrap warning: {ex.Message}");
    }
}

// --- Health check endpoints ---
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
    .WithTags("Health");

app.MapGet("/ready", async (PaymentsDbContext db) =>
{
    try
    {
        await db.Database.CanConnectAsync();
        return Results.Ok(new { status = "ready" });
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "unhealthy", reason = ex.Message },
            statusCode: 503);
    }
}).WithTags("Health");

// --- Payment endpoints ---
app.MapPost("/pay", async (PaymentRequest request, PaymentsDbContext db) =>
{
    var payment = new Payment
    {
        Id = Guid.NewGuid(),
        OrderId = request.OrderId,
        Amount = request.Amount,
        PaymentMethod = request.PaymentMethod,
        ProcessedAt = DateTime.UtcNow
    };

    // Fault injection: randomly fail at the configured rate
    if (faultEnabled && Random.Shared.Next(100) < faultRate)
    {
        payment.Status = "failed";
        payment.FailureReason = "Payment gateway timeout";
        db.Payments.Add(payment);
        await db.SaveChangesAsync();

        return Results.Json(new
        {
            error = "Payment gateway timeout",
            paymentId = payment.Id,
            status = payment.Status
        }, statusCode: 500);
    }

    payment.Status = "completed";
    db.Payments.Add(payment);
    await db.SaveChangesAsync();

    return Results.Ok(new
    {
        paymentId = payment.Id,
        orderId = payment.OrderId,
        amount = payment.Amount,
        status = payment.Status,
        processedAt = payment.ProcessedAt
    });
}).WithTags("Payments");

app.MapGet("/payments/{orderId:guid}", async (Guid orderId, PaymentsDbContext db) =>
{
    var payments = await db.Payments
        .Where(p => p.OrderId == orderId)
        .OrderByDescending(p => p.ProcessedAt)
        .ToListAsync();

    if (payments.Count == 0)
        return Results.NotFound(new { error = "No payments found for this order" });

    return Results.Ok(payments);
}).WithTags("Payments");

// F-PAY-1: Refund a completed payment
app.MapPost("/pay/{paymentId:guid}/refund", async (Guid paymentId, PaymentsDbContext db) =>
{
    var payment = await db.Payments.FindAsync(paymentId);
    if (payment is null)
        return Results.NotFound(new { error = "Payment not found", paymentId });

    if (payment.Status != "completed")
        return Results.Json(
            new { error = "Payment is not in 'completed' status", currentStatus = payment.Status },
            statusCode: 409);

    // Mark original payment as refunded
    payment.Status = "refunded";
    payment.FailureReason = "Refund processed";

    // Create audit record for the refund
    var refundRecord = new Payment
    {
        Id = Guid.NewGuid(),
        OrderId = payment.OrderId,
        Amount = -payment.Amount,
        Status = "refunded",
        PaymentMethod = payment.PaymentMethod,
        FailureReason = $"Refund for payment {paymentId}",
        ProcessedAt = DateTime.UtcNow
    };

    db.Payments.Add(refundRecord);
    await db.SaveChangesAsync();

    return Results.Ok(new
    {
        paymentId = payment.Id,
        refundId = refundRecord.Id,
        orderId = payment.OrderId,
        amount = payment.Amount,
        status = "refunded",
        processedAt = refundRecord.ProcessedAt
    });
}).WithTags("Payments");

// --- Fault injection endpoints ---
app.MapPost("/fault/enable", (FaultConfig config) =>
{
    faultEnabled = true;
    faultRate = Math.Clamp(config.Rate, 0, 100);
    return Results.Ok(new { enabled = true, rate = faultRate });
}).WithTags("Fault Injection");

app.MapPost("/fault/disable", () =>
{
    faultEnabled = false;
    faultRate = 0;
    return Results.Ok(new { enabled = false, rate = 0 });
}).WithTags("Fault Injection");

app.MapGet("/fault/status", () =>
{
    return Results.Ok(new { enabled = faultEnabled, rate = faultRate });
}).WithTags("Fault Injection");

app.Run();

// --- Request DTOs ---
public record PaymentRequest(Guid OrderId, decimal Amount, string PaymentMethod);
public record FaultConfig(int Rate);
