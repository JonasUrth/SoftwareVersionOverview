using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;
using BMReleaseManager.DTOs;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VersionsController : BaseController
{
    public VersionsController(ApplicationDbContext context) : base(context)
    {
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetAll()
    {
        var versions = await _context.VersionHistories
            .Include(v => v.Software)
            .Include(v => v.ReleasedBy)
            .Include(v => v.VersionHistoryCustomers)
                .ThenInclude(vhc => vhc.Customer)
            .Select(v => new
            {
                v.Id,
                v.Version,
                v.SoftwareId,
                SoftwareName = v.Software.Name,
                v.ReleaseDate,
                v.ReleaseStatus,
                ReleasedBy = v.ReleasedBy.Name,
                CustomerCount = v.VersionHistoryCustomers.Count
            })
            .OrderByDescending(v => v.ReleaseDate)
            .ToListAsync();

        return Ok(versions);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<VersionDetailResponse>> GetById(int id)
    {
        var detail = await GetVersionDetailById(id);
        if (detail == null)
        {
            return NotFound();
        }

        return Ok(detail);
    }

    [HttpGet("latest")]
    public async Task<ActionResult<VersionDetailResponse>> GetLatest([FromQuery] int softwareId, [FromQuery] int customerId)
    {
        if (softwareId <= 0 || customerId <= 0)
        {
            return BadRequest(new { message = "softwareId and customerId are required." });
        }

        var software = await _context.Softwares
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == softwareId && s.Type == SoftwareType.Windows);

        if (software == null)
        {
            return NotFound(new { message = "Windows software not found." });
        }

        var latestVersionId = await _context.VersionHistoryCustomers
            .Where(vhc =>
                vhc.CustomerId == customerId
                    && vhc.VersionHistory.SoftwareId == softwareId
                    && vhc.ReleaseStage == CustomerReleaseStage.ProductionReady
            )
            .OrderByDescending(vhc => vhc.VersionHistory.ReleaseDate)
            .Select(vhc => vhc.VersionHistoryId)
            .FirstOrDefaultAsync();

        if (latestVersionId == 0)
        {
            return NotFound(new { message = "No production-ready releases found for this software and customer." });
        }

        var detail = await GetVersionDetailById(latestVersionId);
        if (detail == null)
        {
            return NotFound(new { message = "Release details unavailable." });
        }

        return Ok(detail);
    }

    [HttpPost]
    public async Task<ActionResult<VersionDetailResponse>> Create([FromBody] CreateVersionRequest request)
    {
        // Get current user from session or token
        var userId = await GetCurrentUserId();
        if (userId == null)
        {
            return Unauthorized(new { message = "User not authenticated" });
        }

        // Validation 1: Check if version + software combination already exists
        var exists = await _context.VersionHistories
            .AnyAsync(v => v.Version == request.Version && v.SoftwareId == request.SoftwareId);

        if (exists)
        {
            return BadRequest(new { message = "This version already exists for this software. Please edit the existing release." });
        }

        // Validation 2: Must have at least one customer
        if (!request.CustomerIds.Any())
        {
            return BadRequest(new { message = "Cannot create version without at least one customer" });
        }

        // Validation 3: Must have at least one note
        if (!request.Notes.Any())
        {
            return BadRequest(new { message = "Cannot create version without at least one note" });
        }

        // Validation 4: Each note must be assigned to at least one customer
        foreach (var note in request.Notes)
        {
            if (!note.CustomerIds.Any())
            {
                return BadRequest(new { message = "Each note must be assigned to at least one customer" });
            }

            // Validate that note customers are from the selected customers
            if (note.CustomerIds.Any(cid => !request.CustomerIds.Contains(cid)))
            {
                return BadRequest(new { message = "Note can only be assigned to customers selected for this version" });
            }
        }

        var (stageValid, stageError, customerStageLookup) =
            ResolveCustomerStages(request.ReleaseStatus, request.CustomerIds, request.CustomerStages);

        if (!stageValid)
        {
            return BadRequest(new { message = stageError });
        }

        // Create version history
        var releaseDateUtc = DateTime.SpecifyKind(request.ReleaseDate, DateTimeKind.Utc);
        var nowUtc = DateTime.UtcNow;

        // Auto-populate status tracking fields based on ReleaseStatus if not provided
        var versionHistory = new VersionHistory
        {
            Version = request.Version,
            SoftwareId = request.SoftwareId,
            ReleaseDate = releaseDateUtc,
            ReleasedById = userId.Value,
            ReleaseStatus = request.ReleaseStatus,
            PreReleaseById = request.PreReleaseBy ?? (request.ReleaseStatus == ReleaseStatus.PreRelease ? userId.Value : null),
            PreReleaseDate = request.PreReleaseDate ?? (request.ReleaseStatus == ReleaseStatus.PreRelease ? nowUtc : (DateTime?)null),
            ReleasedStatusById = request.ReleasedBy ?? (request.ReleaseStatus == ReleaseStatus.Released ? userId.Value : null),
            ReleasedStatusDate = request.ReleasedDate ?? (request.ReleaseStatus == ReleaseStatus.Released ? nowUtc : (DateTime?)null),
            ProductionReadyById = request.ProductionReadyBy ?? (request.ReleaseStatus == ReleaseStatus.ProductionReady ? userId.Value : null),
            ProductionReadyDate = request.ProductionReadyDate ?? (request.ReleaseStatus == ReleaseStatus.ProductionReady ? nowUtc : (DateTime?)null)
        };

        _context.VersionHistories.Add(versionHistory);
        await _context.SaveChangesAsync();

        // Add customer associations
        foreach (var customerId in request.CustomerIds)
        {
            _context.VersionHistoryCustomers.Add(new VersionHistoryCustomer
            {
                VersionHistoryId = versionHistory.Id,
                CustomerId = customerId,
                ReleaseStage = customerStageLookup[customerId]
            });
        }

        // Add notes with customer associations
        foreach (var noteDto in request.Notes)
        {
            var note = new HistoryNote
            {
                Note = noteDto.Note,
                VersionHistoryId = versionHistory.Id
            };
            _context.HistoryNotes.Add(note);
            await _context.SaveChangesAsync(); // Save to get note ID

            foreach (var customerId in noteDto.CustomerIds)
            {
                _context.HistoryNoteCustomers.Add(new HistoryNoteCustomer
                {
                    HistoryNoteId = note.Id,
                    CustomerId = customerId
                });
            }
        }

        await _context.SaveChangesAsync();

        // Create audit log
        await CreateAuditLog(userId.Value, "VERSION_HISTORY", versionHistory.Id.ToString(), "CREATE", 
            $"Created version {request.Version} for software ID {request.SoftwareId}");

        // Return the created version details
        return CreatedAtAction(nameof(GetById), new { id = versionHistory.Id }, 
            await GetVersionDetailById(versionHistory.Id));
    }

    [HttpPost("confirm")]
    public async Task<ActionResult<VersionDetailResponse>> CreateConfirmed([FromBody] CreateVersionRequest request)
    {
        // This endpoint bypasses the validation warning and creates the version
        // Get current user from session or token
        var userId = await GetCurrentUserId();
        if (userId == null)
        {
            return Unauthorized(new { message = "User not authenticated" });
        }

        // Check if version + software combination already exists
        var exists = await _context.VersionHistories
            .AnyAsync(v => v.Version == request.Version && v.SoftwareId == request.SoftwareId);

        if (exists)
        {
            return BadRequest(new { message = "This version already exists for this software. Please edit the existing release." });
        }

        // Must have at least one customer
        if (!request.CustomerIds.Any())
        {
            return BadRequest(new { message = "Cannot create version without at least one customer" });
        }

        // Must have at least one note
        if (!request.Notes.Any())
        {
            return BadRequest(new { message = "Cannot create version without at least one note" });
        }

        // Each note must be assigned to at least one customer
        foreach (var note in request.Notes)
        {
            if (!note.CustomerIds.Any())
            {
                return BadRequest(new { message = "Each note must be assigned to at least one customer" });
            }

            if (note.CustomerIds.Any(cid => !request.CustomerIds.Contains(cid)))
            {
                return BadRequest(new { message = "Note can only be assigned to customers selected for this version" });
            }
        }

        var (stageValid, stageError, customerStageLookup) =
            ResolveCustomerStages(request.ReleaseStatus, request.CustomerIds, request.CustomerStages);

        if (!stageValid)
        {
            return BadRequest(new { message = stageError });
        }

        // Create version history
        var releaseDateUtc = DateTime.SpecifyKind(request.ReleaseDate, DateTimeKind.Utc);
        var nowUtc = DateTime.UtcNow;

        // Auto-populate status tracking fields based on ReleaseStatus if not provided
        var versionHistory = new VersionHistory
        {
            Version = request.Version,
            SoftwareId = request.SoftwareId,
            ReleaseDate = releaseDateUtc,
            ReleasedById = userId.Value,
            ReleaseStatus = request.ReleaseStatus,
            PreReleaseById = request.PreReleaseBy ?? (request.ReleaseStatus == ReleaseStatus.PreRelease ? userId.Value : null),
            PreReleaseDate = request.PreReleaseDate ?? (request.ReleaseStatus == ReleaseStatus.PreRelease ? nowUtc : (DateTime?)null),
            ReleasedStatusById = request.ReleasedBy ?? (request.ReleaseStatus == ReleaseStatus.Released ? userId.Value : null),
            ReleasedStatusDate = request.ReleasedDate ?? (request.ReleaseStatus == ReleaseStatus.Released ? nowUtc : (DateTime?)null),
            ProductionReadyById = request.ProductionReadyBy ?? (request.ReleaseStatus == ReleaseStatus.ProductionReady ? userId.Value : null),
            ProductionReadyDate = request.ProductionReadyDate ?? (request.ReleaseStatus == ReleaseStatus.ProductionReady ? nowUtc : (DateTime?)null)
        };

        _context.VersionHistories.Add(versionHistory);
        await _context.SaveChangesAsync();

        // Add customer associations
        foreach (var customerId in request.CustomerIds)
        {
            _context.VersionHistoryCustomers.Add(new VersionHistoryCustomer
            {
                VersionHistoryId = versionHistory.Id,
                CustomerId = customerId,
                ReleaseStage = customerStageLookup[customerId]
            });
        }

        // Add notes with customer associations
        foreach (var noteDto in request.Notes)
        {
            var note = new HistoryNote
            {
                Note = noteDto.Note,
                VersionHistoryId = versionHistory.Id
            };
            _context.HistoryNotes.Add(note);
            await _context.SaveChangesAsync();

            foreach (var customerId in noteDto.CustomerIds)
            {
                _context.HistoryNoteCustomers.Add(new HistoryNoteCustomer
                {
                    HistoryNoteId = note.Id,
                    CustomerId = customerId
                });
            }
        }

        await _context.SaveChangesAsync();

        // Create audit log
        await CreateAuditLog(userId.Value, "VERSION_HISTORY", versionHistory.Id.ToString(), "CREATE", 
            $"Created version {request.Version} for software ID {request.SoftwareId}");

        return CreatedAtAction(nameof(GetById), new { id = versionHistory.Id }, 
            await GetVersionDetailById(versionHistory.Id));
    }

    [HttpPut("{id}")]
    public async Task<ActionResult> Update(int id, [FromBody] UpdateVersionRequest request)
    {
        if (id != request.Id)
        {
            return BadRequest();
        }

        var userId = await GetCurrentUserId();
        if (userId == null)
        {
            return Unauthorized(new { message = "User not authenticated" });
        }

        var versionHistory = await _context.VersionHistories
            .Include(v => v.VersionHistoryCustomers)
            .Include(v => v.HistoryNotes)
                .ThenInclude(n => n.HistoryNoteCustomers)
            .FirstOrDefaultAsync(v => v.Id == id);

        if (versionHistory == null)
        {
            return NotFound();
        }

        var (stageValid, stageError, customerStageLookup) =
            ResolveCustomerStages(request.ReleaseStatus, request.CustomerIds, request.CustomerStages);

        if (!stageValid)
        {
            return BadRequest(new { message = stageError });
        }

        // Update release date
        versionHistory.ReleaseDate = DateTime.SpecifyKind(request.ReleaseDate, DateTimeKind.Utc);

        // Update release status
        versionHistory.ReleaseStatus = request.ReleaseStatus;

        foreach (var vhc in versionHistory.VersionHistoryCustomers)
        {
            if (customerStageLookup.TryGetValue(vhc.CustomerId, out var stage))
            {
                vhc.ReleaseStage = stage;
            }
        }

        // Update customers
        var existingCustomerIds = versionHistory.VersionHistoryCustomers.Select(vhc => vhc.CustomerId).ToList();
        var customersToAdd = request.CustomerIds.Except(existingCustomerIds).ToList();
        var customersToRemove = existingCustomerIds.Except(request.CustomerIds).ToList();

        foreach (var customerId in customersToAdd)
        {
            _context.VersionHistoryCustomers.Add(new VersionHistoryCustomer
            {
                VersionHistoryId = id,
                CustomerId = customerId,
                ReleaseStage = customerStageLookup[customerId]
            });
        }

        foreach (var customerId in customersToRemove)
        {
            var vhcToRemove = versionHistory.VersionHistoryCustomers
                .First(vhc => vhc.CustomerId == customerId);
            _context.VersionHistoryCustomers.Remove(vhcToRemove);
        }

        // Update notes
        var existingNoteIds = versionHistory.HistoryNotes.Select(n => n.Id).ToList();
        var requestNoteIds = request.Notes.Where(n => n.Id.HasValue).Select(n => n.Id!.Value).ToList();
        var notesToRemove = existingNoteIds.Except(requestNoteIds).ToList();

        // Remove deleted notes
        foreach (var noteId in notesToRemove)
        {
            var noteToRemove = versionHistory.HistoryNotes.First(n => n.Id == noteId);
            _context.HistoryNotes.Remove(noteToRemove);
        }

        // Update existing notes and add new ones
        foreach (var noteDto in request.Notes)
        {
            if (noteDto.Id.HasValue)
            {
                // Update existing note
                var existingNote = versionHistory.HistoryNotes.FirstOrDefault(n => n.Id == noteDto.Id.Value);
                if (existingNote != null)
                {
                    existingNote.Note = noteDto.Note;

                    // Update note customer associations
                    var existingNoteCustomerIds = existingNote.HistoryNoteCustomers.Select(hnc => hnc.CustomerId).ToList();
                    var noteCustomersToAdd = noteDto.CustomerIds.Except(existingNoteCustomerIds).ToList();
                    var noteCustomersToRemove = existingNoteCustomerIds.Except(noteDto.CustomerIds).ToList();

                    foreach (var customerId in noteCustomersToAdd)
                    {
                        _context.HistoryNoteCustomers.Add(new HistoryNoteCustomer
                        {
                            HistoryNoteId = existingNote.Id,
                            CustomerId = customerId
                        });
                    }

                    foreach (var customerId in noteCustomersToRemove)
                    {
                        var hncToRemove = existingNote.HistoryNoteCustomers
                            .First(hnc => hnc.CustomerId == customerId);
                        _context.HistoryNoteCustomers.Remove(hncToRemove);
                    }
                }
            }
            else
            {
                // Add new note
                var newNote = new HistoryNote
                {
                    Note = noteDto.Note,
                    VersionHistoryId = id
                };
                _context.HistoryNotes.Add(newNote);
                await _context.SaveChangesAsync();

                foreach (var customerId in noteDto.CustomerIds)
                {
                    _context.HistoryNoteCustomers.Add(new HistoryNoteCustomer
                    {
                        HistoryNoteId = newNote.Id,
                        CustomerId = customerId
                    });
                }
            }
        }

        await _context.SaveChangesAsync();

        // Create audit log
        await CreateAuditLog(userId.Value, "VERSION_HISTORY", id.ToString(), "UPDATE", 
            $"Updated version {versionHistory.Version}");

        return NoContent();
    }

    private (bool IsValid, string? Error, Dictionary<int, CustomerReleaseStage> StageMap) ResolveCustomerStages(
        ReleaseStatus releaseStatus,
        List<int> customerIds,
        List<CustomerStageDto>? customerStages)
    {
        var lookup = new Dictionary<int, CustomerReleaseStage>();
        customerStages ??= new List<CustomerStageDto>();

        if (!customerIds.Any())
        {
            return (true, null, lookup);
        }

        if (releaseStatus == ReleaseStatus.CustomPerCustomer)
        {
            foreach (var customerId in customerIds)
            {
                var stage = customerStages.FirstOrDefault(cs => cs.CustomerId == customerId);
                if (stage == null)
                {
                    return (false, $"Missing release stage for customer ID {customerId}.", lookup);
                }

                lookup[customerId] = stage.ReleaseStage;
            }

            if (customerStages.Any(cs => !customerIds.Contains(cs.CustomerId)))
            {
                return (false, "Customer stages contain IDs that are not part of this release.", lookup);
            }
        }
        else
        {
            var defaultStage = MapReleaseStatusToStage(releaseStatus);
            foreach (var customerId in customerIds)
            {
                lookup[customerId] = defaultStage;
            }
        }

        return (true, null, lookup);
    }

    private CustomerReleaseStage MapReleaseStatusToStage(ReleaseStatus releaseStatus)
    {
        return releaseStatus switch
        {
            ReleaseStatus.Released => CustomerReleaseStage.Released,
            ReleaseStatus.ProductionReady => CustomerReleaseStage.ProductionReady,
            ReleaseStatus.Canceled => CustomerReleaseStage.Canceled,
            _ => CustomerReleaseStage.PreRelease
        };
    }

    private async Task<VersionDetailResponse?> GetVersionDetailById(int id)
    {
        var version = await _context.VersionHistories
            .Include(v => v.Software)
            .Include(v => v.ReleasedBy)
            .Include(v => v.VersionHistoryCustomers)
                .ThenInclude(vhc => vhc.Customer)
                    .ThenInclude(c => c.Country)
            .Include(v => v.HistoryNotes)
                .ThenInclude(n => n.HistoryNoteCustomers)
                    .ThenInclude(hnc => hnc.Customer)
                        .ThenInclude(c => c.Country)
            .FirstOrDefaultAsync(v => v.Id == id);

        if (version == null)
        {
            return null;
        }

        var stageLookup = version.VersionHistoryCustomers.ToDictionary(vhc => vhc.CustomerId, vhc => vhc.ReleaseStage);

        return new VersionDetailResponse
        {
            Id = version.Id,
            Version = version.Version,
            SoftwareId = version.SoftwareId,
            SoftwareName = version.Software.Name,
            ReleaseDate = version.ReleaseDate,
            ReleaseStatus = version.ReleaseStatus,
            ReleasedByName = version.ReleasedBy.Name,
            Customers = version.VersionHistoryCustomers
                .Select(vhc => new CustomerDto
                {
                    Id = vhc.Customer.Id,
                    Name = vhc.Customer.Name,
                    IsActive = vhc.Customer.IsActive,
                    CountryName = vhc.Customer.Country.Name,
                    ReleaseStage = vhc.ReleaseStage
                })
                .ToList(),
            Notes = version.HistoryNotes
                .Select(n => new NoteDetailDto
                {
                    Id = n.Id,
                    Note = n.Note,
                    Customers = n.HistoryNoteCustomers
                        .Select(hnc => new CustomerDto
                        {
                            Id = hnc.Customer.Id,
                            Name = hnc.Customer.Name,
                            IsActive = hnc.Customer.IsActive,
                            CountryName = hnc.Customer.Country.Name,
                            ReleaseStage = stageLookup.TryGetValue(hnc.CustomerId, out var stage)
                                ? stage
                                : CustomerReleaseStage.PreRelease
                        })
                        .ToList()
                })
                .ToList()
        };
    }

    private async Task CreateAuditLog(int userId, string entityType, string entityId, string action, string changes)
    {
        var auditLog = new AuditLog
        {
            UserId = userId,
            EntityType = entityType,
            EntityId = entityId,
            Action = action,
            Changes = changes,
            Timestamp = DateTime.UtcNow
        };

        _context.AuditLogs.Add(auditLog);
        await _context.SaveChangesAsync();
    }
}


