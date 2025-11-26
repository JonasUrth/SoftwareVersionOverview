using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.Models;
using System.Globalization;
using System.Text;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ImportController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly ILogger<ImportController> _logger;
    private readonly string _csvFilePath;
    private readonly string _firmwareCsvFilePath;

    public ImportController(ApplicationDbContext context, ILogger<ImportController> logger, IConfiguration configuration)
    {
        _context = context;
        _logger = logger;
        _csvFilePath = Path.Combine(Directory.GetCurrentDirectory(), "ImportData", "BM FlexCheck Version Log.csv");
        _firmwareCsvFilePath = Path.Combine(Directory.GetCurrentDirectory(), "ImportData", "firmware_releases.csv");
    }

    [HttpPost("csv")]
    public async Task<ActionResult> ImportCsv()
    {
        try
        {
            if (!System.IO.File.Exists(_csvFilePath))
            {
                return BadRequest(new { message = $"CSV file not found at: {_csvFilePath}" });
            }

            _logger.LogInformation("Starting CSV import from: {Path}", _csvFilePath);

            // Step 1: Clear and recreate database
            await ClearAndRecreateDatabase();

            // Step 2: Read and parse CSV
            var rows = await ReadCsvFile(_csvFilePath);

            // Step 3: Create software entries
            var softwareMap = await CreateSoftwareEntries();

            // Step 4: Create users from "By" column
            var userMap = await CreateUsers(rows);

            // Step 5: Create default country and customers from "Released for" column
            var country = await CreateDefaultCountry();
            var customerMap = await CreateCustomers(rows, country.Id);

            // Step 6: Process rows and create/update versions
            var importResult = await ProcessRows(rows, softwareMap, userMap, customerMap);

            _logger.LogInformation("Import completed. Created: {Versions} versions, {Notes} notes", 
                importResult.VersionsCreated, importResult.NotesCreated);

            return Ok(new
            {
                success = true,
                message = "Import completed successfully",
                statistics = new
                {
                    softwareCreated = softwareMap.Count,
                    usersCreated = userMap.Count,
                    customersCreated = customerMap.Count,
                    versionsCreated = importResult.VersionsCreated,
                    versionsUpdated = importResult.VersionsUpdated,
                    notesCreated = importResult.NotesCreated,
                    duplicateNotes = importResult.DuplicateNotes.Count
                },
                duplicateNotes = importResult.DuplicateNotes
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during CSV import");
            return StatusCode(500, new { message = $"Import failed: {ex.Message}", error = ex.ToString() });
        }
    }

    private async Task ClearAndRecreateDatabase()
    {
        _logger.LogInformation("Clearing and recreating database...");

        // Drop all tables
        await _context.Database.EnsureDeletedAsync();

        // Recreate database
        await _context.Database.EnsureCreatedAsync();

        _logger.LogInformation("Database cleared and recreated");
    }

    private async Task<List<CsvRow>> ReadCsvFile(string filePath)
    {
        var rows = new List<CsvRow>();
        var lineNumber = 0;

        // Try to detect encoding - CSV files often use Windows-1252 or ISO-8859-1 for European characters
        var encoding = DetectEncoding(filePath) ?? Encoding.UTF8;
        using var reader = new StreamReader(filePath, encoding);
        
        // Skip header row - read it properly handling quotes
        var headerRow = await ReadCsvRow(reader);
        if (headerRow == null)
        {
            throw new Exception("CSV file is empty");
        }

        lineNumber = 1;
        var rowsRead = 0;

        while (!reader.EndOfStream)
        {
            lineNumber++;
            try
            {
                var row = await ReadCsvRow(reader);
                if (row != null)
                {
                    var parsedRow = ParseCsvRow(row, lineNumber);
                    if (parsedRow != null)
                    {
                        rows.Add(parsedRow);
                        rowsRead++;
                        
                        // Log progress every 1000 valid rows
                        if (rowsRead % 1000 == 0)
                        {
                            _logger.LogInformation("Read {Count} valid rows so far (at line {LineNumber})...", rowsRead, lineNumber);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error parsing row at line {LineNumber}", lineNumber);
            }
        }

        _logger.LogInformation("Read {Count} valid rows from CSV (processed {TotalLines} total lines)", rows.Count, lineNumber);
        return rows;
    }

    private async Task<string[]?> ReadCsvRow(StreamReader reader)
    {
        var parts = new List<string>();
        var currentPart = new StringBuilder();
        var inQuotes = false;
        var foundData = false;

        while (!reader.EndOfStream)
        {
            var c = (char)reader.Read();

            if (c == '\r')
            {
                // Skip carriage return, handle \n next
                continue;
            }

            if (c == '\n' && !inQuotes)
            {
                // End of row (only if not in quotes)
                parts.Add(currentPart.ToString());
                currentPart.Clear();
                if (parts.Count > 0 || foundData)
                {
                    return parts.ToArray();
                }
                // Empty line, continue to next
                continue;
            }

            if (c == '"')
            {
                if (inQuotes && reader.Peek() == '"')
                {
                    // Escaped quote ("")
                    currentPart.Append('"');
                    reader.Read(); // Skip next quote
                }
                else
                {
                    // Toggle quote state
                    inQuotes = !inQuotes;
                }
                foundData = true;
            }
            else if (c == ';' && !inQuotes)
            {
                // Field separator (only if not in quotes)
                parts.Add(currentPart.ToString());
                currentPart.Clear();
                foundData = true;
            }
            else
            {
                currentPart.Append(c);
                if (!char.IsWhiteSpace(c))
                {
                    foundData = true;
                }
            }
        }

        // End of file - add last part if we have data
        if (foundData || currentPart.Length > 0 || parts.Count > 0)
        {
            if (currentPart.Length > 0)
            {
                parts.Add(currentPart.ToString());
            }
            // Pad to 12 columns if needed
            while (parts.Count < 12)
            {
                parts.Add(string.Empty);
            }
            if (parts.Count > 0)
            {
                return parts.ToArray();
            }
        }

        return null;
    }

    private CsvRow? ParseCsvRow(string[] parts, int lineNumber)
    {
        if (parts.Length < 12)
        {
            // Pad with empty strings if needed
            while (parts.Length < 12)
            {
                var list = parts.ToList();
                list.Add(string.Empty);
                parts = list.ToArray();
            }
        }

        // Parse date (format: DD-MM-YYYY or D-M-YYYY)
        // Handle formats like: "14-1-2010", "1-9-2014", "26-6-2015", "15-8-2014"
        DateTime? releaseDate = null;
        if (!string.IsNullOrWhiteSpace(parts[0]))
        {
            var dateStr = parts[0].Trim();
            // Try multiple date formats to handle single/double digit days and months
            var dateFormats = new[] { "d-M-yyyy", "dd-M-yyyy", "d-MM-yyyy", "dd-MM-yyyy" };
            
            foreach (var format in dateFormats)
            {
                if (DateTime.TryParseExact(dateStr, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsedDate))
                {
                    // PostgreSQL requires UTC DateTime - convert to UTC (assuming local timezone)
                    releaseDate = DateTime.SpecifyKind(parsedDate, DateTimeKind.Utc);
                    break;
                }
            }
            
            if (!releaseDate.HasValue)
            {
                _logger.LogWarning("Could not parse date '{Date}' on line {LineNumber}", parts[0], lineNumber);
            }
        }

        if (!releaseDate.HasValue)
        {
            // Don't log empty rows - they're expected and very common
            // Only log if it's not an empty row (has some data)
            var hasData = parts.Skip(1).Any(p => !string.IsNullOrWhiteSpace(p));
            if (hasData)
            {
                _logger.LogDebug("Skipping line {LineNumber} - no valid release date", lineNumber);
            }
            return null;
        }

        return new CsvRow
        {
            LineNumber = lineNumber,
            ReleaseDate = releaseDate.Value,
            FcVersion = parts[1]?.Trim(),
            X200Version = parts[2]?.Trim(),
            X010Version = parts[3]?.Trim(),
            LiveStreamVersion = parts[4]?.Trim(),
            AsanetworkVersion = parts[5]?.Trim(),
            AndroidAppVersion = parts[6]?.Trim(),
            EolConnectVersion = parts[7]?.Trim(),
            By = parts[8]?.Trim(),
            ReleasedFor = parts[9]?.Trim(),
            Notes = parts[10]?.Trim(),
            ReleaseStatus = parts[11]?.Trim()
        };
    }

    private string[] SplitCsvLine(string line, char delimiter)
    {
        var parts = new List<string>();
        var currentPart = new StringBuilder();
        var inQuotes = false;

        for (int i = 0; i < line.Length; i++)
        {
            var c = line[i];

            if (c == '"')
            {
                if (inQuotes && i + 1 < line.Length && line[i + 1] == '"')
                {
                    // Escaped quote
                    currentPart.Append('"');
                    i++; // Skip next quote
                }
                else
                {
                    // Toggle quote state
                    inQuotes = !inQuotes;
                }
            }
            else if (c == delimiter && !inQuotes)
            {
                parts.Add(currentPart.ToString());
                currentPart.Clear();
            }
            else
            {
                currentPart.Append(c);
            }
        }

        // Add last part
        parts.Add(currentPart.ToString());

        return parts.ToArray();
    }

    private async Task<Dictionary<string, int>> CreateSoftwareEntries()
    {
        var softwareMap = new Dictionary<string, int>();

        var softwares = new[]
        {
            new Software { Name = "BM FlexCheck", Type = SoftwareType.Windows, IsActive = true },
            new Software { Name = "X200 Flash", Type = SoftwareType.Firmware, IsActive = true },
            new Software { Name = "X010", Type = SoftwareType.Firmware, IsActive = true },
            new Software { Name = "BM EOL Connect", Type = SoftwareType.Windows, IsActive = true }
        };

        foreach (var software in softwares)
        {
            _context.Softwares.Add(software);
            await _context.SaveChangesAsync();
            softwareMap[software.Name] = software.Id;
            _logger.LogInformation("Created software: {Name} (ID: {Id})", software.Name, software.Id);
        }

        return softwareMap;
    }

    private async Task<Dictionary<string, int>> CreateUsers(List<CsvRow> rows)
    {
        var userMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var userNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Get distinct users from "By" column
        // Handle cases like "JUC/PN" or "JUC / PN" - extract both users
        foreach (var row in rows)
        {
            if (string.IsNullOrWhiteSpace(row.By))
                continue;

            var byValue = row.By.Trim();
            var parts = ParseUsers(byValue);
            
            foreach (var part in parts)
            {
                if (!string.IsNullOrWhiteSpace(part))
                {
                    userNames.Add(part.Trim());
                }
            }
        }

        foreach (var userName in userNames)
        {
            var user = new User
            {
                Name = userName,
                Password = "imported", // Default password for imported users
                IsActive = true
            };

            _context.Users.Add(user);
            await _context.SaveChangesAsync();
            userMap[userName] = user.Id;
            _logger.LogInformation("Created user: {Name} (ID: {Id})", userName, user.Id);
        }

        return userMap;
    }

    private string[] ParseUsers(string byValue)
    {
        // Handle both "/" and " / " separators
        if (byValue.Contains(" / "))
        {
            return byValue.Split(new[] { " / " }, StringSplitOptions.RemoveEmptyEntries);
        }
        else if (byValue.Contains('/'))
        {
            return byValue.Split('/', StringSplitOptions.RemoveEmptyEntries);
        }
        else
        {
            return new[] { byValue };
        }
    }

    private async Task<Country> CreateDefaultCountry()
    {
        var country = new Country
        {
            Name = "Default",
            IsActive = true
        };

        _context.Countries.Add(country);
        await _context.SaveChangesAsync();
        _logger.LogInformation("Created default country: {Name} (ID: {Id})", country.Name, country.Id);

        return country;
    }

    private async Task<Dictionary<string, int>> CreateCustomers(List<CsvRow> rows, int countryId)
    {
        var customerMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        // Get distinct customers from "Released for" column
        var distinctCustomers = rows
            .Where(r => !string.IsNullOrWhiteSpace(r.ReleasedFor))
            .Select(r => r.ReleasedFor.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        foreach (var customerName in distinctCustomers)
        {
            var customer = new Customer
            {
                Name = customerName,
                CountryId = countryId,
                IsActive = true,
                RequiresCustomerValidation = false
            };

            _context.Customers.Add(customer);
            await _context.SaveChangesAsync();
            customerMap[customerName] = customer.Id;
            _logger.LogInformation("Created customer: {Name} (ID: {Id})", customerName, customer.Id);
        }

        return customerMap;
    }

    private async Task<ImportResult> ProcessRows(
        List<CsvRow> rows,
        Dictionary<string, int> softwareMap,
        Dictionary<string, int> userMap,
        Dictionary<string, int> customerMap)
    {
        var result = new ImportResult();
        var versionCache = new Dictionary<string, VersionHistory>(); // Key: "{SoftwareId}:{Version}"
        var batchSize = 100; // Save every 100 operations
        var operationCount = 0;
        var totalRows = rows.Count;
        var processedRows = 0;

        _logger.LogInformation("Processing {Count} rows...", totalRows);

        foreach (var row in rows)
        {
            // Skip if no customer or user
            if (string.IsNullOrWhiteSpace(row.ReleasedFor) || string.IsNullOrWhiteSpace(row.By))
            {
                _logger.LogWarning("Skipping row {LineNumber} - missing customer or user", row.LineNumber);
                continue;
            }

            if (!customerMap.TryGetValue(row.ReleasedFor, out var customerId))
            {
                _logger.LogWarning("Customer not found: {Customer} on line {LineNumber}", row.ReleasedFor, row.LineNumber);
                continue;
            }

            // Parse user(s) from "By" column
            // If format is "JUC/PN" or "JUC / PN", use first for Windows, second for Firmware
            var byValue = row.By.Trim();
            var userParts = ParseUsers(byValue);
            
            string? windowsUser = null;
            string? firmwareUser = null;

            if (userParts.Length >= 2)
            {
                // Two users: first for Windows, second for Firmware
                windowsUser = userParts[0].Trim();
                firmwareUser = userParts[1].Trim();
            }
            else if (userParts.Length == 1)
            {
                // Single user - use for both
                windowsUser = userParts[0].Trim();
                firmwareUser = userParts[0].Trim();
            }

            // Map release status
            var releaseStatus = MapReleaseStatus(row.ReleaseStatus);

            // Process each software version in the row
            var softwareVersions = new[]
            {
                ("BM FlexCheck", row.FcVersion, SoftwareType.Windows),
                ("X200 Flash", row.X200Version, SoftwareType.Firmware),
                ("X010", row.X010Version, SoftwareType.Firmware),
                ("BM EOL Connect", row.EolConnectVersion, SoftwareType.Windows)
            };

            foreach (var (softwareName, version, softwareType) in softwareVersions)
            {
                if (string.IsNullOrWhiteSpace(version))
                    continue;

                if (!softwareMap.TryGetValue(softwareName, out var softwareId))
                {
                    _logger.LogWarning("Software not found: {Software} on line {LineNumber}", softwareName, row.LineNumber);
                    continue;
                }

                // Select appropriate user based on software type
                var selectedUser = softwareType == SoftwareType.Windows ? windowsUser : firmwareUser;
                if (string.IsNullOrWhiteSpace(selectedUser))
                {
                    _logger.LogWarning("No user available for {SoftwareType} on line {LineNumber}", softwareType, row.LineNumber);
                    continue;
                }

                if (!userMap.TryGetValue(selectedUser, out var userId))
                {
                    _logger.LogWarning("User not found: {User} on line {LineNumber}", selectedUser, row.LineNumber);
                    continue;
                }

                var cacheKey = $"{softwareId}:{version}";
                VersionHistory? versionHistory = null;

                // Check if version already exists
                if (versionCache.TryGetValue(cacheKey, out var existingVersion))
                {
                    versionHistory = existingVersion;
                }
                else
                {
                    versionHistory = await _context.VersionHistories
                        .Include(v => v.VersionHistoryCustomers)
                        .Include(v => v.HistoryNotes)
                        .FirstOrDefaultAsync(v => v.SoftwareId == softwareId && v.Version == version);

                    if (versionHistory != null)
                    {
                        versionCache[cacheKey] = versionHistory;
                    }
                }

                if (versionHistory == null)
                {
                    // Create new version
                    versionHistory = new VersionHistory
                    {
                        Version = version,
                        SoftwareId = softwareId,
                        ReleaseDate = row.ReleaseDate,
                        ReleasedById = userId,
                        ReleaseStatus = releaseStatus
                    };

                    _context.VersionHistories.Add(versionHistory);
                    // Save immediately to get the version ID (required for foreign keys in notes and customers)
                    await _context.SaveChangesAsync();
                    versionCache[cacheKey] = versionHistory;
                    result.VersionsCreated++;
                }
                else
                {
                    result.VersionsUpdated++;
                }

                // Add/update customer release stage
                var customerStage = MapCustomerReleaseStage(releaseStatus);
                var versionHistoryCustomer = await _context.VersionHistoryCustomers
                    .FirstOrDefaultAsync(vhc => vhc.VersionHistoryId == versionHistory.Id && vhc.CustomerId == customerId);

                if (versionHistoryCustomer == null)
                {
                    versionHistoryCustomer = new VersionHistoryCustomer
                    {
                        VersionHistoryId = versionHistory.Id,
                        CustomerId = customerId,
                        ReleaseStage = customerStage
                    };
                    _context.VersionHistoryCustomers.Add(versionHistoryCustomer);
                    operationCount++;
                }
                else
                {
                    // Update existing stage if needed
                    versionHistoryCustomer.ReleaseStage = customerStage;
                    operationCount++;
                }

                // Add note if present
                if (!string.IsNullOrWhiteSpace(row.Notes))
                {
                    // Check if this exact note already exists for this version
                    var existingNote = await _context.HistoryNotes
                        .FirstOrDefaultAsync(hn => hn.VersionHistoryId == versionHistory.Id && hn.Note == row.Notes);

                    if (existingNote == null)
                    {
                        var note = new HistoryNote
                        {
                            VersionHistoryId = versionHistory.Id,
                            Note = row.Notes
                        };
                        _context.HistoryNotes.Add(note);
                        
                        // Save immediately to get the note ID (required for foreign key)
                        await _context.SaveChangesAsync();
                        result.NotesCreated++;

                        // Now link note to customer (note.Id is now available)
                        var noteCustomer = new HistoryNoteCustomer
                        {
                            HistoryNoteId = note.Id,
                            CustomerId = customerId
                        };
                        _context.HistoryNoteCustomers.Add(noteCustomer);
                        operationCount++;
                    }
                    else
                    {
                        // Check if note is linked to this customer
                        var noteCustomerLink = await _context.HistoryNoteCustomers
                            .FirstOrDefaultAsync(hnc => hnc.HistoryNoteId == existingNote.Id && hnc.CustomerId == customerId);

                        if (noteCustomerLink == null)
                        {
                            var noteCustomer = new HistoryNoteCustomer
                            {
                                HistoryNoteId = existingNote.Id,
                                CustomerId = customerId
                            };
                            _context.HistoryNoteCustomers.Add(noteCustomer);
                            operationCount++;
                        }
                    }

                    // Check for duplicate notes across different software
                    var duplicateCheck = await _context.HistoryNotes
                        .Where(hn => hn.Note == row.Notes && hn.VersionHistoryId != versionHistory.Id)
                        .Include(hn => hn.VersionHistory)
                        .ThenInclude(vh => vh.Software)
                        .FirstOrDefaultAsync();

                    if (duplicateCheck != null)
                    {
                        result.DuplicateNotes.Add(new DuplicateNoteInfo
                        {
                            Note = row.Notes,
                            Software1 = softwareName,
                            Version1 = version,
                            Software2 = duplicateCheck.VersionHistory.Software.Name,
                            Version2 = duplicateCheck.VersionHistory.Version,
                            LineNumber = row.LineNumber
                        });
                    }
                }

                // Batch save operations
                if (operationCount >= batchSize)
                {
                    await _context.SaveChangesAsync();
                    operationCount = 0;
                }
            }
        }

        // Save any remaining operations
        if (operationCount > 0)
        {
            await _context.SaveChangesAsync();
        }

        return result;
    }

    private ReleaseStatus MapReleaseStatus(string? statusText)
    {
        if (string.IsNullOrWhiteSpace(statusText))
            return ReleaseStatus.PreRelease;

        var normalized = statusText.Trim();

        // Map common status texts to enum values
        if (normalized.Equals("PreRelease", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Pre-Release", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Pre Release", StringComparison.OrdinalIgnoreCase))
        {
            return ReleaseStatus.PreRelease;
        }

        if (normalized.Equals("Released", StringComparison.OrdinalIgnoreCase))
        {
            return ReleaseStatus.Released;
        }

        if (normalized.Equals("ProductionReady", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Production Ready", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Production", StringComparison.OrdinalIgnoreCase))
        {
            return ReleaseStatus.ProductionReady;
        }

        if (normalized.Equals("Canceled", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))
        {
            return ReleaseStatus.Canceled;
        }

        // Default to PreRelease if status doesn't match
        return ReleaseStatus.PreRelease;
    }

    private CustomerReleaseStage MapCustomerReleaseStage(ReleaseStatus status)
    {
        return status switch
        {
            ReleaseStatus.PreRelease => CustomerReleaseStage.PreRelease,
            ReleaseStatus.Released => CustomerReleaseStage.Released,
            ReleaseStatus.ProductionReady => CustomerReleaseStage.ProductionReady,
            ReleaseStatus.Canceled => CustomerReleaseStage.Canceled,
            _ => CustomerReleaseStage.PreRelease
        };
    }

    private class CsvRow
    {
        public int LineNumber { get; set; }
        public DateTime ReleaseDate { get; set; }
        public string? FcVersion { get; set; }
        public string? X200Version { get; set; }
        public string? X010Version { get; set; }
        public string? LiveStreamVersion { get; set; }
        public string? AsanetworkVersion { get; set; }
        public string? AndroidAppVersion { get; set; }
        public string? EolConnectVersion { get; set; }
        public string? By { get; set; }
        public string? ReleasedFor { get; set; }
        public string? Notes { get; set; }
        public string? ReleaseStatus { get; set; }
    }

    private class ImportResult
    {
        public int VersionsCreated { get; set; }
        public int VersionsUpdated { get; set; }
        public int NotesCreated { get; set; }
        public List<DuplicateNoteInfo> DuplicateNotes { get; set; } = new();
    }

    private class DuplicateNoteInfo
    {
        public string Note { get; set; } = string.Empty;
        public string Software1 { get; set; } = string.Empty;
        public string Version1 { get; set; } = string.Empty;
        public string Software2 { get; set; } = string.Empty;
        public string Version2 { get; set; } = string.Empty;
        public int LineNumber { get; set; }
    }

    [HttpPost("firmware/countries")]
    public async Task<ActionResult> ImportFirmwareCountries()
    {
        try
        {
            if (!System.IO.File.Exists(_firmwareCsvFilePath))
            {
                return BadRequest(new { message = $"Firmware CSV file not found at: {_firmwareCsvFilePath}" });
            }

            _logger.LogInformation("Starting firmware countries import from: {Path}", _firmwareCsvFilePath);

            // Read CSV and extract unique country names
            var rows = await ReadFirmwareCsvFile(_firmwareCsvFilePath);
            var countryNames = rows
                .Where(r => !string.IsNullOrWhiteSpace(r.Country))
                .Select(r => r.Country!.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(c => c)
                .ToList();

            var createdCountries = new List<object>();
            var existingCountries = new List<object>();

            // Get all existing countries (case-insensitive)
            var existingCountriesDb = await _context.Countries
                .Where(c => c.IsActive)
                .ToListAsync();

            var existingCountryNames = new HashSet<string>(
                existingCountriesDb.Select(c => c.Name.ToLower()),
                StringComparer.OrdinalIgnoreCase);

            // Create countries that don't exist
            foreach (var countryName in countryNames)
            {
                var countryNameLower = countryName.ToLower();
                if (existingCountryNames.Contains(countryNameLower))
                {
                    // Country already exists
                    var existing = existingCountriesDb.First(c => c.Name.ToLower() == countryNameLower);
                    existingCountries.Add(new
                    {
                        id = existing.Id,
                        name = existing.Name
                    });
                }
                else
                {
                    // Create new country
                    var country = new Country
                    {
                        Name = countryName,
                        IsActive = true
                    };
                    _context.Countries.Add(country);
                    await _context.SaveChangesAsync();
                    
                    createdCountries.Add(new
                    {
                        id = country.Id,
                        name = country.Name
                    });
                    
                    existingCountryNames.Add(countryNameLower);
                    existingCountriesDb.Add(country);
                    _logger.LogInformation("Created country: {Name} (ID: {Id})", country.Name, country.Id);
                }
            }

            _logger.LogInformation("Countries import completed. Created: {Created}, Existing: {Existing}", 
                createdCountries.Count, existingCountries.Count);

            return Ok(new
            {
                success = true,
                message = "Countries import completed successfully",
                statistics = new
                {
                    total = countryNames.Count,
                    created = createdCountries.Count,
                    existing = existingCountries.Count
                },
                created = createdCountries,
                existing = existingCountries
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during firmware countries import");
            return StatusCode(500, new { message = $"Import failed: {ex.Message}", error = ex.ToString() });
        }
    }

    [HttpPost("firmware")]
    public async Task<ActionResult> ImportFirmware()
    {
        try
        {
            if (!System.IO.File.Exists(_firmwareCsvFilePath))
            {
                return BadRequest(new { message = $"Firmware CSV file not found at: {_firmwareCsvFilePath}" });
            }

            _logger.LogInformation("Starting firmware CSV import from: {Path}", _firmwareCsvFilePath);

            // Step 1: Ensure X200 Turbo software exists
            var softwareMap = await EnsureFirmwareSoftware();

            // Step 2: Read and parse CSV
            var rows = await ReadFirmwareCsvFile(_firmwareCsvFilePath);

            // Step 3: Get country to customers mapping
            var countryCustomersMap = await GetCountryCustomersMap();

            // Step 4: Get or create users
            var userMap = await GetOrCreateUsers(rows);

            // Step 5: Process rows and create/update versions
            var importResult = await ProcessFirmwareRows(rows, softwareMap, userMap, countryCustomersMap);

            _logger.LogInformation("Firmware import completed. Created: {Versions} versions, {Notes} notes", 
                importResult.VersionsCreated, importResult.NotesCreated);

            return Ok(new
            {
                success = true,
                message = "Firmware import completed successfully",
                statistics = new
                {
                    versionsCreated = importResult.VersionsCreated,
                    versionsUpdated = importResult.VersionsUpdated,
                    notesCreated = importResult.NotesCreated
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during firmware CSV import");
            return StatusCode(500, new { message = $"Import failed: {ex.Message}", error = ex.ToString() });
        }
    }

    private async Task<Dictionary<string, int>> EnsureFirmwareSoftware()
    {
        var softwareMap = new Dictionary<string, int>();

        // Check if X200 Flash exists
        var x200Flash = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "X200 Flash");
        if (x200Flash == null)
        {
            x200Flash = new Software { Name = "X200 Flash", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(x200Flash);
            await _context.SaveChangesAsync();
        }
        softwareMap["X200 Flash"] = x200Flash.Id;

        // Check if X200 Turbo exists, create if not
        var x200Turbo = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "X200 Turbo");
        if (x200Turbo == null)
        {
            x200Turbo = new Software { Name = "X200 Turbo", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(x200Turbo);
            await _context.SaveChangesAsync();
        }
        softwareMap["X200 Turbo"] = x200Turbo.Id;

        // Check if X010 exists
        var x010 = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "X010");
        if (x010 == null)
        {
            x010 = new Software { Name = "X010", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(x010);
            await _context.SaveChangesAsync();
        }
        softwareMap["X010"] = x010.Id;

        // Check if CCPU exists, create if not
        var ccpu = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "CCPU");
        if (ccpu == null)
        {
            ccpu = new Software { Name = "CCPU", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(ccpu);
            await _context.SaveChangesAsync();
        }
        softwareMap["CCPU"] = ccpu.Id;

        // Check if DCPU exists, create if not
        var dcpu = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "DCPU");
        if (dcpu == null)
        {
            dcpu = new Software { Name = "DCPU", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(dcpu);
            await _context.SaveChangesAsync();
        }
        softwareMap["DCPU"] = dcpu.Id;

        // Check if RCPU exists, create if not
        var rcpu = await _context.Softwares.FirstOrDefaultAsync(s => s.Name == "RCPU");
        if (rcpu == null)
        {
            rcpu = new Software { Name = "RCPU", Type = SoftwareType.Firmware, IsActive = true };
            _context.Softwares.Add(rcpu);
            await _context.SaveChangesAsync();
        }
        softwareMap["RCPU"] = rcpu.Id;

        return softwareMap;
    }

    private async Task<List<FirmwareCsvRow>> ReadFirmwareCsvFile(string filePath)
    {
        var rows = new List<FirmwareCsvRow>();
        var lineNumber = 0;

        // Try to detect encoding - CSV files often use Windows-1252 or ISO-8859-1 for European characters
        // Since we converted the file to UTF-8, default to UTF-8, but try to detect if needed
        var encoding = DetectEncoding(filePath) ?? Encoding.UTF8;
        using var reader = new StreamReader(filePath, encoding);
        
        // Skip header row
        var headerRow = await ReadCsvRow(reader);
        if (headerRow == null || headerRow.Length < 13)
        {
            throw new Exception("Firmware CSV file is empty or has invalid header");
        }

        lineNumber = 1;
        var rowsRead = 0;

        while (!reader.EndOfStream)
        {
            lineNumber++;
            try
            {
                var row = await ReadCsvRow(reader);
                if (row == null || row.Length < 13)
                    continue;

                var parsedRow = ParseFirmwareCsvRow(row, lineNumber);
                if (parsedRow != null)
                {
                    rows.Add(parsedRow);
                    rowsRead++;
                    
                    if (rowsRead % 100 == 0)
                    {
                        _logger.LogInformation("Read {Count} valid rows so far (at line {LineNumber})...", rowsRead, lineNumber);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error parsing row at line {LineNumber}", lineNumber);
            }
        }

        _logger.LogInformation("Read {Count} valid rows from firmware CSV (processed {TotalLines} total lines)", rows.Count, lineNumber);
        return rows;
    }

    private FirmwareCsvRow? ParseFirmwareCsvRow(string[] parts, int lineNumber)
    {
        // New column order: CONTRY;CHANGED;USER;CCPU;CCPU_CHANGES;DCPU;DCPU_CHANGES;RCPU;RCPU_CHANGES;X010;X010T_CHANGES;X200_FLASH_TURBE;X200T_CHANGES
        if (parts.Length < 13)
        {
            // Pad with empty strings if needed
            while (parts.Length < 13)
            {
                var list = parts.ToList();
                list.Add(string.Empty);
                parts = list.ToArray();
            }
        }

        if (string.IsNullOrWhiteSpace(parts[1])) // CHANGED (date) - now at index 1
            return null;

        // Parse date (format: DD-MM-YYYY)
        DateTime? releaseDate = null;
        var dateStr = parts[1].Trim();
        var dateFormats = new[] { "d-M-yyyy", "dd-M-yyyy", "d-MM-yyyy", "dd-MM-yyyy", "d-M-yyyy HH:mm:ss", "dd-M-yyyy HH:mm:ss" };
        
        foreach (var format in dateFormats)
        {
            if (DateTime.TryParseExact(dateStr, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsedDate))
            {
                releaseDate = DateTime.SpecifyKind(parsedDate, DateTimeKind.Utc);
                break;
            }
        }

        if (!releaseDate.HasValue)
        {
            _logger.LogDebug("Skipping line {LineNumber} - no valid release date: {Date}", lineNumber, dateStr);
            return null;
        }

        return new FirmwareCsvRow
        {
            LineNumber = lineNumber,
            ReleaseDate = releaseDate.Value,
            Country = parts[0]?.Trim(),        // CONTRY - index 0
            User = parts[2]?.Trim(),           // USER - index 2
            CcpuVersion = parts[3]?.Trim(),    // CCPU - index 3
            CcpuChanges = parts[4]?.Trim(),    // CCPU_CHANGES - index 4
            DcpuVersion = parts[5]?.Trim(),    // DCPU - index 5
            DcpuChanges = parts[6]?.Trim(),    // DCPU_CHANGES - index 6
            RcpuVersion = parts[7]?.Trim(),    // RCPU - index 7
            RcpuChanges = parts[8]?.Trim(),    // RCPU_CHANGES - index 8
            X010Version = parts[9]?.Trim(),    // X010 - index 9
            X010Changes = parts[10]?.Trim(),   // X010T_CHANGES - index 10
            X200FlashTurboVersion = parts[11]?.Trim(), // X200_FLASH_TURBE - index 11
            X200Changes = parts[12]?.Trim()    // X200T_CHANGES - index 12
        };
    }

    private async Task<Dictionary<string, List<int>>> GetCountryCustomersMap()
    {
        var map = new Dictionary<string, List<int>>(StringComparer.OrdinalIgnoreCase);
        
        var customers = await _context.Customers
            .Include(c => c.Country)
            .Where(c => c.IsActive)
            .ToListAsync();

        foreach (var customer in customers)
        {
            if (customer?.Country == null)
                continue;

            var countryName = customer.Country.Name;
            if (string.IsNullOrWhiteSpace(countryName))
                continue;

            if (!map.ContainsKey(countryName))
            {
                map[countryName] = new List<int>();
            }
            map[countryName].Add(customer.Id);
        }

        return map;
    }

    private async Task<List<int>> GetOrCreateCustomersForCountry(string countryName, Dictionary<string, List<int>> countryCustomersMap)
    {
        if (countryCustomersMap.TryGetValue(countryName, out var customerIds) && customerIds.Count > 0)
        {
            return customerIds;
        }

        // No customers found - create a default customer for this country
        _logger.LogWarning("No customers found for country: {Country}. Creating default customer.", countryName);

        // Find or create the country (case-insensitive search)
        var country = await _context.Countries
            .FirstOrDefaultAsync(c => c.Name.ToLower() == countryName.ToLower());
        if (country == null)
        {
            country = new Country
            {
                Name = countryName,
                IsActive = true
            };
            _context.Countries.Add(country);
            await _context.SaveChangesAsync();
        }

        if (country == null)
        {
            _logger.LogError("Failed to create or find country: {Country}", countryName);
            return new List<int>();
        }

        // Create default customer
        var defaultCustomer = new Customer
        {
            Name = $"{countryName} (Default)",
            CountryId = country.Id,
            IsActive = true,
            RequiresCustomerValidation = false
        };
        _context.Customers.Add(defaultCustomer);
        await _context.SaveChangesAsync();

        // Update the map for future lookups (use original case for key)
        if (countryCustomersMap != null)
        {
            countryCustomersMap[countryName] = new List<int> { defaultCustomer.Id };
        }

        return new List<int> { defaultCustomer.Id };
    }

    private async Task<Dictionary<string, int>> GetOrCreateUsers(List<FirmwareCsvRow> rows)
    {
        var userMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var distinctUsers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Extract users, taking only the first user if there's a "/" separator
        foreach (var row in rows)
        {
            if (string.IsNullOrWhiteSpace(row.User))
                continue;

            var userName = row.User.Trim();
            
            // If user contains "/", take only the first part
            if (userName.Contains('/'))
            {
                var parts = userName.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                if (parts.Length > 0)
                {
                    userName = parts[0].Trim();
                }
            }
            
            if (!string.IsNullOrWhiteSpace(userName))
            {
                distinctUsers.Add(userName);
            }
        }

        foreach (var userName in distinctUsers)
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Name == userName);
            if (user == null)
            {
                user = new User
                {
                    Name = userName,
                    Password = "imported",
                    IsActive = true
                };
                _context.Users.Add(user);
                await _context.SaveChangesAsync();
            }
            userMap[userName] = user.Id;
        }

        return userMap;
    }


    private List<(string Version, string SoftwareName)> ParseX200Versions(string? versionText)
    {
        var results = new List<(string Version, string SoftwareName)>();
        
        if (string.IsNullOrWhiteSpace(versionText))
            return results;

        var version = versionText.Trim();
        
        // Handle format like "P14.217/P9.135 L1" - split by "/"
        if (version.Contains('/'))
        {
            var parts = version.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            var lSuffix = "";
            
            // Check if there's an L suffix at the end (e.g., "P14.217/P9.135 L1")
            var lastPart = parts[parts.Length - 1];
            var lMatch = System.Text.RegularExpressions.Regex.Match(lastPart, @"\s+(L\d+)$");
            if (lMatch.Success)
            {
                lSuffix = lMatch.Groups[1].Value; // e.g., "L1"
                // Remove L suffix from last part
                parts[parts.Length - 1] = lastPart.Substring(0, lMatch.Index).Trim();
            }

            foreach (var part in parts)
            {
                var cleanVersion = part.Trim();
                if (!string.IsNullOrWhiteSpace(cleanVersion))
                {
                    // Add L suffix to each version if it was found
                    if (!string.IsNullOrEmpty(lSuffix) && !cleanVersion.EndsWith(lSuffix))
                    {
                        cleanVersion = $"{cleanVersion} {lSuffix}";
                    }
                    
                    // Determine software type
                    var softwareName = DetermineX200SoftwareType(cleanVersion);
                    results.Add((cleanVersion, softwareName));
                }
            }
        }
        else
        {
            // Single version
            var softwareName = DetermineX200SoftwareType(version);
            results.Add((version, softwareName));
        }

        return results;
    }

    private string DetermineX200SoftwareType(string version)
    {
        // Remove L suffix for checking (e.g., "P14.217 L1" → "P14.217")
        var cleanVersion = System.Text.RegularExpressions.Regex.Replace(version, @"\s+L\d+$", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        // P9.xx or P12.xxx → X200 Turbo
        // Everything else → X200 Flash
        if (cleanVersion.StartsWith("P9.", StringComparison.OrdinalIgnoreCase) ||
            cleanVersion.StartsWith("P12.", StringComparison.OrdinalIgnoreCase) ||
            cleanVersion.StartsWith("M", StringComparison.OrdinalIgnoreCase)) // M versions also seem to be Turbo
        {
            return "X200 Turbo";
        }
        return "X200 Flash";
    }

    private async Task<FirmwareImportResult> ProcessFirmwareRows(
        List<FirmwareCsvRow> rows,
        Dictionary<string, int> softwareMap,
        Dictionary<string, int> userMap,
        Dictionary<string, List<int>> countryCustomersMap)
    {
        var result = new FirmwareImportResult();
        var versionCache = new Dictionary<string, VersionHistory>(); // Key: "{SoftwareId}:{Version}"

        foreach (var row in rows)
        {
            // Skip if no country or user
            if (string.IsNullOrWhiteSpace(row.Country) || string.IsNullOrWhiteSpace(row.User))
            {
                _logger.LogDebug("Skipping row {LineNumber} - missing country or user", row.LineNumber);
                continue;
            }

            // Get or create customers for this country
            if (string.IsNullOrWhiteSpace(row.Country))
            {
                _logger.LogDebug("Skipping row {LineNumber} - missing country", row.LineNumber);
                continue;
            }

            var customerIds = await GetOrCreateCustomersForCountry(row.Country, countryCustomersMap);
            if (customerIds == null || customerIds.Count == 0)
            {
                _logger.LogWarning("Could not get or create customers for country: '{Country}' on line {LineNumber}. Skipping this row.", row.Country, row.LineNumber);
                continue;
            }
            
            _logger.LogDebug("Processing row {LineNumber} for country: '{Country}' with {CustomerCount} customers", row.LineNumber, row.Country, customerIds.Count);

            // Extract first user if there's a "/" separator
            var userName = row.User.Trim();
            if (userName.Contains('/'))
            {
                var parts = userName.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                if (parts.Length > 0)
                {
                    userName = parts[0].Trim();
                }
            }

            if (!userMap.TryGetValue(userName, out var userId))
            {
                _logger.LogWarning("User not found: {User} on line {LineNumber}", userName, row.LineNumber);
                continue;
            }

            // Process CCPU version if present
            if (!string.IsNullOrWhiteSpace(row.CcpuVersion))
            {
                await ProcessFirmwareVersion(
                    "CCPU", row.CcpuVersion, row.CcpuChanges, row.ReleaseDate, userId, 
                    customerIds, softwareMap, versionCache, result);
            }

            // Process DCPU version if present
            if (!string.IsNullOrWhiteSpace(row.DcpuVersion))
            {
                await ProcessFirmwareVersion(
                    "DCPU", row.DcpuVersion, row.DcpuChanges, row.ReleaseDate, userId,
                    customerIds, softwareMap, versionCache, result);
            }

            // Process RCPU version if present
            if (!string.IsNullOrWhiteSpace(row.RcpuVersion))
            {
                await ProcessFirmwareVersion(
                    "RCPU", row.RcpuVersion, row.RcpuChanges, row.ReleaseDate, userId,
                    customerIds, softwareMap, versionCache, result);
            }

            // Process X010 version if present
            if (!string.IsNullOrWhiteSpace(row.X010Version))
            {
                await ProcessFirmwareVersion(
                    "X010", row.X010Version, row.X010Changes, row.ReleaseDate, userId, 
                    customerIds, softwareMap, versionCache, result);
            }

            // Process X200 versions
            if (!string.IsNullOrWhiteSpace(row.X200FlashTurboVersion))
            {
                var x200Versions = ParseX200Versions(row.X200FlashTurboVersion);
                if (x200Versions.Count == 0)
                {
                    _logger.LogWarning("Could not parse X200 version '{Version}' on line {LineNumber} for country '{Country}'", 
                        row.X200FlashTurboVersion, row.LineNumber, row.Country);
                }
                foreach (var (version, softwareName) in x200Versions)
                {
                    await ProcessFirmwareVersion(
                        softwareName, version, row.X200Changes, row.ReleaseDate, userId,
                        customerIds, softwareMap, versionCache, result);
                }
            }
        }

        return result;
    }

    private async Task ProcessFirmwareVersion(
        string softwareName,
        string version,
        string? notes,
        DateTime releaseDate,
        int userId,
        List<int> customerIds,
        Dictionary<string, int> softwareMap,
        Dictionary<string, VersionHistory> versionCache,
        FirmwareImportResult result)
    {
        if (!softwareMap.TryGetValue(softwareName, out var softwareId))
        {
            _logger.LogWarning("Software not found: {Software}", softwareName);
            return;
        }

        var cacheKey = $"{softwareId}:{version}";
        VersionHistory? versionHistory = null;

        // Check cache first
        if (versionCache.TryGetValue(cacheKey, out var cachedVersion))
        {
            versionHistory = cachedVersion;
        }
        else
        {
            // Check database
            versionHistory = await _context.VersionHistories
                .FirstOrDefaultAsync(v => v.SoftwareId == softwareId && v.Version == version);

            if (versionHistory != null)
            {
                versionCache[cacheKey] = versionHistory;
            }
        }

        // Create version if it doesn't exist
        if (versionHistory == null)
        {
            versionHistory = new VersionHistory
            {
                Version = version,
                SoftwareId = softwareId,
                ReleaseDate = releaseDate,
                ReleasedById = userId,
                ReleaseStatus = ReleaseStatus.ProductionReady
            };
            _context.VersionHistories.Add(versionHistory);
            await _context.SaveChangesAsync();
            versionCache[cacheKey] = versionHistory;
            result.VersionsCreated++;
        }
        else
        {
            result.VersionsUpdated++;
        }

        // Batch load existing customer links for this version
        var existingCustomerLinks = await _context.VersionHistoryCustomers
            .Where(vhc => vhc.VersionHistoryId == versionHistory.Id && customerIds.Contains(vhc.CustomerId))
            .Select(vhc => vhc.CustomerId)
            .ToListAsync();

        // Add missing customer links
        var missingCustomerIds = customerIds.Where(cid => !existingCustomerLinks.Contains(cid)).ToList();
        foreach (var customerId in missingCustomerIds)
        {
            var                 versionHistoryCustomer = new VersionHistoryCustomer
                {
                    VersionHistoryId = versionHistory.Id,
                    CustomerId = customerId,
                    ReleaseStage = CustomerReleaseStage.ProductionReady
                };
            _context.VersionHistoryCustomers.Add(versionHistoryCustomer);
        }

        // Add note if present - create ONE note with ALL customers for this country
        var hasNoteChanges = false;
        if (!string.IsNullOrWhiteSpace(notes))
        {
            // Check if this exact note already exists for this version
            var existingNote = await _context.HistoryNotes
                .FirstOrDefaultAsync(hn => hn.VersionHistoryId == versionHistory.Id && hn.Note == notes);

            if (existingNote == null)
            {
                var note = new HistoryNote
                {
                    VersionHistoryId = versionHistory.Id,
                    Note = notes
                };
                _context.HistoryNotes.Add(note);
                // Save to get note ID, then add customer links
                await _context.SaveChangesAsync();
                result.NotesCreated++;

                // Link note to ALL customers for this country
                foreach (var customerId in customerIds)
                {
                    var noteCustomer = new HistoryNoteCustomer
                    {
                        HistoryNoteId = note.Id,
                        CustomerId = customerId
                    };
                    _context.HistoryNoteCustomers.Add(noteCustomer);
                }
                hasNoteChanges = true;
            }
            else
            {
                // Batch load existing note-customer links
                var linkedCustomerIds = await _context.HistoryNoteCustomers
                    .Where(hnc => hnc.HistoryNoteId == existingNote.Id && customerIds.Contains(hnc.CustomerId))
                    .Select(hnc => hnc.CustomerId)
                    .ToListAsync();

                // Add missing customer links
                var missingNoteCustomerIds = customerIds.Where(cid => !linkedCustomerIds.Contains(cid)).ToList();
                if (missingNoteCustomerIds.Count > 0)
                {
                    foreach (var customerId in missingNoteCustomerIds)
                    {
                        var noteCustomer = new HistoryNoteCustomer
                        {
                            HistoryNoteId = existingNote.Id,
                            CustomerId = customerId
                        };
                        _context.HistoryNoteCustomers.Add(noteCustomer);
                    }
                    hasNoteChanges = true;
                }
            }
        }

        // Save all changes for this version at once (customer links + note links)
        if (missingCustomerIds.Count > 0 || hasNoteChanges)
        {
            await _context.SaveChangesAsync();
        }
    }

    private Encoding? DetectEncoding(string filePath)
    {
        // Try to detect encoding by reading the BOM (Byte Order Mark)
        using var fileStream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var bom = new byte[4];
        fileStream.Read(bom, 0, 4);
        fileStream.Position = 0;

        // Check for UTF-8 BOM
        if (bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF)
        {
            return Encoding.UTF8;
        }
        // Check for UTF-16 LE BOM
        if (bom[0] == 0xFF && bom[1] == 0xFE)
        {
            return Encoding.Unicode;
        }
        // Check for UTF-16 BE BOM
        if (bom[0] == 0xFE && bom[1] == 0xFF)
        {
            return Encoding.BigEndianUnicode;
        }

        // Try to detect encoding by reading first few lines
        // CSV files with European characters often use Windows-1252 or ISO-8859-1
        try
        {
            // Try UTF-8 first (since we converted the file)
            fileStream.Position = 0;
            using var reader = new StreamReader(fileStream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
            var firstLine = reader.ReadLine();
            var hasReplacementCharUtf8 = firstLine != null && (firstLine.Contains('\uFFFD') || firstLine.Contains('?'));
            
            // If UTF-8 reads well, use it
            if (!hasReplacementCharUtf8)
            {
                return Encoding.UTF8;
            }
            
            // Try Windows-1252 if available (for European CSV files from Excel)
            try
            {
                fileStream.Position = 0;
                using var reader1252 = new StreamReader(fileStream, Encoding.GetEncoding(1252), detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
                var testLine1252 = reader1252.ReadLine();
                var hasReplacementChar1252 = testLine1252 != null && (testLine1252.Contains('\uFFFD') || testLine1252.Contains('?'));
                
                if (!hasReplacementChar1252)
                {
                    return Encoding.GetEncoding(1252); // Windows-1252
                }
            }
            catch (NotSupportedException)
            {
                // Windows-1252 not available, try Encoding.Default (usually Windows-1252 on Windows)
                try
                {
                    fileStream.Position = 0;
                    using var readerDefault = new StreamReader(fileStream, Encoding.Default, detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
                    var testLineDefault = readerDefault.ReadLine();
                    var hasReplacementCharDefault = testLineDefault != null && (testLineDefault.Contains('\uFFFD') || testLineDefault.Contains('?'));
                    
                    if (!hasReplacementCharDefault)
                    {
                        return Encoding.Default;
                    }
                }
                catch
                {
                    // Fall through to UTF-8
                }
            }
            
            // Default to UTF-8 if detection fails
            return Encoding.UTF8;
        }
        catch
        {
            // If detection fails, return null to use UTF-8 as default
        }

        return null; // Will default to UTF-8
    }

    private class FirmwareCsvRow
    {
        public int LineNumber { get; set; }
        public DateTime ReleaseDate { get; set; }
        public string? Country { get; set; }
        public string? User { get; set; }
        public string? CcpuVersion { get; set; }
        public string? CcpuChanges { get; set; }
        public string? DcpuVersion { get; set; }
        public string? DcpuChanges { get; set; }
        public string? RcpuVersion { get; set; }
        public string? RcpuChanges { get; set; }
        public string? X010Version { get; set; }
        public string? X010Changes { get; set; }
        public string? X200FlashTurboVersion { get; set; }
        public string? X200Changes { get; set; }
    }

    private class FirmwareImportResult
    {
        public int VersionsCreated { get; set; }
        public int VersionsUpdated { get; set; }
        public int NotesCreated { get; set; }
    }
}

