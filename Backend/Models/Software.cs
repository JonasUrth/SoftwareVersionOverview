using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class Software
{
    public int Id { get; set; }

    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public SoftwareType Type { get; set; }

    public string? FileLocation { get; set; }

    public ReleaseMethod? ReleaseMethod { get; set; }

    // Navigation properties
    public ICollection<VersionHistory> VersionHistories { get; set; } = new List<VersionHistory>();
}


