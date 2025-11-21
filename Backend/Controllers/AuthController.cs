using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;
using BMReleaseManager.DTOs;

namespace BMReleaseManager.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : BaseController
{
    public AuthController(ApplicationDbContext context) : base(context)
    {
    }

    [HttpPost("login")]
    public async Task<ActionResult<LoginResponse>> Login([FromBody] LoginRequest request)
    {
        var user = await _context.Users
            .FirstOrDefaultAsync(u => u.Name == request.Username && u.Password == request.Password);

        if (user == null)
        {
            return Ok(new LoginResponse
            {
                Success = false,
                Message = "Invalid username or password"
            });
        }

        // Store user session
        HttpContext.Session.SetInt32("UserId", user.Id);
        HttpContext.Session.SetString("UserName", user.Name);

        // Also return a simple token for Elm (session ID is fine for internal use)
        var token = $"{user.Id}:{user.Name}";
        var tokenBytes = System.Text.Encoding.UTF8.GetBytes(token);
        var tokenBase64 = Convert.ToBase64String(tokenBytes);

        return Ok(new LoginResponse
        {
            Success = true,
            Message = "Login successful",
            User = new UserDto
            {
                Id = user.Id,
                Name = user.Name
            },
            Token = tokenBase64
        });
    }

    [HttpPost("logout")]
    public IActionResult Logout()
    {
        HttpContext.Session.Clear();
        return Ok(new { success = true, message = "Logout successful" });
    }

    [HttpGet("check")]
    public async Task<IActionResult> CheckSession()
    {
        // First, try session
        var userId = HttpContext.Session.GetInt32("UserId");
        var userName = HttpContext.Session.GetString("UserName");

        if (userId != null && userName != null)
        {
            return Ok(new
            {
                authenticated = true,
                user = new UserDto
                {
                    Id = userId.Value,
                    Name = userName
                }
            });
        }

        // If no session, try Authorization header token
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
                        // Restore session from token
                        HttpContext.Session.SetInt32("UserId", user.Id);
                        HttpContext.Session.SetString("UserName", user.Name);

                        return Ok(new
                        {
                            authenticated = true,
                            user = new UserDto
                            {
                                Id = user.Id,
                                Name = user.Name
                            }
                        });
                    }
                }
            }
            catch
            {
                // Invalid token format, continue to return false
            }
        }

        return Ok(new { authenticated = false });
    }
}

