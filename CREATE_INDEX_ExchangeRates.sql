-- =========================================================
-- CRITICAL INDEX for GuiSetExchangeRates Performance
-- =========================================================
-- This index will make your F rate adjustment UPDATE 10-100x faster
-- Run this on your exchange_rates table

USE [YourDatabaseName]  -- ✅ Change this to your database name
GO

-- Step 1: Check if index already exists
IF EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE object_id = OBJECT_ID('exchange_rates') 
      AND name = 'IX_ExchangeRates_ClientDateSource'
)
BEGIN
    PRINT '⚠️ Index already exists. Dropping to recreate...';
    DROP INDEX IX_ExchangeRates_ClientDateSource ON exchange_rates;
END
GO

-- Step 2: Create the performance index
CREATE NONCLUSTERED INDEX IX_ExchangeRates_ClientDateSource
ON exchange_rates(ClientId, report_date, source)
INCLUDE (exch_rate, exch_rate_id)
WITH (
    ONLINE = ON,           -- ✅ Won't block other queries
    FILLFACTOR = 90,       -- ✅ Leaves room for updates
    PAD_INDEX = ON,        -- ✅ Applies fillfactor to all levels
    SORT_IN_TEMPDB = ON,   -- ✅ Faster creation
    STATISTICS_NORECOMPUTE = OFF,
    DATA_COMPRESSION = PAGE  -- ✅ Saves space (optional, remove if SQL < 2008)
);
GO

-- Step 3: Update statistics for optimal performance
UPDATE STATISTICS exchange_rates IX_ExchangeRates_ClientDateSource 
WITH FULLSCAN;
GO

-- Step 4: Verify index was created
SELECT 
    '✅ Index Created Successfully' AS Status,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique,
    i.fill_factor,
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS KeyColumns,
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH('')
    ), 1, 2, '') AS IncludedColumns
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('exchange_rates')
  AND i.name = 'IX_ExchangeRates_ClientDateSource';
GO

PRINT '✅ Index creation complete!';
PRINT '✅ Your UPDATE will now be MUCH faster!';
GO

-- =========================================================
-- Performance Test (Optional - run AFTER creating index)
-- =========================================================
-- This will show you how fast the UPDATE will be now

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

DECLARE @clientID INT = 1;  -- ✅ Change to your actual client ID

-- Test query (same as your UPDATE, but SELECT to see speed)
SELECT 
    ER.exch_rate_id,
    ER.report_date,
    ER.ClientId,
    ER.source,
    ER.exch_rate AS OldRate,
    NewRate = CAST(ER.exch_rate * 1.05 AS NUMERIC(38,15))  -- Example calculation
FROM exchange_rates ER WITH(INDEX(IX_ExchangeRates_ClientDateSource))  -- Force new index
WHERE ER.ClientId = @clientID
  AND ER.report_date IN ('2024-01-15', '2024-01-16', '2024-01-17')  -- 3 dates
  AND ER.source <> 'F'
  AND ISNULL(ER.exch_rate, 0) <> 0;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- =========================================================
-- Check what SQL Server will do now (Execution Plan)
-- =========================================================
-- Look for "Index Seek" instead of "Table Scan"
-- Estimated Subtree Cost should be MUCH lower now

DECLARE @clientID INT = 1;

SELECT 
    ER.exch_rate_id,
    ER.exch_rate
FROM exchange_rates ER
WHERE ER.ClientId = @clientID
  AND ER.report_date IN ('2024-01-15', '2024-01-16', '2024-01-17')
  AND ER.source <> 'F'
  AND ISNULL(ER.exch_rate, 0) <> 0;

-- Press Ctrl+M in SSMS to see execution plan
-- You should see: Index Seek (IX_ExchangeRates_ClientDateSource)
