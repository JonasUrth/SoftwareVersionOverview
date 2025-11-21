using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class AuditLog
{
    public int Id { get; set; }

    [Required]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    public int? UserId { get; set; }

    [Required]
    public string EntityType { get; set; } = string.Empty;

    [Required]
    public string EntityId { get; set; } = string.Empty;

    [Required]
    public string Action { get; set; } = string.Empty;

    public string? Changes { get; set; }

    // Navigation property
    public User? User { get; set; }
}


