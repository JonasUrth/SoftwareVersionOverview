using System.Collections.Generic;

namespace BMReleaseManager.DTOs;

public class ReleasePathCheckResponse
{
    public bool IsValid { get; set; }

    public List<string> Errors { get; set; } = new();

    public List<string> Warnings { get; set; } = new();
}


