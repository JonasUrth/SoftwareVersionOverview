using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class HistoryNoteCustomer
{
    public int Id { get; set; }

    [Required]
    public int HistoryNoteId { get; set; }

    [Required]
    public int CustomerId { get; set; }

    // Navigation properties
    public HistoryNote HistoryNote { get; set; } = null!;
    public Customer Customer { get; set; } = null!;
}


