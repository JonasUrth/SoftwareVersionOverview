using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.DTOs;

public class CreateCustomerRequest
{
    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public int CountryId { get; set; }

    public bool IsActive { get; set; } = true;
}

