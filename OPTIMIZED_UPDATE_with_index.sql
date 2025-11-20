-- =========================================================
-- OPTIMIZED F Rate Adjustment UPDATE
-- Use this AFTER creating the index
-- =========================================================

-- ✅ Version 1: Your current query (now will be fast with index)
UPDATE ER
SET ER.exch_rate = CAST(ER.exch_rate * FRA.oldFRate / FRA.newFRate AS NUMERIC(38,15)),
    ER.version_date = SYSDATETIME(),
    ER.version_source = 'F-adjusted'
FROM exchange_rates ER WITH(ROWLOCK)  -- ✅ Added ROWLOCK for less blocking
INNER JOIN #FRateAdjustments FRA
    ON ER.report_date = FRA.ReportDate
   AND ER.ClientId = @clientID
WHERE ER.source <> 'F'
  AND ISNULL(ER.exch_rate, 0) <> 0
  AND FRA.newFRate IS NOT NULL
  AND FRA.oldFRate IS NOT NULL
  AND FRA.oldFRate <> FRA.newFRate;

SELECT @@ROWCOUNT AS RowsUpdated;

-- =========================================================
-- ✅ Version 2: Even FASTER (Forces index usage)
-- =========================================================
-- Use this if SQL Server doesn't automatically pick the index

UPDATE ER
SET ER.exch_rate = CAST(ER.exch_rate * FRA.oldFRate / FRA.newFRate AS NUMERIC(38,15)),
    ER.version_date = SYSDATETIME(),
    ER.version_source = 'F-adjusted'
FROM exchange_rates ER WITH(INDEX(IX_ExchangeRates_ClientDateSource), ROWLOCK)  -- ✅ Force index
INNER JOIN #FRateAdjustments FRA
    ON ER.ClientId = @clientID           -- ✅ ClientId first (matches index order)
   AND ER.report_date = FRA.ReportDate   -- ✅ report_date second
WHERE ER.source <> 'F'                    -- ✅ source third (in index)
  AND ER.exch_rate IS NOT NULL            -- ✅ Simplified condition
  AND ER.exch_rate <> 0
  AND FRA.newFRate IS NOT NULL
  AND FRA.oldFRate IS NOT NULL
  AND FRA.oldFRate <> FRA.newFRate
  AND ABS(ER.exch_rate * FRA.oldFRate / FRA.newFRate) <= 999999999;  -- ✅ Overflow protection

SELECT @@ROWCOUNT AS RowsUpdated;

-- =========================================================
-- ✅ Version 3: FASTEST for LARGE tables (Batch update)
-- =========================================================
-- Use this if you have millions of rows to update

DECLARE @BatchSize INT = 5000;
DECLARE @RowsUpdated INT = 1;
DECLARE @TotalUpdated INT = 0;

WHILE @RowsUpdated > 0
BEGIN
    UPDATE TOP (@BatchSize) ER
    SET ER.exch_rate = CAST(ER.exch_rate * FRA.oldFRate / FRA.newFRate AS NUMERIC(38,15)),
        ER.version_date = SYSDATETIME(),
        ER.version_source = 'F-adjusted'
    FROM exchange_rates ER WITH(INDEX(IX_ExchangeRates_ClientDateSource), ROWLOCK)
    INNER JOIN #FRateAdjustments FRA
        ON ER.ClientId = @clientID
       AND ER.report_date = FRA.ReportDate
    WHERE ER.source <> 'F'
      AND ER.exch_rate IS NOT NULL
      AND ER.exch_rate <> 0
      AND FRA.newFRate IS NOT NULL
      AND FRA.oldFRate IS NOT NULL
      AND FRA.oldFRate <> FRA.newFRate
      AND ABS(ER.exch_rate * FRA.oldFRate / FRA.newFRate) <= 999999999;
    
    SET @RowsUpdated = @@ROWCOUNT;
    SET @TotalUpdated = @TotalUpdated + @RowsUpdated;
    
    IF @RowsUpdated > 0
        PRINT 'Batch updated: ' + CAST(@RowsUpdated AS VARCHAR) + ' rows';
    
    WAITFOR DELAY '00:00:00.100';  -- 100ms pause between batches (reduces blocking)
END

PRINT '✅ Total rows updated: ' + CAST(@TotalUpdated AS VARCHAR);

-- =========================================================
-- Performance Comparison Test
-- =========================================================
-- Run this to see the speed difference

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- Create test data
CREATE TABLE #FRateAdjustments (
    ReportDate DATE,
    oldFRate FLOAT,
    newFRate FLOAT
);

INSERT #FRateAdjustments VALUES 
('2024-01-15', 1.10, 1.15),
('2024-01-16', 1.15, 1.12),
('2024-01-17', 1.12, 1.18);

DECLARE @clientID INT = 1;  -- Change to your client ID

-- Test query (to see speed without actually updating)
SELECT 
    COUNT(*) AS RowsToUpdate,
    MIN(ER.exch_rate) AS MinRate,
    MAX(ER.exch_rate) AS MaxRate
FROM exchange_rates ER WITH(INDEX(IX_ExchangeRates_ClientDateSource))
INNER JOIN #FRateAdjustments FRA
    ON ER.ClientId = @clientID
   AND ER.report_date = FRA.ReportDate
WHERE ER.source <> 'F'
  AND ER.exch_rate IS NOT NULL
  AND ER.exch_rate <> 0;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

DROP TABLE #FRateAdjustments;

-- Look at the output:
-- - "Table 'exchange_rates'. Scan count should be 1 or small number
-- - "logical reads" should be SMALL (hundreds, not thousands)
-- - "CPU time" and "elapsed time" should be < 100ms for 3 dates
