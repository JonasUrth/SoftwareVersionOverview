using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;
using BMReleaseManager.DTOs;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CustomersController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public CustomersController(ApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll([FromQuery] bool includeInactive = false)
    {
        var query = _context.Customers.Include(c => c.Country).AsQueryable();

        if (!includeInactive)
        {
            query = query.Where(c => c.IsActive);
        }

        var customers = await query
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.IsActive,
                c.CountryId,
                c.RequiresCustomerValidation,
                Country = new
                {
                    c.Country.Id,
                    c.Country.Name,
                    c.Country.FirmwareReleaseNote
                }
            })
            .ToListAsync();

        return Ok(customers);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<Customer>> GetById(int id)
    {
        var customer = await _context.Customers
            .Include(c => c.Country)
            .FirstOrDefaultAsync(c => c.Id == id);

        if (customer == null)
        {
            return NotFound();
        }

        return customer;
    }

    [HttpPost]
    public async Task<ActionResult> Create([FromBody] CreateCustomerRequest request)
    {
        var customer = new Customer
        {
            Name = request.Name,
            CountryId = request.CountryId,
            IsActive = request.IsActive,
            RequiresCustomerValidation = request.RequiresCustomerValidation
        };

        _context.Customers.Add(customer);
        await _context.SaveChangesAsync();

        // Load the country for the response
        await _context.Entry(customer).Reference(c => c.Country).LoadAsync();

        var response = new
        {
            customer.Id,
            customer.Name,
            customer.IsActive,
            customer.CountryId,
            customer.RequiresCustomerValidation,
            Country = new
            {
                customer.Country.Id,
                customer.Country.Name,
                customer.Country.FirmwareReleaseNote
            }
        };

        return CreatedAtAction(nameof(GetById), new { id = customer.Id }, response);
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] UpdateCustomerRequest request)
    {
        var customer = await _context.Customers.FindAsync(id);
        if (customer == null)
        {
            return NotFound();
        }

        customer.Name = request.Name;
        customer.CountryId = request.CountryId;
        customer.IsActive = request.IsActive;
        customer.RequiresCustomerValidation = request.RequiresCustomerValidation;

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await _context.Customers.AnyAsync(e => e.Id == id))
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
        var customer = await _context.Customers.FindAsync(id);
        if (customer == null)
        {
            return NotFound();
        }

        // Soft delete
        customer.IsActive = false;
        await _context.SaveChangesAsync();

        return NoContent();
    }
}


