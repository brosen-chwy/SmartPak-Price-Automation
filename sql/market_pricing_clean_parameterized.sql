-- SQL Server: connect to livereporting; workbook default database is SPDW.
-- Reproduces the Market Pricing Clean model query with an explicit ingestion date.
-- Intentional changes from the original: parameterized date and half-open timestamp filter.
-- Price is intentionally kept in its source type to preserve the clean worksheet.
-- This SELECT has not been executed against the live SQL Server.
DECLARE @AsOfDate date = '2026-09-14';

;WITH marketpricing AS
(
    SELECT
        sku - 990000000000 AS skuid,
        Name AS name,
        competitor,
        CASE WHEN price = '' THEN NULL ELSE price END AS price,
        availability,
        seller
    FROM SPDW_ODS.Mktg.tblChewyConsolidatedPricing
    WHERE EDWCreatedDateTime >= @AsOfDate
      AND EDWCreatedDateTime < DATEADD(day, 1, @AsOfDate)
      AND sku NOT LIKE '%-%'
)
SELECT DISTINCT skuid, name, competitor, price, availability, seller
FROM marketpricing
WHERE availability = 1
  AND price <> ''
  AND competitor IN
  (
      'amazon', 'bigdweb', 'corroshop', 'farmandfleet', 'horse',
      'jefferspet', 'nrs', 'ridingwarehouse', 'statelinetack',
      'tractorsupply', 'valleyvet'
  );

-- Expected 2026-09-14 saved-workbook baseline:
-- Raw: 17,918 rows; in stock: 14,684; in stock/nonblank price: 14,672;
-- approved competitors before DISTINCT: 11,887; final DISTINCT: 4,115;
-- final distinct SKUs: 1,107.
-- Retained database history is required to reproduce a prior ingestion date.
-- No ORDER BY exists in the original query: worksheet row positions are not stable IDs.
