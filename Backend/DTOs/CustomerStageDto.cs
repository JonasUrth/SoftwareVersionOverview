using System.ComponentModel.DataAnnotations;
using BMReleaseManager.Models;

namespace BMReleaseManager.DTOs;

public class CustomerStageDto
{
    [Required]
    public int CustomerId { get; set; }

    [Required]
    public CustomerReleaseStage ReleaseStage { get; set; }
}


