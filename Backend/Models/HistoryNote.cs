using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class HistoryNote
{
    public int Id { get; set; }

    [Required]
    public string Note { get; set; } = string.Empty;

    [Required]
    public int VersionHistoryId { get; set; }

    // Navigation properties
    public VersionHistory VersionHistory { get; set; } = null!;
    public ICollection<HistoryNoteCustomer> HistoryNoteCustomers { get; set; } = new List<HistoryNoteCustomer>();
}


