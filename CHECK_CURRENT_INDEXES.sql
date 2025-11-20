-- =========================================================
-- Check Current Indexes on exchange_rates Table
-- =========================================================
-- Run this first to see what indexes you already have

USE [YourDatabaseName]  -- Change to your database
GO

-- ===== Part 1: List ALL indexes =====
SELECT 
    '🔍 Current Indexes' AS Info,
    i.index_id,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_primary_key AS IsPrimaryKey,
    i.is_unique AS IsUnique,
    i.fill_factor AS FillFactor,
    -- Key columns
    STUFF((
        SELECT ', ' + c.name + 
            CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS KeyColumns,
    -- Included columns
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH('')
    ), 1, 2, '') AS IncludedColumns,
    ps.row_count AS ApproxRowCount,
    ps.reserved_page_count * 8 / 1024.0 AS IndexSizeMB
FROM sys.indexes i
LEFT JOIN sys.dm_db_partition_stats ps 
    ON i.object_id = ps.object_id 
   AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID('exchange_rates')
  AND i.type_desc <> 'HEAP'  -- Exclude heap
ORDER BY i.index_id;

-- ===== Part 2: Check if recommended index exists =====
IF EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE object_id = OBJECT_ID('exchange_rates') 
      AND name = 'IX_ExchangeRates_ClientDateSource'
)
BEGIN
    PRINT '✅ GOOD: Recommended index IX_ExchangeRates_ClientDateSource already exists!';
    PRINT '   Your UPDATE should be fast.';
END
ELSE
BEGIN
    PRINT '❌ PROBLEM: Index IX_ExchangeRates_ClientDateSource does NOT exist!';
    PRINT '   CREATE IT NOW for better performance!';
    PRINT '';
    PRINT 'Run this command:';
    PRINT 'CREATE NONCLUSTERED INDEX IX_ExchangeRates_ClientDateSource';
    PRINT 'ON exchange_rates(ClientId, report_date, source)';
    PRINT 'INCLUDE (exch_rate, exch_rate_id)';
    PRINT 'WITH (ONLINE = ON, FILLFACTOR = 90);';
END

-- ===== Part 3: Check index usage statistics =====
SELECT 
    '📊 Index Usage Stats' AS Info,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ius.user_seeks AS Seeks,
    ius.user_scans AS Scans,
    ius.user_lookups AS Lookups,
    ius.user_updates AS Updates,
    ius.last_user_seek AS LastSeek,
    ius.last_user_scan AS LastScan,
    CASE 
        WHEN ius.user_seeks + ius.user_scans + ius.user_lookups = 0 
        THEN '⚠️ UNUSED'
        WHEN ius.user_updates > (ius.user_seeks + ius.user_scans + ius.user_lookups) * 10
        THEN '⚠️ Overhead (more updates than reads)'
        ELSE '✅ Used'
    END AS Status
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius
    ON i.object_id = ius.object_id
   AND i.index_id = ius.index_id
   AND ius.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID('exchange_rates')
  AND i.type_desc <> 'HEAP'
ORDER BY 
    ius.user_seeks + ius.user_scans + ius.user_lookups DESC;

-- ===== Part 4: Missing index suggestions from SQL Server =====
SELECT DISTINCT
    '💡 SQL Server Recommends' AS Info,
    mid.statement AS TableName,
    migs.avg_user_impact AS AvgImpact_Percent,
    migs.user_seeks AS Seeks,
    migs.user_scans AS Scans,
    'CREATE NONCLUSTERED INDEX IX_ExchangeRates_Missing_' + 
        CAST(mid.index_handle AS VARCHAR) + 
        ' ON ' + mid.statement + 
        ' (' + ISNULL(mid.equality_columns, '') + 
        CASE 
            WHEN mid.inequality_columns IS NOT NULL 
            THEN CASE WHEN mid.equality_columns IS NOT NULL THEN ', ' ELSE '' END + mid.inequality_columns 
            ELSE '' 
        END + ')' +
        CASE 
            WHEN mid.included_columns IS NOT NULL 
            THEN ' INCLUDE (' + mid.included_columns + ')' 
            ELSE '' 
        END + ';' AS RecommendedIndexSQL
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig 
    ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs 
    ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID()
  AND mid.object_id = OBJECT_ID('exchange_rates')
  AND migs.avg_user_impact > 20  -- Only show high-impact indexes
ORDER BY migs.avg_user_impact DESC;

-- ===== Part 5: Table size and row count =====
SELECT 
    '📈 Table Statistics' AS Info,
    t.name AS TableName,
    p.rows AS RowCount,
    SUM(a.total_pages) * 8 / 1024.0 AS TotalSizeMB,
    SUM(a.used_pages) * 8 / 1024.0 AS UsedSizeMB,
    SUM(a.data_pages) * 8 / 1024.0 AS DataSizeMB,
    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024.0 AS UnusedSizeMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name = 'exchange_rates'
  AND i.index_id <= 1  -- Clustered index or heap only
GROUP BY t.name, p.rows;

-- ===== Part 6: Column data types (important for NUMERIC overflow) =====
SELECT 
    '🔢 Column Definitions' AS Info,
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    CASE 
        WHEN t.name = 'numeric' OR t.name = 'decimal' 
        THEN t.name + '(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')'
        WHEN t.name IN ('varchar', 'nvarchar', 'char', 'nchar')
        THEN t.name + '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR) END + ')'
        ELSE t.name
    END AS FullDataType
FROM sys.columns c
INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('exchange_rates')
  AND c.name IN ('exch_rate', 'exch_rate_id', 'ClientId', 'report_date', 'source', 'curr_id')
ORDER BY c.column_id;

PRINT '';
PRINT '========================================';
PRINT '✅ Analysis complete!';
PRINT '========================================';
