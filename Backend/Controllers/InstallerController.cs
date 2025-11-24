using System.Diagnostics;
using BMReleaseManager.Data;
using BMReleaseManager.DTOs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class InstallerController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<InstallerController> _logger;

    public InstallerController(ApplicationDbContext context, IConfiguration configuration, ILogger<InstallerController> logger)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("open")]
    public async Task<IActionResult> Open([FromBody] LaunchInstallerRequest request)
    {
        if (request.SoftwareId <= 0 || request.CustomerId <= 0 || string.IsNullOrWhiteSpace(request.Version))
        {
            return BadRequest(new { message = "softwareId, customerId, and version are required." });
        }

        var software = await _context.Softwares.AsNoTracking().FirstOrDefaultAsync(s => s.Id == request.SoftwareId);
        if (software == null)
        {
            return NotFound(new { message = "Software not found." });
        }

        var customer = await _context.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == request.CustomerId);
        if (customer == null)
        {
            return NotFound(new { message = "Customer not found." });
        }

        var executablePath = _configuration["InstallerSettings:ExecutablePath"];
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return StatusCode(500, new { message = "Installer executable path is not configured." });
        }

        if (!System.IO.File.Exists(executablePath))
        {
            return StatusCode(500, new { message = $"Installer executable not found at '{executablePath}'." });
        }

        var argumentsTemplate = _configuration["InstallerSettings:ArgumentsTemplate"];
        var workingDirectory = _configuration["InstallerSettings:WorkingDirectory"];
        var arguments = FormatArguments(argumentsTemplate, software.Name, customer.Name, request.Version);

        try
        {
            var startInfo = new ProcessStartInfo(executablePath)
            {
                UseShellExecute = true
            };

            if (!string.IsNullOrWhiteSpace(arguments))
            {
                startInfo.Arguments = arguments;
            }

            if (!string.IsNullOrWhiteSpace(workingDirectory))
            {
                startInfo.WorkingDirectory = workingDirectory;
            }

            Process.Start(startInfo);

            return Ok(new
            {
                launched = true,
                path = executablePath,
                arguments
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to launch installer for software {SoftwareId} and customer {CustomerId}", request.SoftwareId, request.CustomerId);
            return StatusCode(500, new { message = "Failed to launch installer application." });
        }
    }

    private static string FormatArguments(string? template, string softwareName, string customerName, string version)
    {
        var safeTemplate =
            string.IsNullOrWhiteSpace(template)
                ? "\"{softwareName}\" \"{customerName}\" \"{version}\""
                : template;

        return safeTemplate
            .Replace("{softwareName}", EscapeArgument(softwareName))
            .Replace("{customerName}", EscapeArgument(customerName))
            .Replace("{version}", EscapeArgument(version));
    }

    private static string EscapeArgument(string value)
    {
        return value.Replace("\"", "\\\"");
    }
}

