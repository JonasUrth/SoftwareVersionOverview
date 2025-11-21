using System.ComponentModel.DataAnnotations;
using BMReleaseManager.Models;

namespace BMReleaseManager.DTOs;

public class CreateSoftwareRequest
{
    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public SoftwareType Type { get; set; }

    [Required]
    public bool RequiresCustomerValidation { get; set; }

    public string? FileLocation { get; set; }

    public ReleaseMethod? ReleaseMethod { get; set; }
}

