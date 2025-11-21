using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;
using BMReleaseManager.DTOs;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CountriesController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public CountriesController(ApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll()
    {
        var countries = await _context.Countries
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.FirmwareReleaseNote
            })
            .ToListAsync();

        return Ok(countries);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult> GetById(int id)
    {
        var country = await _context.Countries
            .Where(c => c.Id == id)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.FirmwareReleaseNote
            })
            .FirstOrDefaultAsync();

        if (country == null)
        {
            return NotFound();
        }

        return Ok(country);
    }

    [HttpPost]
    public async Task<ActionResult> Create([FromBody] CreateCountryRequest request)
    {
        var country = new Country
        {
            Name = request.Name,
            FirmwareReleaseNote = request.FirmwareReleaseNote
        };

        _context.Countries.Add(country);
        await _context.SaveChangesAsync();

        var response = new
        {
            country.Id,
            country.Name,
            country.FirmwareReleaseNote
        };

        return CreatedAtAction(nameof(GetById), new { id = country.Id }, response);
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] CreateCountryRequest request)
    {
        var country = await _context.Countries.FindAsync(id);
        if (country == null)
        {
            return NotFound();
        }

        country.Name = request.Name;
        country.FirmwareReleaseNote = request.FirmwareReleaseNote;

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await _context.Countries.AnyAsync(e => e.Id == id))
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
        var country = await _context.Countries.FindAsync(id);
        if (country == null)
        {
            return NotFound();
        }

        _context.Countries.Remove(country);
        await _context.SaveChangesAsync();

        return NoContent();
    }
}


