using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BMReleaseManager.Migrations
{
    /// <inheritdoc />
    public partial class AddCustomerReleaseStages : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ReleaseStage",
                table: "VersionHistoryCustomers",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ReleaseStage",
                table: "VersionHistoryCustomers");
        }
    }
}
