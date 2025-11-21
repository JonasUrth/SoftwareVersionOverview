using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BMReleaseManager.Migrations
{
    /// <inheritdoc />
    public partial class AddStatusTrackingFieldsToVersionHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PreReleaseById",
                table: "VersionHistories",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "PreReleaseDate",
                table: "VersionHistories",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ProductionReadyById",
                table: "VersionHistories",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ProductionReadyDate",
                table: "VersionHistories",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ReleasedStatusById",
                table: "VersionHistories",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ReleasedStatusDate",
                table: "VersionHistories",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_VersionHistories_PreReleaseById",
                table: "VersionHistories",
                column: "PreReleaseById");

            migrationBuilder.CreateIndex(
                name: "IX_VersionHistories_ProductionReadyById",
                table: "VersionHistories",
                column: "ProductionReadyById");

            migrationBuilder.CreateIndex(
                name: "IX_VersionHistories_ReleasedStatusById",
                table: "VersionHistories",
                column: "ReleasedStatusById");

            migrationBuilder.AddForeignKey(
                name: "FK_VersionHistories_Users_PreReleaseById",
                table: "VersionHistories",
                column: "PreReleaseById",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_VersionHistories_Users_ProductionReadyById",
                table: "VersionHistories",
                column: "ProductionReadyById",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_VersionHistories_Users_ReleasedStatusById",
                table: "VersionHistories",
                column: "ReleasedStatusById",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_VersionHistories_Users_PreReleaseById",
                table: "VersionHistories");

            migrationBuilder.DropForeignKey(
                name: "FK_VersionHistories_Users_ProductionReadyById",
                table: "VersionHistories");

            migrationBuilder.DropForeignKey(
                name: "FK_VersionHistories_Users_ReleasedStatusById",
                table: "VersionHistories");

            migrationBuilder.DropIndex(
                name: "IX_VersionHistories_PreReleaseById",
                table: "VersionHistories");

            migrationBuilder.DropIndex(
                name: "IX_VersionHistories_ProductionReadyById",
                table: "VersionHistories");

            migrationBuilder.DropIndex(
                name: "IX_VersionHistories_ReleasedStatusById",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "PreReleaseById",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "PreReleaseDate",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "ProductionReadyById",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "ProductionReadyDate",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "ReleasedStatusById",
                table: "VersionHistories");

            migrationBuilder.DropColumn(
                name: "ReleasedStatusDate",
                table: "VersionHistories");
        }
    }
}
