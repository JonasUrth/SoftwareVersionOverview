-- SQL query to export firmware releases with LEFT JOINs to include ALL rows
-- This ensures all EPROMM_VERSIONS rows are included, even when:
-- - Version IDs don't exist in the related tables (999 or any other invalid ID)
-- - Version reference fields are NULL
-- NULL values in xxx_CHANGES fields are fine and will be handled by the import

SELECT 
    c.Customer_Name as contry, 
    e.Changed, 
    e.Name as user_name, 
    CPU.CCPU_VER as CCPU, 
    CPU.CCPU_CHANGES, 
    DCPU_.DCPU_VER as DCPU, 
    DCPU_.DCPU_CHANGES, 
    X010_.X010T_VERSIONS as X010, 
    X010_.X010T_CHANGES, 
    X200.X200T_VERSIONS as x200_flash_turbe, 
    X200.X200T_CHANGES, 
    RCPU_.RCPU_VER as RCPU, 
    RCPU_.RCPU_CHANGES
FROM 
    EPROMM_VERSIONS e
    INNER JOIN customer c ON c.ID = e.Customer_ID
    -- Use LEFT JOIN and check if ID exists in the table (not NULL and not 999)
    -- This will return NULL for CCPU fields if ID doesn't exist or is 999
    LEFT JOIN CCPU_VERSIONS CPU ON CPU.ID = e.CCPU_ID 
        AND e.CCPU_ID IS NOT NULL 
        AND e.CCPU_ID != 999
    LEFT JOIN DCPU_VERSIONS DCPU_ ON DCPU_.ID = e.DCPU_ID 
        AND e.DCPU_ID IS NOT NULL 
        AND e.DCPU_ID != 999
    LEFT JOIN MCPU_X010T_VERSIONS X010_ ON X010_.ID = e.MCPU_X010T_ID 
        AND e.MCPU_X010T_ID IS NOT NULL 
        AND e.MCPU_X010T_ID != 999
    LEFT JOIN MCPU_X200T_VERSIONS X200 ON X200.ID = e.MCPU_X200T_ID 
        AND e.MCPU_X200T_ID IS NOT NULL 
        AND e.MCPU_X200T_ID != 999
    LEFT JOIN RCPU_VERSIONS RCPU_ ON RCPU_.ID = e.RCPU_ID 
        AND e.RCPU_ID IS NOT NULL 
        AND e.RCPU_ID != 999
ORDER BY 
    c.Customer_Name, 
    e.Changed;

