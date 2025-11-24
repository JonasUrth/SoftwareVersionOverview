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
}


