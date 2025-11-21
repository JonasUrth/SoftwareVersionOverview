using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.DTOs;

public class UpdateCustomerRequest
{
    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public int CountryId { get; set; }

    [Required]
    public bool IsActive { get; set; }
}

