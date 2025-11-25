using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;
using BMReleaseManager.DTOs;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SoftwareController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public SoftwareController(ApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll()
    {
        var software = await _context.Softwares
            .Select(s => new
            {
                s.Id,
                s.Name,
                Type = s.Type.ToString(),
                s.FileLocation,
                ReleaseMethod = s.ReleaseMethod != null ? s.ReleaseMethod.ToString() : null
            })
            .ToListAsync();

        return Ok(software);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<Software>> GetById(int id)
    {
        var software = await _context.Softwares.FindAsync(id);

        if (software == null)
        {
            return NotFound();
        }

        return software;
    }

    [HttpPost]
    public async Task<ActionResult> Create([FromBody] CreateSoftwareRequest request)
    {
        var software = new Software
        {
            Name = request.Name,
            Type = request.Type,
            FileLocation = request.FileLocation,
            ReleaseMethod = request.ReleaseMethod
        };

        _context.Softwares.Add(software);
        await _context.SaveChangesAsync();

        var response = new
        {
            software.Id,
            software.Name,
            Type = software.Type.ToString(),
            software.FileLocation,
            ReleaseMethod = software.ReleaseMethod?.ToString()
        };

        return CreatedAtAction(nameof(GetById), new { id = software.Id }, response);
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] CreateSoftwareRequest request)
    {
        var software = await _context.Softwares.FindAsync(id);
        if (software == null)
        {
            return NotFound();
        }

        software.Name = request.Name;
        software.Type = request.Type;
        software.FileLocation = request.FileLocation;
        software.ReleaseMethod = request.ReleaseMethod;

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await _context.Softwares.AnyAsync(e => e.Id == id))
            {
                return NotFound();
            }
            throw;
        }

        return NoContent();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        var software = await _context.Softwares.FindAsync(id);
        if (software == null)
        {
            return NotFound();
        }

        _context.Softwares.Remove(software);
        await _context.SaveChangesAsync();

        return NoContent();
    }

    [HttpGet("{id}/release-path")]
    public async Task<ActionResult<ReleasePathCheckResponse>> CheckReleasePath(
        int id,
        [FromQuery] string version,
        [FromQuery] List<int> customerIds)
    {
        if (string.IsNullOrWhiteSpace(version))
        {
            return BadRequest(new { message = "version query parameter is required." });
        }

        var software = await _context.Softwares
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == id);

        if (software == null)
        {
            return NotFound(new { message = "Software not found." });
        }

        var customersNeedingValidation = customerIds != null && customerIds.Count > 0
            ? await _context.Customers
                .AsNoTracking()
                .Where(c => customerIds.Contains(c.Id) && c.RequiresCustomerValidation)
                .Select(c => c.Name)
                .ToListAsync()
            : new List<string>();

        var response = BuildReleasePathResponse(software, version.Trim(), customersNeedingValidation);
        return Ok(response);
    }

    private static ReleasePathCheckResponse BuildReleasePathResponse(
        Software software,
        string version,
        IReadOnlyList<string> validationCustomers)
    {
        var response = new ReleasePathCheckResponse();

        var requiresValidation = software.ReleaseMethod is ReleaseMethod.FindFile
            or ReleaseMethod.CreateCD
            or ReleaseMethod.FindFolder;

        if (!requiresValidation)
        {
            response.IsValid = true;
            return response;
        }

        if (validationCustomers != null && validationCustomers.Count > 0)
        {
            response.Warnings.Add(BuildCustomerValidationWarning(validationCustomers));
        }

        if (string.IsNullOrWhiteSpace(software.FileLocation))
        {
            response.Errors.Add("Release location is not configured.");
            return response;
        }

        try
        {
            var resolvedPath = software.FileLocation
                .Replace("{{VERSION}}", version, StringComparison.OrdinalIgnoreCase);

            var normalizedPath = resolvedPath.Replace('/', Path.DirectorySeparatorChar);
            var displayPath = normalizedPath.Replace('\\', '/');
            var requiresFolderValidation = software.ReleaseMethod is ReleaseMethod.CreateCD or ReleaseMethod.FindFolder;

            var (rootValid, rootError) = ValidateRootAccess(Path.GetPathRoot(normalizedPath));
            if (!rootValid)
            {
                response.Errors.Add(rootError ?? "Release drive not accessible.");
                return response;
            }

            var folderPath = requiresFolderValidation
                ? normalizedPath
                : Path.GetDirectoryName(normalizedPath);
            var displayFolderPath = NormalizeForDisplay(folderPath ?? normalizedPath);

            if (string.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath))
            {
                response.Errors.Add($@"Release folder not found ""{displayFolderPath}"".");
                return response;
            }

            if (requiresFolderValidation)
            {
                if (!DirectoryContainsEntries(folderPath))
                {
                    response.Errors.Add($@"Release folder is empty ""{displayFolderPath}"".");
                    return response;
                }

                response.IsValid = true;
                return response;
            }

            if (!System.IO.File.Exists(normalizedPath))
            {
                response.Errors.Add($@"Release file not found ""{displayPath}"".");
                return response;
            }

            response.IsValid = true;
            return response;
        }
        catch (Exception ex)
        {
            response.Errors.Add($"Failed to validate release path: {ex.Message}");
            return response;
        }
    }

    private static (bool Success, string? Error) ValidateRootAccess(string? rootPath)
    {
        if (string.IsNullOrWhiteSpace(rootPath))
        {
            return (false, "Release drive not found.");
        }

        if (rootPath.StartsWith(@"\\"))
        {
            return Directory.Exists(rootPath)
                ? (true, null)
                : (false, $@"Release share not accessible ""{NormalizeForDisplay(rootPath)}"".");
        }

        var normalizedRoot = rootPath.EndsWith(Path.DirectorySeparatorChar.ToString())
            ? rootPath
            : rootPath + Path.DirectorySeparatorChar;

        var drive = DriveInfo.GetDrives()
            .FirstOrDefault(d => string.Equals(d.Name, normalizedRoot, StringComparison.OrdinalIgnoreCase));

        if (drive == null)
        {
            return (false, $@"Release drive not found ""{normalizedRoot}""");
        }

        if (!drive.IsReady)
        {
            return (false, $@"Release drive not accessible ""{normalizedRoot}""");
        }

        return (true, null);
    }

    private static bool DirectoryContainsEntries(string path)
    {
        try
        {
            return Directory.EnumerateFileSystemEntries(path).Any();
        }
        catch
        {
            return false;
        }
    }

    private static string NormalizeForDisplay(string path) =>
        path.Replace('\\', '/');

    private static string BuildCustomerValidationWarning(IReadOnlyList<string> validationCustomers)
    {
        var customerList = string.Join(", ", validationCustomers);
        return $"Customer validation required for: {customerList}. These customers must confirm this release before production.";
    }
}


