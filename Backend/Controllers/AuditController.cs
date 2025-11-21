using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuditController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public AuditController(ApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet("{entityType}/{entityId}")]
    public async Task<ActionResult<IEnumerable<object>>> GetAuditTrail(string entityType, string entityId)
    {
        var auditLogs = await _context.AuditLogs
            .Include(a => a.User)
            .Where(a => a.EntityType == entityType && a.EntityId == entityId)
            .OrderByDescending(a => a.Timestamp)
            .Select(a => new
            {
                a.Id,
                a.Timestamp,
                UserName = a.User != null ? a.User.Name : "System",
                a.EntityType,
                a.EntityId,
                a.Action,
                a.Changes
            })
            .ToListAsync();

        return Ok(auditLogs);
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll([FromQuery] int? limit = 100)
    {
        var auditLogs = await _context.AuditLogs
            .Include(a => a.User)
            .OrderByDescending(a => a.Timestamp)
            .Take(limit ?? 100)
            .Select(a => new
            {
                a.Id,
                a.Timestamp,
                UserName = a.User != null ? a.User.Name : "System",
                a.EntityType,
                a.EntityId,
                a.Action,
                a.Changes
            })
            .ToListAsync();

        return Ok(auditLogs);
    }
}

