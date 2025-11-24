namespace BMReleaseManager.DTOs;

public class LaunchInstallerRequest
{
    public int SoftwareId { get; set; }
    public int CustomerId { get; set; }
    public string Version { get; set; } = string.Empty;
}

