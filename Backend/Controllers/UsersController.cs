using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public UsersController(ApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll()
    {
        var users = await _context.Users
            .Select(u => new
            {
                u.Id,
                u.Name
                // Don't return password
            })
            .ToListAsync();

        return Ok(users);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<object>> GetById(int id)
    {
        var user = await _context.Users
            .Where(u => u.Id == id)
            .Select(u => new
            {
                u.Id,
                u.Name
                // Don't return password
            })
            .FirstOrDefaultAsync();

        if (user == null)
        {
            return NotFound();
        }

        return user;
    }

    [HttpPost]
    public async Task<ActionResult<User>> Create([FromBody] User user)
    {
        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = user.Id }, new { user.Id, user.Name });
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] User user)
    {
        if (id != user.Id)
        {
            return BadRequest();
        }

        _context.Entry(user).State = EntityState.Modified;

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await _context.Users.AnyAsync(e => e.Id == id))
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
        var user = await _context.Users.FindAsync(id);
        if (user == null)
        {
            return NotFound();
        }

        // Soft delete
        user.IsActive = false;
        await _context.SaveChangesAsync();

        return NoContent();
    }
}


