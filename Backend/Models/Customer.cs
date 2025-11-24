using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class Customer
{
    public int Id { get; set; }

    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public bool IsActive { get; set; } = true;

    [Required]
    public int CountryId { get; set; }

    [Required]
    public bool RequiresCustomerValidation { get; set; } = false;

    // Navigation properties
    public Country Country { get; set; } = null!;
    public ICollection<VersionHistoryCustomer> VersionHistoryCustomers { get; set; } = new List<VersionHistoryCustomer>();
    public ICollection<HistoryNoteCustomer> HistoryNoteCustomers { get; set; } = new List<HistoryNoteCustomer>();
}


