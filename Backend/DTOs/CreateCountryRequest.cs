using System.ComponentModel.DataAnnotations;

namespace BMReleaseManager.DTOs;

public class CreateCountryRequest
{
    [Required]
    public string Name { get; set; } = string.Empty;

    public string? FirmwareReleaseNote { get; set; }
}

