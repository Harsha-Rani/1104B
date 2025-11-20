-- =========================================================
-- TEST: Verify F Rate Adjustment is Now FAST
-- =========================================================
-- Run this to see the performance improvement

-- Step 1: Setup test data
CREATE TABLE #FRateAdjustments (
    ReportDate DATE,
    oldFRate FLOAT,
    newFRate FLOAT
);

-- Insert your 3 report dates (change dates to match your actual data)
INSERT #FRateAdjustments VALUES 
('2024-01-15', 1.10, 1.15),
('2024-01-16', 1.15, 1.12),
('2024-01-17', 1.12, 1.18);

DECLARE @clientID INT = 1;  -- ✅ Change to your actual client ID

-- Step 2: Turn on performance monitoring
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- Step 3: Test query (SELECT first - don't UPDATE yet)
SELECT 
    COUNT(*) AS RowsToUpdate,
    MIN(ER.exch_rate) AS MinRate,
    MAX(ER.exch_rate) AS MaxRate,
    AVG(ER.exch_rate) AS AvgRate
FROM exchange_rates ER WITH(INDEX(IX_ExchangeRates_ClientDateSource))  -- Force your new index
INNER JOIN #FRateAdjustments FRA
    ON ER.ClientId = @clientID
   AND ER.report_date = FRA.ReportDate
WHERE ER.source <> 'F'
  AND ISNULL(ER.exch_rate, 0) <> 0
  AND FRA.newFRate IS NOT NULL
  AND FRA.oldFRate IS NOT NULL
  AND FRA.oldFRate <> FRA.newFRate;

-- Step 4: Turn off monitoring
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

-- Cleanup
DROP TABLE #FRateAdjustments;

-- =========================================================
-- 📊 READ THE RESULTS:
-- =========================================================
-- Look at the "Messages" tab in SSMS, you should see:
--
-- ✅ GOOD (Fast):
--   - SQL Server Execution Times:
--     CPU time = 0-50 ms, elapsed time = 10-200 ms
--   - Table 'exchange_rates'. Scan count 1-3
--   - logical reads = 10-500 (small number)
--
-- ❌ BAD (Slow - index not being used):
--   - CPU time = 1000+ ms, elapsed time = 5000+ ms
--   - Table 'exchange_rates'. Scan count 1
--   - logical reads = 50000+ (huge number)
--
-- If you see BAD results, the index is not being used!
-- Run the "Fix Index Not Being Used" script below.
-- =========================================================

PRINT '';
PRINT '========================================';
PRINT '✅ Performance test complete!';
PRINT '';
PRINT 'Check the Messages tab above:';
PRINT '  - CPU time should be < 100ms';
PRINT '  - Logical reads should be < 1000';
PRINT '  - If higher, see "Fix Index Not Being Used" section';
PRINT '========================================';
