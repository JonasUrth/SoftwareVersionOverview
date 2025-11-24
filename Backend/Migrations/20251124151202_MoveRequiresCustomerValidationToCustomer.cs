using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BMReleaseManager.Migrations
{
    /// <inheritdoc />
    public partial class MoveRequiresCustomerValidationToCustomer : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RequiresCustomerValidation",
                table: "Softwares");

            migrationBuilder.AddColumn<bool>(
                name: "RequiresCustomerValidation",
                table: "Customers",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RequiresCustomerValidation",
                table: "Customers");

            migrationBuilder.AddColumn<bool>(
                name: "RequiresCustomerValidation",
                table: "Softwares",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }
    }
}
