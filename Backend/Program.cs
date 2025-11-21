using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Data;

var builder = WebApplication.CreateBuilder(args);

// Add Windows Service support
builder.Services.AddWindowsService();

// Add services to the container
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        // Serialize enums as strings instead of integers
        options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Configure PostgreSQL with Entity Framework Core
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Configure session management for authentication
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromHours(8);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
    options.Cookie.Name = ".BMReleaseManager.Session";
    options.Cookie.SameSite = SameSiteMode.None; // Required for CORS
    options.Cookie.SecurePolicy = CookieSecurePolicy.None; // For localhost testing (use Secure in production)
});

// Configure CORS to allow frontend access
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowElmSpa", policy =>
    {
        policy.WithOrigins("http://localhost:8000", "http://localhost:1234")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Don't use HTTPS redirection for local company network deployment
// app.UseHttpsRedirection();

app.UseCors("AllowElmSpa");
app.UseSession();
app.MapControllers();

app.Run();
