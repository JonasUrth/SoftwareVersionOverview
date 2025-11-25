using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BMReleaseManager.Migrations
{
    /// <inheritdoc />
    public partial class AddIsActiveToCountriesSoftwareUsers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsActive",
                table: "Users",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsActive",
                table: "Softwares",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsActive",
                table: "Countries",
                type: "boolean",
                nullable: false,
                defaultValue: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsActive",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "IsActive",
                table: "Softwares");

            migrationBuilder.DropColumn(
                name: "IsActive",
                table: "Countries");
        }
    }
}
