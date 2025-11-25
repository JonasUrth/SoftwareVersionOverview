using BMReleaseManager.Models;

namespace BMReleaseManager.DTOs;

public class VersionDetailResponse
{
    public int Id { get; set; }
    public string Version { get; set; } = string.Empty;
    public int SoftwareId { get; set; }
    public string SoftwareName { get; set; } = string.Empty;
    public DateTime ReleaseDate { get; set; }
    public ReleaseStatus ReleaseStatus { get; set; }
    public string ReleasedByName { get; set; } = string.Empty;
    public List<CustomerDto> Customers { get; set; } = new();
    public List<NoteDetailDto> Notes { get; set; } = new();
}

public class CustomerDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public string CountryName { get; set; } = string.Empty;
    public CustomerReleaseStage ReleaseStage { get; set; }
}

public class NoteDetailDto
{
    public int Id { get; set; }
    public string Note { get; set; } = string.Empty;
    public List<CustomerDto> Customers { get; set; } = new();
}


