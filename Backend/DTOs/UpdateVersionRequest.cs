using System.ComponentModel.DataAnnotations;
using BMReleaseManager.Models;

namespace BMReleaseManager.DTOs;

public class UpdateVersionRequest
{
    [Required]
    public int Id { get; set; }

    [Required]
    public ReleaseStatus ReleaseStatus { get; set; }

    [Required]
    public List<int> CustomerIds { get; set; } = new();

    [Required]
    public List<UpdateNoteDto> Notes { get; set; } = new();
}

public class UpdateNoteDto
{
    public int? Id { get; set; } // null for new notes

    [Required]
    public string Note { get; set; } = string.Empty;

    [Required]
    public List<int> CustomerIds { get; set; } = new();
}


