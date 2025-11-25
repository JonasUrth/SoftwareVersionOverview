using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public enum CustomerReleaseStage
{
    PreRelease,
    Released,
    ProductionReady
}

public class VersionHistoryCustomer
{
    public int Id { get; set; }

    [Required]
    public int VersionHistoryId { get; set; }

    [Required]
    public int CustomerId { get; set; }

    [Required]
    public CustomerReleaseStage ReleaseStage { get; set; }

    // Navigation properties
    public VersionHistory VersionHistory { get; set; } = null!;
    public Customer Customer { get; set; } = null!;
}


