using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.Models;

public class Country
{
    public int Id { get; set; }

    [Required]
    public string Name { get; set; } = string.Empty;

    public string? FirmwareReleaseNote { get; set; }

    // Navigation properties
    public ICollection<Customer> Customers { get; set; } = new List<Customer>();
}


