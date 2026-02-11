namespace OrderApi.Models;

public class Order
{
    public Guid Id { get; set; }
    public Guid CustomerId { get; set; }
    public string RestaurantId { get; set; } = string.Empty;
    public string Status { get; set; } = "pending";
    public decimal TotalAmount { get; set; }
    public string Items { get; set; } = "[]";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
