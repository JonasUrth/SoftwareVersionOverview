using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class User
{
    public int Id { get; set; }

    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public string Password { get; set; } = string.Empty;

    // Navigation properties
    public ICollection<VersionHistory> VersionHistories { get; set; } = new List<VersionHistory>();
}


