using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class VersionHistoryCustomer
{
    public int Id { get; set; }

    [Required]
    public int VersionHistoryId { get; set; }

    [Required]
    public int CustomerId { get; set; }

    // Navigation properties
    public VersionHistory VersionHistory { get; set; } = null!;
    public Customer Customer { get; set; } = null!;
}


