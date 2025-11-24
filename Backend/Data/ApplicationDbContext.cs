using Microsoft.EntityFrameworkCore;
using BMReleaseManager.Models;

namespace BMReleaseManager.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Country> Countries { get; set; }
    public DbSet<Customer> Customers { get; set; }
    public DbSet<User> Users { get; set; }
    public DbSet<Software> Softwares { get; set; }
    public DbSet<VersionHistory> VersionHistories { get; set; }
    public DbSet<HistoryNote> HistoryNotes { get; set; }
    public DbSet<VersionHistoryCustomer> VersionHistoryCustomers { get; set; }
    public DbSet<HistoryNoteCustomer> HistoryNoteCustomers { get; set; }
    public DbSet<AuditLog> AuditLogs { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Country configuration
        modelBuilder.Entity<Country>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).IsRequired();
        });

        // Customer configuration
        modelBuilder.Entity<Customer>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).IsRequired();
            entity.Property(e => e.IsActive).IsRequired().HasDefaultValue(true);
            entity.Property(e => e.RequiresCustomerValidation).IsRequired().HasDefaultValue(false);
            
            entity.HasOne(e => e.Country)
                .WithMany(c => c.Customers)
                .HasForeignKey(e => e.CountryId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // User configuration
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).IsRequired();
            entity.HasIndex(e => e.Name).IsUnique();
            entity.Property(e => e.Password).IsRequired();
        });

        // Software configuration
        modelBuilder.Entity<Software>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).IsRequired();
            entity.Property(e => e.Type).IsRequired();
        });

        // VersionHistory configuration
        modelBuilder.Entity<VersionHistory>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Version).IsRequired();
            entity.Property(e => e.ReleaseDate).IsRequired();
            entity.Property(e => e.ReleaseStatus).IsRequired();

            // Unique constraint on (Version, SoftwareId)
            entity.HasIndex(e => new { e.Version, e.SoftwareId }).IsUnique();

            entity.HasOne(e => e.Software)
                .WithMany(s => s.VersionHistories)
                .HasForeignKey(e => e.SoftwareId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(e => e.ReleasedBy)
                .WithMany(u => u.VersionHistories)
                .HasForeignKey(e => e.ReleasedById)
                .OnDelete(DeleteBehavior.Restrict);

            // Optional foreign keys for status tracking
            entity.HasOne(e => e.PreReleaseBy)
                .WithMany()
                .HasForeignKey(e => e.PreReleaseById)
                .OnDelete(DeleteBehavior.Restrict)
                .IsRequired(false);

            entity.HasOne(e => e.ReleasedStatusBy)
                .WithMany()
                .HasForeignKey(e => e.ReleasedStatusById)
                .OnDelete(DeleteBehavior.Restrict)
                .IsRequired(false);

            entity.HasOne(e => e.ProductionReadyBy)
                .WithMany()
                .HasForeignKey(e => e.ProductionReadyById)
                .OnDelete(DeleteBehavior.Restrict)
                .IsRequired(false);
        });

        // HistoryNote configuration
        modelBuilder.Entity<HistoryNote>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Note).IsRequired();

            entity.HasOne(e => e.VersionHistory)
                .WithMany(v => v.HistoryNotes)
                .HasForeignKey(e => e.VersionHistoryId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        // VersionHistoryCustomer configuration (junction table)
        modelBuilder.Entity<VersionHistoryCustomer>(entity =>
        {
            entity.HasKey(e => e.Id);
            
            // Unique constraint on (VersionHistoryId, CustomerId)
            entity.HasIndex(e => new { e.VersionHistoryId, e.CustomerId }).IsUnique();

            entity.HasOne(e => e.VersionHistory)
                .WithMany(v => v.VersionHistoryCustomers)
                .HasForeignKey(e => e.VersionHistoryId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Customer)
                .WithMany(c => c.VersionHistoryCustomers)
                .HasForeignKey(e => e.CustomerId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // HistoryNoteCustomer configuration (junction table)
        modelBuilder.Entity<HistoryNoteCustomer>(entity =>
        {
            entity.HasKey(e => e.Id);
            
            // Unique constraint on (HistoryNoteId, CustomerId)
            entity.HasIndex(e => new { e.HistoryNoteId, e.CustomerId }).IsUnique();

            entity.HasOne(e => e.HistoryNote)
                .WithMany(n => n.HistoryNoteCustomers)
                .HasForeignKey(e => e.HistoryNoteId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Customer)
                .WithMany(c => c.HistoryNoteCustomers)
                .HasForeignKey(e => e.CustomerId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // AuditLog configuration
        modelBuilder.Entity<AuditLog>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Timestamp).IsRequired();
            entity.Property(e => e.EntityType).IsRequired();
            entity.Property(e => e.EntityId).IsRequired();
            entity.Property(e => e.Action).IsRequired();

            entity.HasOne(e => e.User)
                .WithMany()
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.SetNull);
        });
    }
}


