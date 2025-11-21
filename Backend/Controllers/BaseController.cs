using Microsoft.AspNetCore.Mvc;
using BMReleaseManager.Data;
using Microsoft.EntityFrameworkCore;

namespace BMReleaseManager.Controllers;

public class BaseController : ControllerBase
{
    protected readonly ApplicationDbContext _context;

    public BaseController(ApplicationDbContext context)
    {
        _context = context;
    }

    protected async Task<int?> GetCurrentUserId()
    {
        // 1. Try Session
        var userId = HttpContext.Session.GetInt32("UserId");
        if (userId.HasValue)
        {
            return userId.Value;
        }

        // 2. Try Authorization Header
        var authHeader = HttpContext.Request.Headers["Authorization"].FirstOrDefault();
        if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Basic "))
        {
            try
            {
                var token = authHeader.Substring("Basic ".Length);
                var tokenBytes = Convert.FromBase64String(token);
                var tokenString = System.Text.Encoding.UTF8.GetString(tokenBytes);
                var parts = tokenString.Split(':');
                
                if (parts.Length == 2 && int.TryParse(parts[0], out var tokenUserId))
                {
                    var user = await _context.Users.FindAsync(tokenUserId);
                    if (user != null && user.Name == parts[1])
                    {
                        // Restore session from token for future requests
                        HttpContext.Session.SetInt32("UserId", user.Id);
                        HttpContext.Session.SetString("UserName", user.Name);
                        
                        return user.Id;
                    }
                }
            }
            catch
            {
                // Invalid token
            }
        }

        return null;
    }
}

