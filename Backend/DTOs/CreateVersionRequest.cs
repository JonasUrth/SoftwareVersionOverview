using System.ComponentModel.DataAnnotations;
using BMReleaseManager.Models;

namespace BMReleaseManager.DTOs;

public class CreateVersionRequest
{
    [Required]
    public string Version { get; set; } = string.Empty;

    [Required]
    public int SoftwareId { get; set; }

    [Required]
    public DateTime ReleaseDate { get; set; }

    [Required]
    public ReleaseStatus ReleaseStatus { get; set; }

    [Required]
    public List<int> CustomerIds { get; set; } = new();

    [Required]
    public List<NoteDto> Notes { get; set; } = new();

    // Status tracking fields (all optional - auto-populated based on ReleaseStatus)
    public int? PreReleaseBy { get; set; }
    public DateTime? PreReleaseDate { get; set; }
    public int? ReleasedBy { get; set; }
    public DateTime? ReleasedDate { get; set; }
    public int? ProductionReadyBy { get; set; }
    public DateTime? ProductionReadyDate { get; set; }
}

public class NoteDto
{
    [Required]
    public string Note { get; set; } = string.Empty;

    [Required]
    public List<int> CustomerIds { get; set; } = new();
}


