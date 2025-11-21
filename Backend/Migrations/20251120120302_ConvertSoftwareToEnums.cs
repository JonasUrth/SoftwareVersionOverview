using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BMReleaseManager.Migrations
{
    /// <inheritdoc />
    public partial class ConvertSoftwareToEnums : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // First, convert existing string values to enum integers
            // SoftwareType: Firmware = 0, Windows = 1
            migrationBuilder.Sql(@"
                UPDATE ""Softwares"" 
                SET ""Type"" = CASE 
                    WHEN LOWER(""Type"") = 'firmware' THEN '0'
                    WHEN LOWER(""Type"") = 'windows' THEN '1'
                    ELSE '0'
                END
            ");

            // ReleaseMethod: FindFile = 0, CreateCD = 1
            migrationBuilder.Sql(@"
                UPDATE ""Softwares"" 
                SET ""ReleaseMethod"" = CASE 
                    WHEN LOWER(""ReleaseMethod"") IN ('find file', 'findfile') THEN '0'
                    WHEN LOWER(""ReleaseMethod"") IN ('create cd', 'createcd') THEN '1'
                    ELSE NULL
                END
                WHERE ""ReleaseMethod"" IS NOT NULL
            ");

            // Now alter the column types with USING clause for PostgreSQL
            migrationBuilder.Sql(@"ALTER TABLE ""Softwares"" ALTER COLUMN ""Type"" TYPE integer USING ""Type""::integer");
            migrationBuilder.Sql(@"ALTER TABLE ""Softwares"" ALTER COLUMN ""ReleaseMethod"" TYPE integer USING ""ReleaseMethod""::integer");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "Type",
                table: "Softwares",
                type: "text",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "integer");

            migrationBuilder.AlterColumn<string>(
                name: "ReleaseMethod",
                table: "Softwares",
                type: "text",
                nullable: true,
                oldClrType: typeof(int),
                oldType: "integer",
                oldNullable: true);
        }
    }
}
