/*
SmartPak pricing candidate query — SQL Server, run on livereporting / SPDW.
OutputMode UPLOAD: exactly ProductID, New OTS Price, New ATS Price.
OutputMode REVIEW: all scoped candidates with exclusion reasons.
Inventory eligibility deliberately omitted. Cost gate checks rounded OTS only.
MAP-restriction eligibility is also deferred for this team test; review before uploads.

Team-test version: uses daily warehouse RetailPricePerUnit, NOT a live-site price.
Warehouse prices refresh daily; competitor data is loaded on Tuesdays.
Explicit competitor snapshot below is pinned for testing; update after a completed load.
No SPE_Local connection or linked server is required.
Unresolved SKU conflicts are excluded. Kit products and unknown kit status are excluded.
3P SmartPaks require confirmed cost and current OTS on the same 28-day basis.
Known SOP holds are below; refresh these lists before operational use.
No permanent tables or prices are updated. This script has NOT run on live SQL Server.
*/
USE [SPDW];
SET NOCOUNT ON;

DECLARE @RunAt datetime = GETDATE();
-- Latest common snapshot confirmed by the team. This date does not auto-advance.
-- After Tuesday's load completes, set this to the date present in BOTH feeds.
DECLARE @AsOfDate date = '20260908';
DECLARE @OutputMode varchar(6) = 'REVIEW'; -- REVIEW for testing; UPLOAD for template columns

-- Add authoritative manual holds here. The four known problem SKUs are in the SOP/workbook.
DECLARE @SkuHolds TABLE (ProductID bigint PRIMARY KEY, Reason nvarchar(200));
INSERT @SkuHolds VALUES
 (2109838434,N'SOP: RedBarn 12-inch bully stick pricing defect'),
 (2109686160,N'SOP: Horse Nibbles outlier competitor price'),
 (2109770766,N'SOP: Stud Muffin Slim flavor mismatch'),
 (2109713311,N'Workbook: Ulcergard pricing defect');

-- Kit products are excluded while kit mappings are unavailable.

-- Populate only after confirming both values use the same 28-day product basis.
DECLARE @SmartPakBasis TABLE
 (ProductID bigint PRIMARY KEY, UnitCost28Days decimal(19,6), CurrentOTS28Days decimal(19,6));
-- INSERT @SmartPakBasis VALUES (<SmartPak SKU>, <28-day cost>, <current 28-day OTS>);

DECLARE @SupplierHolds TABLE (Cohort varchar(20), SupplierName nvarchar(200));
INSERT @SupplierHolds VALUES
 ('Consumables',N'Med-Vet Pharmaceuticals (MVP)'),
 ('Consumables',N'W.F. Young, Inc.'),
 ('Consumables',N'Auburn Laboratories Inc'),
 ('Consumables',N'Biozyme/Cogent Solutions'),
 ('Consumables',N'Biozyme/Cogent Solutions (SmartPak Equine)'),
 ('Consumables',N'Boehringer Ingelheim'),
 ('Consumables',N'Grand Meadows'),
 ('Consumables',N'Perfect Products LLC'),
 ('Consumables',N'Equiade'),
 ('Consumables',N'Mrs. Pastures Cookies for Horses'),
 ('Consumables',N'Nutramax Laboratories'),
 ('Hardgoods',N'Farnam Companies, Inc.'),
 ('Hardgoods',N'Professional''s Choice'),
 ('Hardgoods',N'W.F. Young, Inc.'),
 ('Hardgoods',N'Wishing Well Services Ltd.');

IF @OutputMode NOT IN ('UPLOAD','REVIEW')
    THROW 51000, 'OutputMode must be UPLOAD or REVIEW.', 1;
DROP TABLE IF EXISTS #SPPriceLive;
DROP TABLE IF EXISTS #SPPriceSku;
DROP TABLE IF EXISTS #SPPriceDecisions;
-- Retain the internal Live/ComputedPrice names to keep downstream rules unchanged.
-- Their values now represent CURRENT WAREHOUSE prices, not SPE_Local prices.
-- SKUID is the upload identifier; DimProductSKU.ProductID is a different key.
-- RowCurrentFlag selects the current warehouse version; dates do not prove freshness.
CREATE TABLE #SPPriceLive (ProductID bigint, ComputedPrice decimal(19,6));
INSERT INTO #SPPriceLive(ProductID,ComputedPrice)
SELECT TRY_CONVERT(bigint,SKUID),TRY_CONVERT(decimal(19,6),RetailPricePerUnit)
FROM SPDW.core.DimProductSKU
WHERE RowCurrentFlag=1;

IF NOT EXISTS(SELECT 1 FROM #SPPriceLive)
    THROW 51003, 'Current warehouse price source returned no rows.', 1;
IF NOT EXISTS(SELECT 1 FROM SPDW_ODS.Mktg.tblChewyConsolidatedPricing
              WHERE EDWCreatedDateTime>=@AsOfDate AND EDWCreatedDateTime<DATEADD(day,1,@AsOfDate))
    THROW 51004, 'No market pricing ingestion exists for the requested date.', 1;
IF NOT EXISTS(SELECT 1 FROM SPDW_ODS.Mktg.tblChewyPricingComp
              WHERE AsOfDate>=@AsOfDate AND AsOfDate<DATEADD(day,1,@AsOfDate))
    THROW 51005, 'No Chewy pricing snapshot exists for the requested date.', 1;

-- Sales lookback uses @RunAt; both competitor feeds use the explicit @AsOfDate.
-- The original unused finalmarketprice CTE is retained to minimize source changes.
;with #sales
as
(
 select y.*, gross, net, qty, cogs, ats_qty, ots_qty
 --into #sales
 from
(select distinct skuid, skuname, RetailPricePerUnit, dps.AutoshipRetailPrice, dps.RetailCostperUnit, ProductStockType, productgroup, productcategory, BuyerName, AutoShipEligibleFlag, SKUInactiveFlag, SupplierName, ProductKitFlag
, case when LabelClassification = 'Exclusive' then '3rd Party' else labelclassification end as labelclassification
, segment, subsegment, mapretailprice
from core.dimproductsku dps
where RowCurrentFlag = 1) y
left join

(
select skuid,  sum(productamount) gross, sum(netproductamount) net, sum(orderedquantity) qty, sum(cogsamount) cogs
, sum(case when priceoffertypename = 'AutoShip Price' then orderedquantity else 0 end) as ATS_qty
, sum(case when priceoffertypename = 'OneTimeShip Price' then orderedquantity else 0 end) as OTS_qty
from sales.factsalesdetail fsd
join core.dimproductsku dps on dps.ProductSKUKey = fsd.productskukey
join core.dimdate dd on dd.DateKey = fsd.OrderDateKey
where demandflag = 1
and freeitem = 0
and productcategory not like '%Gift%Card%'
and fulldate between dateadd(year,-1, dateadd(day, -1,@RunAt)) and dateadd(day, -1,@RunAt)
group by skuid
) x on y.skuid = x.SKUID

--order by gross desc
)

,
--create market pricing table from file
#marketpricing AS
(
    SELECT
        TRY_CONVERT(
            bigint,
            NULLIF(LTRIM(RTRIM(CONVERT(varchar(100), sku))), '')
        ) - 990000000000 AS skuid,

        Name,
        competitor,

        TRY_CONVERT(
            decimal(19, 4),
            NULLIF(LTRIM(RTRIM(CONVERT(varchar(100), price))), '')
        ) AS price,

        availability,
        seller
    FROM SPDW_ODS.Mktg.tblChewyConsolidatedPricing
    WHERE EDWCreatedDateTime>=@AsOfDate
      AND EDWCreatedDateTime<DATEADD(day,1,@AsOfDate)
      AND CONVERT(varchar(100), sku) NOT LIKE '%-%'
)
,
#chewypricing as

  --create chewy pricing table from file
(
select *
--into #chewypricing
from spdw_ods.mktg.tblchewypricingcomp cpc
where AsOfDate>=@AsOfDate AND AsOfDate<DATEADD(day,1,@AsOfDate)
)
,
#pricing AS
(
    SELECT
        CASE
            WHEN c.SmartPakSkuNumber IS NOT NULL THEN
                TRY_CONVERT(
                    bigint,
                    NULLIF(
                        LTRIM(RTRIM(
                            CONVERT(varchar(100), c.SmartPakSkuNumber)
                        )),
                        ''
                    )
                )
            ELSE m.skuid
        END AS skuid,

        TRY_CONVERT(
            decimal(19, 4),
            NULLIF(
                LTRIM(RTRIM(CONVERT(varchar(100), c.ChewyPrice))),
                ''
            )
        ) AS ChewyPrice,

        m.min_price_instock_focus_comp,
        m.min_price_instock,
        m.min_price_all,
        m.instock_focuscomp,
        m.instock_comp,
        m.all_comp
    FROM
    (
        SELECT DISTINCT
            SmartPakSkuNumber,
            ChewyPrice
        FROM #chewypricing
    ) AS c
    FULL OUTER JOIN
    (
        SELECT
            a.skuid,
            a.min_price AS min_price_all,
            a.competitors AS all_comp,
            b.min_price AS min_price_instock,
            b.competitors AS instock_comp,
            fc.min_price AS min_price_instock_focus_comp,
            fc.competitors AS instock_focuscomp
        FROM
        (
            SELECT
                skuid,
                MIN(price) AS min_price,
                COUNT(DISTINCT competitor) AS competitors
            FROM #marketpricing
            WHERE price IS NOT NULL
            GROUP BY skuid
        ) AS a
        LEFT JOIN
        (
            SELECT
                skuid,
                MIN(price) AS min_price,
                COUNT(DISTINCT competitor) AS competitors
            FROM #marketpricing
            WHERE TRY_CONVERT(int, Availability) = 1
            GROUP BY skuid
        ) AS b
            ON a.skuid = b.skuid
        LEFT JOIN
        (
            SELECT
                skuid,
                MIN(price) AS min_price,
                COUNT(DISTINCT competitor) AS competitors
            FROM #marketpricing
            WHERE TRY_CONVERT(int, Availability) = 1
              AND competitor IN
              (
                  'amazon',
                  'bigdweb',
                  'corroshop',
                  'farmandfleet',
                  'horse',
                  'jefferspet',
                  'nrs',
                  'ridingwarehouse',
                  'statelinetack',
                  'tractorsupply',
                  'valleyvet'
              )
            GROUP BY skuid
        ) AS fc
            ON b.skuid = fc.skuid
    ) AS m
        ON TRY_CONVERT(
               bigint,
               NULLIF(
                   LTRIM(RTRIM(
                       CONVERT(varchar(100), c.SmartPakSkuNumber)
                   )),
                   ''
               )
           ) = m.skuid
)
,

#finalmarketprice as
(

--sku level analysis


select x.*
,
case when match_type not like '%Kit%' then

   case when RetailPriceperUnit > 1.00*Market_Price then 'Above'
     when RetailPriceperUnit < 1.00*Market_Price then 'Below'
     when RetailPriceperUnit between 1.00*Market_Price and 1.00*Market_Price then 'At'
     else 'Unknown' end

  when match_type like '%Kit%' then

  case when x.anchor_sku_sp_price > 1.00*Market_Price then 'Above'
     when x.anchor_sku_sp_price < 1.00*Market_Price then 'Below'
     when x.anchor_sku_sp_price between 1.00*Market_Price and 1.00*Market_Price then 'At'
     else 'Unknown' end

   else null end
   as Market_Position
,
case when market_price = 0 then null
  when match_type not like '%Kit%' then
  retailpriceperunit/market_price -1

  when match_type like '%Kit%' then
  x.anchor_sku_sp_price/market_price -1

   else null end
   as Market_Price_Variance

, .95*Market_Price as Market_ATS_Price


from
(

select s.*
, case when p.chewyprice is not null then 'Match to Chewy'
  when p.min_price_instock_focus_comp is not null then 'Market Price'
  when p.min_price_instock is not null then 'Market Price All Retailers'
  when p.min_price_all is not null then 'Market Price inc OOS All Retailers'
  else 'No Match' end as Match_Type
, case when p.chewyprice is not null then p.chewyprice
  when p.min_price_instock_focus_comp is not null then p.min_price_instock_focus_comp
  when p.min_price_instock is not null then p.min_price_instock
  when p.min_price_all is not null then p.min_price_all
  else null end as Market_Price
, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then p.instock_focuscomp
  when p.min_price_instock is not null then p.instock_comp
  when p.min_price_all is not null then p.all_comp
  else null end as Competitor_Count

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then 1
  when p.min_price_instock is not null then 0
  when p.min_price_all is not null then 0
  else 0 end as For_Action

,CAST(NULL AS decimal(19,6)) as kit_quantity
, CAST(NULL AS decimal(19,6)) as anchor_sku_sp_price
from #sales s

left join #pricing p on s.SKUID = p.skuid
-- Kit-component matching deferred; no reporting kit-table dependency.

where gross is not null
and skuinactiveflag = 0
)
x
)
, FinalSku AS (
select x.*
,
case when match_type not like '%Kit%' then

   case when RetailPriceperUnit > 1.001*Market_Price then 'Above'
     when RetailPriceperUnit < .999*Market_Price then 'Below'
     when RetailPriceperUnit between .999*Market_Price and 1.001*Market_Price then 'At'
     else 'Unknown' end

  when match_type like '%Kit%' then

  case when x.anchor_sku_sp_price > 1.001*Market_Price then 'Above'
     when x.anchor_sku_sp_price < .999*Market_Price then 'Below'
     when x.anchor_sku_sp_price between .999*Market_Price and 1.001*Market_Price then 'At'
     else 'Unknown' end

   else null end
   as Market_Position
,
case when market_price = 0 then null
  when match_type not like '%Kit%' then
  retailpriceperunit/market_price -1

  when match_type like '%Kit%' then
  x.anchor_sku_sp_price/market_price -1

   else null end
   as Market_Price_Variance

, .95*Market_Price as Market_ATS_Price

from
(

select s.*, CAST(NULL AS bigint) AS anchor_sku
, case when p.chewyprice is not null then 'Match to Chewy'
  when p.min_price_instock_focus_comp is not null then 'Market Price'
  when p.min_price_instock is not null then 'Market Price All Retailers'
  when p.min_price_all is not null then 'Market Price inc OOS All Retailers'
  when s.mapretailprice > 1 then 'MAP Retail Price'
  else 'No Match' end as Match_Type

, case when p.chewyprice is not null then p.chewyprice
  when p.min_price_instock_focus_comp is not null then p.min_price_instock_focus_comp
  when p.min_price_instock is not null then p.min_price_instock
  when p.min_price_all is not null then p.min_price_all
  when s.mapretailprice > 1 then mapretailprice

else null end as Market_Price

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then p.instock_focuscomp
  when p.min_price_instock is not null then p.instock_comp
  when p.min_price_all is not null then p.all_comp
else null end as Competitor_Count

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then 1
  when p.min_price_instock is not null then 0
  when p.min_price_all is not null then 0
  else 0 end as For_Action

,CAST(NULL AS decimal(19,6)) as kit_quantity
, CAST(NULL AS decimal(19,6)) as anchor_sku_sp_price
from #sales s

left join #pricing p on s.SKUID = p.skuid
-- Kit-component matching deferred; no reporting kit-table dependency.

where gross is not null
and skuinactiveflag = 0
)
x
where x.skuid <> 2109713311  --remove problematic ulcergard sku until bug is fixed

)
SELECT * INTO #SPPriceSku FROM FinalSku;

-- The source query's Market_ATS_Price is not used: it ignores eligibility.
-- Compare current warehouse prices for both SKU and kit-anchor lookups.
;WITH LivePrices AS
(
 SELECT ProductID, MIN(ComputedPrice) AS Price,
        CASE WHEN COUNT(*)=COUNT(ComputedPrice)
               AND MIN(ComputedPrice)=MAX(ComputedPrice) AND MIN(ComputedPrice)>0
             THEN 1 ELSE 0 END AS ValidPrice
 FROM #SPPriceLive GROUP BY ProductID
),
SkuMultiplicity AS
(
 SELECT skuid,COUNT(*) AS SourceRowCount FROM #SPPriceSku GROUP BY skuid
),
Scoped AS
(
 SELECT s.*,m.SourceRowCount,
        CASE WHEN BuyerName='Dan Rollins' AND productgroup IN ('Bucket','TES')
             THEN 'Consumables'
             WHEN BuyerName IN ('Meghan Guissarri','Lainey Sullivan','Alissa Hof')
                  AND productgroup='TES' THEN 'Hardgoods' END AS Cohort
 FROM #SPPriceSku s JOIN SkuMultiplicity m ON m.skuid=s.skuid
 WHERE labelclassification='3rd Party'
),
StandardCandidates AS
(
 SELECT s.skuid AS ProductID,s.skuname AS ProductName,s.Cohort,
        s.Match_Type,s.SupplierName,s.SourceRowCount,
        s.AutoShipEligibleFlag,s.RetailCostperUnit AS UnitCost,
        live.Price AS CurrentOTS,
        live.ValidPrice AS LiveValid,
        s.Market_Price,
        live.Price AS ComparisonPrice,
        live.ValidPrice AS ComparisonValid,
        s.Market_Price AS ProposedOTS,
        CASE
          WHEN s.Cohort IS NULL THEN 'Outside SOP buyer/product-group scope'
          WHEN COALESCE(s.ProductKitFlag,'')<>'Non Kit Product'
               OR s.Match_Type LIKE '%Kit%'
            THEN 'Kit pricing deferred or kit status unknown'
          WHEN h.ProductID IS NOT NULL THEN CONVERT(varchar(200),h.Reason)
          WHEN s.SourceRowCount<>1 THEN 'Multiple source rows for SKU; resolve conflicting prices or joins'
          WHEN s.Cohort='Consumables' AND s.Match_Type NOT IN ('Match to Chewy','Market Price','Kit Match to Chewy')
            THEN 'Match type not permitted for consumables'
          WHEN s.Cohort='Hardgoods' AND s.Match_Type NOT IN ('Match to Chewy','Market Price')
            THEN 'Match type not permitted for hardgoods'
          WHEN EXISTS(SELECT 1 FROM @SupplierHolds v WHERE v.Cohort=s.Cohort AND v.SupplierName=s.SupplierName)
            THEN 'SOP supplier exclusion'
          -- E3 is a brand exclusion, not an exclusion of every BCI product.
          -- This name-based screen must be replaced by an authoritative brand field if available.
          WHEN s.Cohort='Hardgoods' AND
               (' '+UPPER(s.skuname)+' ' LIKE '% E3 %'
                OR UPPER(s.skuname) LIKE 'E3-%')
            THEN 'SOP E3 brand exclusion identified in product name'
          WHEN s.AutoShipEligibleFlag IS NULL THEN 'Autoship eligibility is missing'
          WHEN s.RetailCostperUnit IS NULL OR s.RetailCostperUnit<0 THEN 'Unit cost is missing or invalid'
        END AS InitialExclusion
 FROM Scoped s
 LEFT JOIN LivePrices live ON live.ProductID=s.skuid
 LEFT JOIN @SkuHolds h ON h.ProductID=s.skuid
 WHERE s.Cohort IS NOT NULL
),
SmartPakCandidates AS
(
 SELECT TRY_CONVERT(bigint,spc.[SmartPak SKUID]) AS ProductID,
        dps.SKUName AS ProductName,'3P SmartPaks' AS Cohort,
        comp.Match_Type,CAST(NULL AS nvarchar(200)) AS SupplierName,
        COUNT(*) OVER(PARTITION BY spc.[SmartPak SKUID]) AS SourceRowCount,
        CAST(1 AS bit) AS AutoShipEligibleFlag,
        basis.UnitCost28Days AS UnitCost,basis.CurrentOTS28Days AS CurrentOTS,
        CASE WHEN basis.CurrentOTS28Days>0 THEN 1 ELSE 0 END AS LiveValid,
        comp.Market_Price,
        dps.AutoshipRetailPrice/NULLIF(dps.AutoshipPriceMultiplier,0)
              /28.0*TRY_CONVERT(decimal(19,6),spc.[Comp DOS]) AS ComparisonPrice,
        CASE WHEN dps.AutoshipRetailPrice>0 AND dps.AutoshipPriceMultiplier>0
             THEN 1 ELSE 0 END AS ComparisonValid,
        comp.Market_Price/NULLIF(TRY_CONVERT(decimal(19,6),spc.[Comp DOS]),0)*28 AS ProposedOTS,
        CASE
          WHEN h.ProductID IS NOT NULL THEN CONVERT(varchar(200),h.Reason)
          WHEN anchorhold.ProductID IS NOT NULL THEN 'Comparison bucket is on a known SKU hold'
          WHEN COALESCE(bucket.ProductKitFlag,'')<>'Non Kit Product'
               OR COALESCE(dps.ProductKitFlag,'')<>'Non Kit Product'
            THEN 'Kit pricing deferred or kit status unknown'
          WHEN mult.SourceRowCount<>1 THEN 'Comparison bucket has multiple source prices'
          WHEN comp.skuid IS NULL OR comp.Match_Type IN ('No Match','MAP Retail Price')
            THEN 'No supported comparison-bucket market price'
          WHEN TRY_CONVERT(decimal(19,6),spc.[Comp DOS]) IS NULL
               OR TRY_CONVERT(decimal(19,6),spc.[Comp DOS])<=0
            THEN 'Comparison days of supply is missing or invalid'
          WHEN basis.ProductID IS NULL OR basis.UnitCost28Days IS NULL OR basis.UnitCost28Days<0
            THEN 'Confirm 28-day unit cost and current OTS basis'
        END AS InitialExclusion
 FROM sandbox.dbo.[SmartPak Pricing Comps] spc
 JOIN
 (
   SELECT p.skuid,p.SKUName,p.AutoshipRetailPrice,p.AutoshipPriceMultiplier,
          p.SKUInactiveFlag,p.productgroup,p.LabelClassification,p.ProductKitFlag
   FROM SPDW.core.DimProductSKU p
   WHERE p.RowCurrentFlag=1
 ) dps ON dps.skuid=spc.[SmartPak SKUID]
 JOIN SPDW.core.DimProductSKU bucket ON bucket.skuid=spc.[Comp SKUID] AND bucket.RowCurrentFlag=1
 LEFT JOIN #SPPriceSku comp ON comp.skuid=spc.[Comp SKUID]
 LEFT JOIN SkuMultiplicity mult ON mult.skuid=comp.skuid
 LEFT JOIN @SmartPakBasis basis ON basis.ProductID=spc.[SmartPak SKUID]
 LEFT JOIN @SkuHolds h ON h.ProductID=spc.[SmartPak SKUID]
 LEFT JOIN @SkuHolds anchorhold ON anchorhold.ProductID=spc.[Comp SKUID]
 WHERE dps.SKUInactiveFlag=0 AND dps.productgroup='SmartPak'
       AND dps.LabelClassification IN ('3rd Party','Exclusive')
),
Candidates AS
(
 SELECT * FROM StandardCandidates
 UNION ALL
 SELECT * FROM SmartPakCandidates
),
Rounded AS
(
 SELECT *,CAST(ROUND(ProposedOTS,2) AS decimal(19,2)) AS NewOTS
 FROM Candidates
),
Decisions AS
(
 SELECT *,
        CAST(ROUND(CASE WHEN AutoShipEligibleFlag=1 THEN NewOTS*0.95 ELSE NewOTS END,2)
             AS decimal(19,2)) AS NewATS,
        CASE
          WHEN InitialExclusion IS NOT NULL THEN InitialExclusion
          WHEN SourceRowCount<>1 THEN 'Multiple source rows for SKU'
          WHEN COALESCE(LiveValid,0)<>1 OR COALESCE(ComparisonValid,0)<>1
            THEN 'Current comparison price is missing, invalid or conflicting'
          WHEN NewOTS IS NULL OR NewOTS<=0 OR Market_Price IS NULL OR Market_Price<=0
            THEN 'Proposed price is missing or nonpositive'
          WHEN NewOTS<UnitCost THEN 'Proposed OTS is below unit cost'
          WHEN ABS(ComparisonPrice/NULLIF(Market_Price,0)-1)
                    <= CASE WHEN Cohort='3P SmartPaks' THEN 0.01 ELSE 0.001 END
            THEN 'Already within workbook market-position tolerance'
          WHEN NewOTS=CAST(ROUND(CurrentOTS,2) AS decimal(19,2))
            THEN 'Rounded OTS would not change'
        END AS ExclusionReason
 FROM Rounded
)
SELECT *,COUNT(*) OVER(PARTITION BY ProductID) AS OutputRowCount
INTO #SPPriceDecisions FROM Decisions;

IF @OutputMode='UPLOAD'
 SELECT ProductID,
        NewOTS AS [New OTS Price],
        NewATS AS [New ATS Price]
 FROM #SPPriceDecisions
 WHERE ExclusionReason IS NULL AND OutputRowCount=1
 ORDER BY ProductID;
ELSE
 SELECT ProductID,ProductName,Cohort,Match_Type,SupplierName,
        CASE WHEN Cohort='3P SmartPaks' THEN 'Confirmed 28-day basis'
             ELSE 'Warehouse RetailPricePerUnit' END AS CurrentOTSPriceSource,
        @RunAt AS QueryRunAt,
        'Deferred - not evaluated' AS MAPRestrictionCheck,
        @AsOfDate AS CompetitorSnapshotDate,
        DATEDIFF(day,@AsOfDate,CAST(@RunAt AS date)) AS CompetitorSnapshotAgeDays,
        CurrentOTS,Market_Price,UnitCost,NewOTS AS [New OTS Price],NewATS AS [New ATS Price],
        CASE WHEN OutputRowCount<>1 THEN 'Excluded: multiple candidate rows for SKU'
             WHEN ExclusionReason IS NULL THEN 'Eligible'
             ELSE ExclusionReason END AS Decision
 FROM #SPPriceDecisions
 ORDER BY Cohort,ProductID;
