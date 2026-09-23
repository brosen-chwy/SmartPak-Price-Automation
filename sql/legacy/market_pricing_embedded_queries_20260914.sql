-- Exact query text extracted from market_pricing_file_ERob_V11_20260914.xlsx.
-- SQL Server dialect. This file contains separate SELECT batches; it was not run against a database.
-- Most batches use livereporting / SPDW. Live Site Pricing uses Localdb,51002 / SPE_Local.
-- Select the correct connection per batch; do not run the whole file on one connection.

-- MODEL QUERY: ChewyPricing
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:12.19 (timezone not established)
-- Extracted from xl/model/item.data, file B9C924C1D4C42489998, offset 22283
select *
from spdw_ods.mktg.tblchewypricingcomp cpc
where cast(asofdate as date) = cast(getdate() as date)
GO

-- MODEL QUERY: MarketPricing Raw Data
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:21.236667 (timezone not established)
-- Extracted from xl/model/item.data, file 46EADDC68FE64B2689AF, offset 29749
select *
  FROM [SPDW_ODS].[Mktg].[tblChewyConsolidatedPricing]
  where cast(EDWCreatedDateTime as date) = cast(getdate() as date)
and sku not like '%-%'
GO

-- MODEL QUERY: Market Pricing Clean
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:20.553333 (timezone not established)
-- Extracted from xl/model/item.data, file 135A99221738493EA88B, offset 34714
with #marketpricing as
(
SELECT sku-990000000000 as skuid, Name, competitor, case when price = '' then null else price end as  price, availability, seller

  FROM [SPDW_ODS].[Mktg].[tblChewyConsolidatedPricing]
  where cast(EDWCreatedDateTime as date) = cast(getdate() as date)
and sku not like '%-%'
)



  select distinct skuid, name, competitor, price, availability, seller from #marketpricing
  where availability = 1
  and price <> ''
  and competitor in
('amazon'
        ,'bigdweb'
        ,'corroshop'

        ,'farmandfleet'
        ,'horse'
        ,'jefferspet'
        ,'nrs'
        ,'ridingwarehouse'
        ,'statelinetack'
        ,'tractorsupply'
        ,'valleyvet'
        )
GO

-- MODEL QUERY: Kits
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:20.966667 (timezone not established)
-- Extracted from xl/model/item.data, file 5F0FCA4A9FD492B90C0, offset 40722
with
#marketpricing as
(
SELECT RIGHT(990000000000,10) as skuid, Name, competitor, case when price = '' then null else CAST(price AS FLOAT) end as  price, availability, seller
 --into #marketpricing
  FROM [SPDW_ODS].[Mktg].[tblChewyConsolidatedPricing]
  where cast(EDWCreatedDateTime as date) = cast(getdate() as date)
and sku not like '%-%'
)
,
#chewypricing as

  --create chewy pricing table from file
(
select *
--into #chewypricing
from spdw_ods.mktg.tblchewypricingcomp cpc
where cast(asofdate as date) = cast(getdate() as date)
)
,
#pricing as
(
select  case when smartpakskunumber is null then skuid else smartpakskunumber end as skuid
,c.ChewyPrice
, m.min_price_instock_focus_comp
, m.min_price_instock
, m.min_price_all
, m.instock_focuscomp
, m.instock_comp
, m.all_comp
--into #pricing
from
(

select distinct smartpakskunumber, chewyprice
--into #targetpricing
from #chewypricing
) c
full outer join

--next find the minimum market price and data quality criteria from the market pricing file
(
select a.skuid
, a.min_price as min_price_all, a.competitors as all_comp
, b.min_price as min_price_instock, b.competitors as instock_comp
, c.min_price as min_price_instock_focus_comp, c.competitors as instock_focuscomp
--into #comp_pricing
from

(
select skuid, min(price) min_price, count(distinct competitor) competitors
from #marketpricing
where price is not null
and price <> ''
--and skuid = 2109912740
group by skuid
) a
left join
(
select skuid, min(price) min_price, count(distinct competitor) competitors
from #marketpricing
where Availability = 1
--and skuid = 2109912740
group by skuid
) b on a.skuid = b.skuid
left join
(
select skuid, min(price) min_price, count(distinct competitor) competitors
from #marketpricing
where Availability = 1
--and skuid = 2109912740
and competitor in
('amazon'
        ,'bigdweb'
        ,'corroshop'
        ,'doversaddlery'
        ,'farmandfleet'
        ,'horse'
        ,'jefferspet'
        ,'nrs'
        ,'ridingwarehouse'
        ,'statelinetack'
        ,'tractorsupply'
        ,'valleyvet'
        )
group by skuid
) c on b.skuid = c.skuid

) m on c.SmartPakSkuNumber = m.skuid

)


select cpc.skuid anchor_sku, dps1.productname anchor_product, tk.QuantityDose
, cpc.ChewyPrice, cpc.min_price_all, cpc.min_price_instock, cpc.min_price_instock_focus_comp, cpc.all_comp, cpc.instock_comp, cpc.instock_focuscomp, dps1.RetailPricePerUnit anchor_sku_sp_price
,  dps2.skuid, dps2.skuname, dps2.RetailPricePerUnit
from #pricing cpc
join reporting.dbo.tblkit tk on cpc.skuid = tk.ComponentProductID
join CORE.DimProductSKU dps1 on dps1.skuid = tk.ComponentProductID
join CORE.DimProductSKU dps2 on dps2.skuid = tk.PrimaryProductID
--where cast(asofdate as date) = cast(getdate() as date)
where deleted = 0
and dps1.RowCurrentFlag = 1
and dps2.rowcurrentflag = 1
and dps1.SKUInactiveFlag = 0
and dps2.skuinactiveflag = 0
and quantitydose > 1
GO

-- MODEL QUERY: Sku Level Analysis
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:16:18.103333 (timezone not established)
-- Extracted from xl/model/item.data, file 44F45576B06B458E9A0, offset 50797
with #sales
as
(
 select y.*, gross, net, qty, cogs, ats_qty, ots_qty
 --into #sales
 from
(select distinct skuid, skuname, RetailPricePerUnit, dps.AutoshipRetailPrice, dps.RetailCostperUnit, ProductStockType, productgroup, productcategory, BuyerName, AutoShipEligibleFlag, SKUInactiveFlag, SupplierName, ProductKitFlag
, case when LabelClassification = 'Exclusive' then '3rd Party' else labelclassification end as labelclassification, hasmaprestrictedpricing
, segment, subsegment, mapretailprice
from core.dimproductsku dps
join reporting.dbo.manufacturers m on dps.manufacturerid = m.manufacturerid
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
and fulldate between dateadd(year,-1, dateadd(day, -1,getdate())) and dateadd(day, -1,getdate())
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
    WHERE CAST(EDWCreatedDateTime AS date) = CAST(GETDATE() AS date)
      AND CONVERT(varchar(100), sku) NOT LIKE '%-%'
)
,
#chewypricing as

  --create chewy pricing table from file
(
select *
--into #chewypricing
from spdw_ods.mktg.tblchewypricingcomp cpc
where cast(asofdate as date) = cast(getdate() as date)
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
  when kit.ChewyPrice is not null then 'Kit Match to Chewy'
  when kit.min_price_instock_focus_comp is not null then 'Kit Match to Market'
  when p.min_price_instock is not null then 'Market Price All Retailers'
  when p.min_price_all is not null then 'Market Price inc OOS All Retailers'
  else 'No Match' end as Match_Type
, case when p.chewyprice is not null then p.chewyprice
  when p.min_price_instock_focus_comp is not null then p.min_price_instock_focus_comp
  when kit.ChewyPrice is not null then kit.chewyprice
  when kit.min_price_instock_focus_comp is not null then kit.min_price_instock_focus_comp
  when p.min_price_instock is not null then p.min_price_instock
  when p.min_price_all is not null then p.min_price_all
  else null end as Market_Price
, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then p.instock_focuscomp
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then kit.instock_focuscomp
  when p.min_price_instock is not null then p.instock_comp
  when p.min_price_all is not null then p.all_comp
  else null end as Competitor_Count

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then 1
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then 1
  when p.min_price_instock is not null then 0
  when p.min_price_all is not null then 0
  else 0 end as For_Action

,QuantityDose as kit_quantity
, kit.anchor_sku_sp_price
from #sales s

left join #pricing p on s.SKUID = p.skuid
left join
(
select cpc.skuid anchor_sku, dps1.productname anchor_product, tk.QuantityDose,  dps2.skuid, cpc.ChewyPrice, cpc.min_price_all, cpc.min_price_instock, cpc.min_price_instock_focus_comp, cpc.all_comp, cpc.instock_comp, cpc.instock_focuscomp, dps1.RetailPricePerUnit anchor_sku_sp_price
from #pricing cpc
join reporting.dbo.tblkit tk on cpc.skuid = tk.ComponentProductID
join core.DimProductSKU dps1 on dps1.skuid = tk.ComponentProductID
join core.DimProductSKU dps2 on dps2.skuid = tk.PrimaryProductID
--where cast(asofdate as date) = cast(getdate() as date)
where deleted = 0
and dps1.RowCurrentFlag = 1
and dps2.rowcurrentflag = 1
and dps1.SKUInactiveFlag = 0
and dps2.skuinactiveflag = 0
and quantitydose > 1
) kit on s.SKUID = kit.skuid

where gross is not null
and skuinactiveflag = 0
)
x
)


--sku level analysis


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

select s.*, anchor_sku
, case when p.chewyprice is not null then 'Match to Chewy'
  when p.min_price_instock_focus_comp is not null then 'Market Price'
  when kit.ChewyPrice is not null then 'Kit Match to Chewy'
  when kit.min_price_instock_focus_comp is not null then 'Kit Match to Market'
  when p.min_price_instock is not null then 'Market Price All Retailers'
  when p.min_price_all is not null then 'Market Price inc OOS All Retailers'
  when s.mapretailprice > 1 then 'MAP Retail Price'
  else 'No Match' end as Match_Type

, case when p.chewyprice is not null then p.chewyprice
  when p.min_price_instock_focus_comp is not null then p.min_price_instock_focus_comp
  when kit.ChewyPrice is not null then kit.chewyprice
  when kit.min_price_instock_focus_comp is not null then kit.min_price_instock_focus_comp
  when p.min_price_instock is not null then p.min_price_instock
  when p.min_price_all is not null then p.min_price_all
  when s.mapretailprice > 1 then mapretailprice

else null end as Market_Price

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then p.instock_focuscomp
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then kit.instock_focuscomp
  when p.min_price_instock is not null then p.instock_comp
  when p.min_price_all is not null then p.all_comp
else null end as Competitor_Count

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then 1
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then 1
  when p.min_price_instock is not null then 0
  when p.min_price_all is not null then 0
  else 0 end as For_Action

,QuantityDose as kit_quantity
, kit.anchor_sku_sp_price
from #sales s

left join #pricing p on s.SKUID = p.skuid
left join
(
select cpc.skuid anchor_sku, dps1.productname anchor_product, tk.QuantityDose,  dps2.skuid, cpc.ChewyPrice, cpc.min_price_all, cpc.min_price_instock, cpc.min_price_instock_focus_comp, cpc.all_comp, cpc.instock_comp, cpc.instock_focuscomp, dps1.RetailPricePerUnit anchor_sku_sp_price
from #pricing cpc
join reporting.dbo.tblkit tk on cpc.skuid = tk.ComponentProductID
join core.DimProductSKU dps1 on dps1.skuid = tk.ComponentProductID
join core.DimProductSKU dps2 on dps2.skuid = tk.PrimaryProductID
--where cast(asofdate as date) = cast(getdate() as date)
where deleted = 0
and dps1.RowCurrentFlag = 1
and dps2.rowcurrentflag = 1
and dps1.SKUInactiveFlag = 0
and dps2.skuinactiveflag = 0
and quantitydose > 1
) kit on s.SKUID = kit.skuid

where gross is not null
and skuinactiveflag = 0
)
x
where x.skuid <> 2109713311  --remove problematic ulcergard sku until bug is fixed
order by gross desc
GO

-- MODEL QUERY: 3P SmartPaks
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:56.836667 (timezone not established)
-- Extracted from xl/model/item.data, file 7BC019A818F140AF82D9, offset 65249
with #sales
as
(
 select y.*, gross, net, qty, cogs, ats_qty, ots_qty
 --into #sales
 from
(select distinct skuid, skuname, RetailPricePerUnit, dps.AutoshipRetailPrice, dps.RetailCostperUnit, ProductStockType, productgroup, productcategory, BuyerName, AutoShipEligibleFlag, SKUInactiveFlag, SupplierName, ProductKitFlag
, case when LabelClassification = 'Exclusive' then '3rd Party' else labelclassification end as labelclassification, hasmaprestrictedpricing
, segment, subsegment, mapretailprice
from core.dimproductsku dps
join reporting.dbo.manufacturers m on dps.manufacturerid = m.manufacturerid
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
and fulldate between dateadd(year,-1, dateadd(day, -1,getdate())) and dateadd(day, -1,getdate())
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
    WHERE CAST(EDWCreatedDateTime AS date) = CAST(GETDATE() AS date)
      AND CONVERT(varchar(100), sku) NOT LIKE '%-%'
)
,
#chewypricing as

  --create chewy pricing table from file
(
select *
--into #chewypricing
from spdw_ods.mktg.tblchewypricingcomp cpc
where cast(asofdate as date) = cast(getdate() as date)
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
  when kit.ChewyPrice is not null then 'Kit Match to Chewy'
  when kit.min_price_instock_focus_comp is not null then 'Kit Match to Market'
  when p.min_price_instock is not null then 'Market Price All Retailers'
  when p.min_price_all is not null then 'Market Price inc OOS All Retailers'
  else 'No Match' end as Match_Type
, case when p.chewyprice is not null then p.chewyprice
  when p.min_price_instock_focus_comp is not null then p.min_price_instock_focus_comp
  when kit.ChewyPrice is not null then kit.chewyprice
  when kit.min_price_instock_focus_comp is not null then kit.min_price_instock_focus_comp
  when p.min_price_instock is not null then p.min_price_instock
  when p.min_price_all is not null then p.min_price_all
  else null end as Market_Price
, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then p.instock_focuscomp
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then kit.instock_focuscomp
  when p.min_price_instock is not null then p.instock_comp
  when p.min_price_all is not null then p.all_comp
  else null end as Competitor_Count

, case when p.chewyprice is not null then 1
  when p.min_price_instock_focus_comp is not null then 1
  when kit.ChewyPrice is not null then 1
  when kit.min_price_instock_focus_comp is not null then 1
  when p.min_price_instock is not null then 0
  when p.min_price_all is not null then 0
  else 0 end as For_Action

,QuantityDose as kit_quantity
, kit.anchor_sku_sp_price
from #sales s

left join #pricing p on s.SKUID = p.skuid
left join
(
select cpc.skuid anchor_sku, dps1.productname anchor_product, tk.QuantityDose,  dps2.skuid, cpc.ChewyPrice, cpc.min_price_all, cpc.min_price_instock, cpc.min_price_instock_focus_comp, cpc.all_comp, cpc.instock_comp, cpc.instock_focuscomp, dps1.RetailPricePerUnit anchor_sku_sp_price
from #pricing cpc
join reporting.dbo.tblkit tk on cpc.skuid = tk.ComponentProductID
join core.DimProductSKU dps1 on dps1.skuid = tk.ComponentProductID
join core.DimProductSKU dps2 on dps2.skuid = tk.PrimaryProductID
--where cast(asofdate as date) = cast(getdate() as date)
where deleted = 0
and dps1.RowCurrentFlag = 1
and dps2.rowcurrentflag = 1
and dps1.SKUInactiveFlag = 0
and dps2.skuinactiveflag = 0
and quantitydose > 1
) kit on s.SKUID = kit.skuid

where gross is not null
and skuinactiveflag = 0
)
x
)



select spc.*, dps.SKUName
, fmp.SKUName as comp_sku,  fmp.Match_Type, fmp.Market_Price as 'Market Bucket Price'
, dps2.RetailPricePerUnit as 'SPE Bucket Price'
, case when [Comp DOS] > 0 then fmp.market_price/[Comp DOS] end as 'Market Bucket Price per Day'
, dps.AutoshipRetailPrice/dps.AutoshipPriceMultiplier as 'SmartPak Price'
, dps.AutoshipRetailPrice/dps.AutoshipPriceMultiplier/28 as 'SmartPak Price per Day'
, case when fmp.market_price = 0 then null
	else (dps.AutoshipRetailPrice/dps.AutoshipPriceMultiplier/28)/(fmp.market_price/[Comp DOS])-1
	end as price_variance_to_market
, case when market_price = 0 or [Comp DOS] = 0 then null
	when (dps.AutoshipRetailPrice/dps.AutoshipPriceMultiplier/28)/(fmp.market_price/[Comp DOS])-1 > .01 then 'Above'
	when (dps.AutoshipRetailPrice/dps.AutoshipPriceMultiplier/28)/(fmp.market_price/[Comp DOS])-1 < -.01 then 'Below'
	else 'AT'

end as market_position
,case when [Comp DOS] > 0 then fmp.market_price/[Comp DOS]*28 end as 'SmartPak Market Reco Price'

from sandbox.[dbo].[SmartPak Pricing Comps] spc
join core.dimproductsku dps on spc.[SmartPak SKUID] = dps.SKUID
join core.dimproductsku dps2 on spc.[Comp SKUID] = dps2.skuid
left join #finalmarketprice fmp on spc.[Comp SKUID] = fmp.skuid
where dps.RowCurrentFlag = 1
and dps2.RowCurrentFlag = 1
GO

-- MODEL QUERY: Sales
-- Connection source ID: 1e1dc99b-263e-4196-ae2e-11bc0eb8ca18
-- Saved LastProcessed: 2026-09-14T12:15:13.99 (timezone not established)
-- Extracted from xl/model/item.data, file 8906BA2123BF493CA54E, offset 78339
select x.skuid, skuname, productid, productname, productgroup, productcategory, productdivision, labelclassification, animaltype, gross, net, qty, cogs, ats_qty, ots_qty
from
(

select skuid,sum(productamount) gross, sum(netproductamount) net, sum(orderedquantity) qty, sum(cogsamount) cogs
, sum(case when priceoffertypename = 'AutoShip Price' then orderedquantity else 0 end) as ATS_qty
, sum(case when priceoffertypename = 'OneTimeShip Price' then orderedquantity else 0 end) as OTS_qty
from sales.factsalesdetail fsd
join core.dimproductsku dps on dps.ProductSKUKey = fsd.productskukey
join core.dimdate dd on dd.DateKey = fsd.OrderDateKey
where demandflag = 1
and freeitem = 0
and productcategory not like '%Gift%Card%'
and fulldate between dateadd(year,-1, dateadd(day, -1,getdate())) and dateadd(day, -1,getdate())
group by skuid
) x
join core.dimproductsku dps2 on dps2.skuid = x.skuid
where dps2.RowCurrentFlag = 1
and skuinactiveflag = 0
GO

-- MODEL QUERY: Live Site Pricing
-- Connection source ID: a404af0b-f1de-4962-80e2-816ab2141609
-- Saved LastProcessed: 2026-09-14T12:16:24.986667 (timezone not established)
-- Extracted from xl/model/item.data, file 1495B829E84A4E2EA2AD, offset 84160
select productid, ComputedPrice
from products
--where productid  = 2109709939
--where inactive = 0
GO
