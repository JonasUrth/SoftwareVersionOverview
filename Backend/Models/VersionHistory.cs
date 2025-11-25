using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public enum ReleaseStatus
{
    PreRelease,
    Released,
    ProductionReady,
    CustomPerCustomer
}

public class VersionHistory
{
    public int Id { get; set; }

    [Required]
    public string Version { get; set; } = string.Empty;

    [Required]
    public int SoftwareId { get; set; }

    [Required]
    public DateTime ReleaseDate { get; set; }

    [Required]
    public int ReleasedById { get; set; }

    [Required]
    public ReleaseStatus ReleaseStatus { get; set; }

    // Status tracking fields (all nullable)
    // These track who/when each status was set, separate from ReleasedById which tracks creation
    public int? PreReleaseById { get; set; }
    public DateTime? PreReleaseDate { get; set; }
    public int? ReleasedStatusById { get; set; }
    public DateTime? ReleasedStatusDate { get; set; }
    public int? ProductionReadyById { get; set; }
    public DateTime? ProductionReadyDate { get; set; }

    // Navigation properties
    public Software Software { get; set; } = null!;
    public User ReleasedBy { get; set; } = null!;
    public User? PreReleaseBy { get; set; }
    public User? ReleasedStatusBy { get; set; }
    public User? ProductionReadyBy { get; set; }
    public ICollection<HistoryNote> HistoryNotes { get; set; } = new List<HistoryNote>();
    public ICollection<VersionHistoryCustomer> VersionHistoryCustomers { get; set; } = new List<VersionHistoryCustomer>();
}


