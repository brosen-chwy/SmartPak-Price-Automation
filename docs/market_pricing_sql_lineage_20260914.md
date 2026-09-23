# Market pricing workbook: calculations and SQL lineage

Source: `market_pricing_file_ERob_V11_20260914.xlsx`, inspected September 14, 2026.

The requested sheet is named **Market Pricing Clean Data**. It contains 4,115 data rows in A2:F4116, covering 1,107 distinct SKUs, and has no worksheet formulas. All six columns are imported from the Power Pivot model table **Market Pricing Clean**. The exact SQL was recovered from the workbook's embedded data model, rather than inferred from values or the SOP video.

The source connection is SQL Server **livereporting**, default database **SPDW**. The clean query reads **SPDW_ODS.Mktg.tblChewyConsolidatedPricing** directly. The raw sheet is a separate query against the same table; the clean query does not read worksheet cells.

Companion files:

- `market_pricing_clean_parameterized.sql`: clean-data SELECT with an explicit ingestion date, suitable for review and testing on SQL Server.
- `market_pricing_embedded_queries_20260914.sql`: exact recovered SELECT batches for Clean Data, Raw Data, Chewy Pricing, Kits, SKU Analysis, 3P SmartPaks, Sales, and Live Site Pricing. Connection differences and extraction locations are documented in the file.

No database query was executed, workbook refreshed, or source workbook edited. Validation used the saved raw rows, formulas, model definitions, and cached results.

## 1. Clean-data column mapping

Source ranges below identify corresponding fields on **Market Pricing Raw Data**, whose data range is A2:AU17919. They are equivalent source fields, not Excel formula precedents.

| Clean output | Raw field / range | Exact source calculation |
|---|---|---|
| A: `skuid` | `Sku`, A2:A17919 | `sku - 990000000000` |
| B: `name` | `Name`, D2:D17919 | Direct source value |
| C: `competitor` | `Competitor`, B2:B17919 | Direct source value |
| D: `price` | `Price`, F2:F17919 | `CASE WHEN price = '' THEN NULL ELSE price END` |
| E: `availability` | `Availability`, G2:G17919 | Direct source value; only `availability = 1` retained |
| F: `seller` | `Seller`, L2:L17919 | Direct source value |

Additional source fields control inclusion:

- `EDWCreatedDateTime`, raw AS2:AS17919: its date must equal SQL Server's `GETDATE()` date at refresh.
- `Sku`, raw A2:A17919: values containing a hyphen are excluded with `sku NOT LIKE '%-%'`.
- `Price`, raw F2:F17919: blank strings become NULL and are excluded by `price <> ''`.
- `Competitor`, raw B2:B17919: must be in the approved list below.

Approved competitors: `amazon`, `bigdweb`, `corroshop`, `farmandfleet`, `horse`, `jefferspet`, `nrs`, `ridingwarehouse`, `statelinetack`, `tractorsupply`, `valleyvet`. Valleyvet is allowed but has no rows in the saved clean output. Doversaddlery is not in this clean-query list.

Finally, `SELECT DISTINCT` applies to **all six output columns together**. It does not select a single price per SKU or per SKU/competitor, and it does not choose a minimum price. Multiple sellers, product names, or prices can remain for one SKU/competitor.

The clean query does not use `CompEqualizedPrice` (raw Y), `InCartPrice` (P), `ListPrice` (N), coupons, shipping, `MatchType` (T), `ScrapingStatus` (H), or `OfferDate` (I) as selection or price-calculation rules. No separate seller, Amazon FBA, MAP, price-rounding, or positive-price filter is present. Price remains text in the saved clean sheet; numeric conversion occurs in the downstream SKU-analysis query.

## 2. Exact recovered clean SQL

```sql
with #marketpricing as
(
    SELECT sku-990000000000 as skuid,
           Name, competitor,
           case when price = '' then null else price end as price,
           availability, seller
    FROM [SPDW_ODS].[Mktg].[tblChewyConsolidatedPricing]
    where cast(EDWCreatedDateTime as date) = cast(getdate() as date)
      and sku not like '%-%'
)
select distinct skuid, name, competitor, price, availability, seller
from #marketpricing
where availability = 1
  and price <> ''
  and competitor in
  ('amazon','bigdweb','corroshop','farmandfleet','horse','jefferspet',
   'nrs','ridingwarehouse','statelinetack','tractorsupply','valleyvet')
```

Whitespace above is simplified; the companion embedded-query file retains the extracted text. `#marketpricing` is the CTE name used in the workbook, not a separately persisted table.

The supplied parameterized version changes the date filter to `>= @AsOfDate AND < DATEADD(day,1,@AsOfDate)`. It otherwise retains the source transformations and filters. A historical date will work only if that ingestion day's data remains in the source. SQL Server date/time and collation behavior should be retained when validating a different SQL engine.

## 3. Reconciliation to the saved workbook

| Stage | Rows |
|---|---:|
| Saved Market Pricing Raw Data | 17,918 |
| Correct ingestion date and SKU without hyphen | 17,918 |
| Availability = 1 | 14,684 |
| Also nonblank price | 14,672 |
| Also approved competitor | 11,887 |
| DISTINCT six-column records | 4,115 |
| Saved Market Pricing Clean Data | 4,115 |
| Distinct clean SKUs | 1,107 |

The reconstructed and saved outputs match on all records after case-insensitive text comparison. There is one exact-text difference: clean B2477 is `Betadine Solution - 16 oz`; corresponding raw D2180:D2182 is `BETADINE SOLUTION - 16 OZ`. The SKU, competitor, price, availability, and seller match. The extracted SQL contains no title-case transformation, so the capitalization should not become an invented cleaning rule.

Concrete cell examples:

| Clean record | Corresponding raw record(s) | Evidence |
|---|---|---|
| A2:F2 | Rows 11917, 11918, 11919 | A11917 `992109665628` minus `990000000000` = A2 `2109665628`; D11917 → B2; B11917 → C2; F11917 → D2 `33.82`; G11917 → E2; L11917 → F2. Three projected duplicates become one clean row. |
| A3:F3 | Row 2684 | Same six-column mapping; SKU `2109664146`, Amazon price `31.95`. |
| A4:F4 | Row 2843 | Same mapping; SKU `2109672257`, Amazon price `36.61`. |
| A4116:F4116 | Rows 9213, 9214, 9215 | Same mapping; SKU `2109920729`, horse price `54.89`. |

These row references are evidence for this saved workbook. The original query has no `ORDER BY`, so subsequent refreshes may reorder rows.

The saved data identifies the source pipeline as `Mktg_ChewyConsolidatedPricing_ODS_Populate51` and source filename `Chewy_Smartequine_Consolidated_Pricing_260913.csv` (raw AT/AU). The ingestion date is September 14 even though the filename refers to September 13. Use **ingestion date**, not offer date or filename date, to reproduce this workbook.

## 4. How clean market data relates to SKU Analysis

**Sku Analysis** is where the SOP's pricing decisions and upload prices originate. Its model table is **Sku Level Analysis**, worksheet table `Table_Sku_Level_Analysis`. It reads the same underlying pricing table independently. Automating only the six-column clean tab does not recreate the SKU-analysis output: clean data excludes out-of-stock offers and unapproved retailers that the SKU query uses as fallbacks.

The SKU query normalizes `sku` with `TRY_CONVERT(bigint, NULLIF(LTRIM(RTRIM(CONVERT(varchar(100), sku))), '')) - 990000000000` and parses `price` with the same trim/blank handling followed by `TRY_CONVERT(decimal(19,4), ...)`.

It builds three market aggregates per SKU:

| Aggregate | Population | Calculation |
|---|---|---|
| `min_price_all`, `all_comp` | All retailers with numeric non-NULL price, any availability | `MIN(price)`, `COUNT(DISTINCT competitor)` |
| `min_price_instock`, `instock_comp` | `TRY_CONVERT(int, Availability) = 1`, all retailers | `MIN(price)`, `COUNT(DISTINCT competitor)` |
| `min_price_instock_focus_comp`, `instock_focuscomp` | In stock and approved competitor list | `MIN(price)`, `COUNT(DISTINCT competitor)` |

The in-stock competitor counts do not explicitly filter out NULL numeric prices. SQL `MIN` ignores NULL prices, while the competitor count can still include those rows. Preserve or explicitly revise that behavior.

Chewy pricing comes from `SPDW_ODS.Mktg.tblChewyPricingComp`, filtered on `CAST(AsOfDate AS date) = CAST(GETDATE() AS date)`. It is visible in **Chewy Pricing by Item**, H2:H1675 (`ChewyPrice`) and L2:L1675 (`SmartPakSkuNumber`). The join key is **SmartPakSkuNumber**, not the Chewy SKU in column A. The query selects distinct `(SmartPakSkuNumber, ChewyPrice)` pairs and full-outer-joins market aggregates.

The final SKU query applies the following first-match-wins order:

| Priority | Condition | U: Match_Type | V: Market_Price | X: Competitor_Count | Y: For_Action |
|---:|---|---|---|---|---:|
| 1 | Direct Chewy price is non-NULL | Match to Chewy | Direct ChewyPrice | 1 | 1 |
| 2 | Direct focused in-stock minimum is non-NULL | Market Price | min_price_instock_focus_comp | instock_focuscomp | 1 |
| 3 | Kit anchor Chewy price is non-NULL | Kit Match to Chewy | Anchor ChewyPrice | 1 | 1 |
| 4 | Kit anchor focused in-stock minimum is non-NULL | Kit Match to Market | Anchor min_price_instock_focus_comp | Anchor instock_focuscomp | 1 |
| 5 | Direct all-retailer in-stock minimum is non-NULL | Market Price All Retailers | min_price_instock | instock_comp | 0 |
| 6 | Direct all-retailer minimum is non-NULL | Market Price inc OOS All Retailers | min_price_all | all_comp | 0 |
| 7 | MAP retail price > 1 | MAP Retail Price | mapretailprice | NULL | 0 |
| 8 | None of the above | No Match | NULL | NULL | 0 |

MAP is a fallback in this query, not an enforced floor over every chosen market price. `hasmaprestrictedpricing` is carried through as a flag. No additional MAP override should be assumed from the SOP review.

## 5. SKU Analysis column sources and calculations

All references below use **Sku Analysis**, data rows 2:10357. SQL-derived columns arrive as saved values; Excel formulas and DAX are called out separately.

| Columns | Source or calculation |
|---|---|
| A:N | Current product/SKU attributes from `SPDW.core.DimProductSKU`, joined to `reporting.dbo.manufacturers` on manufacturerid. LabelClassification `Exclusive` becomes `3rd Party`. Source fields include sku ID/name, retail and autoship price, cost, stock type, group/category, buyer, eligibility/inactive flags, supplier, and kit flag. |
| O: gross | `SUM(sales.FactSalesDetail.productamount)` by SKU |
| P: net | `SUM(netproductamount)` by SKU |
| Q: qty | `SUM(orderedquantity)` by SKU |
| R: cogs | `SUM(cogsamount)` by SKU |
| S: ats_qty | Sum orderedquantity where priceoffertypename = `AutoShip Price` |
| T: ots_qty | Sum orderedquantity where priceoffertypename = `OneTimeShip Price` |
| U: Match_Type | Ordered pricing rules in section 4 |
| V: Market_Price | Price associated with the first matched rule |
| W: Market Price Implied Margin | Excel formula: for V > 0, `(basis - E) / basis`, where basis = V × Z for the two kit match types, otherwise V; blank string when V is not positive |
| X: Competitor_Count | Count associated with the first matched pricing rule |
| Y: For_Action | 1 for pricing priorities 1–4; otherwise 0 |
| Z: kit_quantity | `reporting.dbo.tblkit.QuantityDose` |
| AA: anchor_sku_sp_price | Anchor SKU's `DimProductSKU.RetailPricePerUnit` |
| AB: Market_Position | Non-kit: compare C against V. Kit: compare AA against V. Above if > 1.001 × V; Below if < 0.999 × V; At within that inclusive band; Unknown otherwise. |
| AC: Market_Price_Variance | Non-kit: C / V − 1. Kit: AA / V − 1. NULL for zero or missing market price. |
| AD: hasmaprestrictedpricing | Attribute selected with the product/manufacturer source |
| AE: Live Price | DAX lookup of `Live Site Pricing[ComputedPrice]` by live productid = this row's A/skuid |
| AF: Live Price Variance | DAX: if V > 0, use AI / V − 1 for kit match types when AI > 0; otherwise AE / V − 1. Blank when V is not positive. |
| AG: Live Price Market Position | DAX: UNKNOWN when V is not positive. Otherwise ABOVE when AF > 0.001; BELOW when AF < −0.001; AT otherwise. |
| AH: anchor_sku | Kit component SKU from `tblkit.ComponentProductID` |
| AI: anchor_sku_live_price | DAX lookup of live ComputedPrice by productid = AH/anchor_sku |
| AJ: segment; AK: subsegment; AL: mapretailprice | Attributes selected with the product/manufacturer source |
| AM: Market ATS Price | Excel `=IF((J2=TRUE),(V2*0.95),(V2))`, copied down |
| AN: Inventory ok to change | Saved values/errors only; no formula, query binding, or recoverable source reference for this added worksheet column |

The product query selects some fields without a table alias. The workbook establishes the product/manufacturer join and selected names but not database column ownership for every unqualified attribute. Confirm ownership against the database schema before introducing aliases in a rewritten query.

Sales joins: FactSalesDetail.ProductSKUKey → DimProductSKU.ProductSKUKey, and FactSalesDetail.OrderDateKey → DimDate.DateKey. Filters are `demandflag = 1`, `freeitem = 0`, and productcategory not like `%Gift%Card%`. The exact date predicate is:

```sql
fulldate BETWEEN DATEADD(year,-1,DATEADD(day,-1,GETDATE()))
             AND DATEADD(day,-1,GETDATE())
```

This retains GETDATE's time component. Replacing it with whole calendar-day boundaries changes the existing behavior and should be reconciled explicitly. The final SKU population requires current product rows, non-NULL gross sales, inactive flag = 0, and excludes SKU **2109713311** with the embedded comment `remove problematic ulcergard sku until bug is fixed`. It sorts by gross descending. It does not filter to For_Action = 1 within the source SELECT.

Kit joins: chosen pricing SKU → `tblkit.ComponentProductID` → anchor DimProductSKU; `tblkit.PrimaryProductID` → kit DimProductSKU; outer join back to the sales SKU. Both product records must be current and active, kit row must have `deleted = 0`, and QuantityDose > 1. A kit's V is the component/anchor price, not automatically a full-kit upload price.

Live prices use a separate connection: **Localdb,51002**, database **SPE_Local**, query `SELECT productid, ComputedPrice FROM products`. The `products` schema is not qualified in the embedded query. Reproducing AE/AI in SQL requires access to that source or a replicated equivalent, then joins on A and AH respectively.

The verified current DAX for AG uses ±0.001. A separate older model metadata fragment contains a different expression with `.999`; that fragment is inconsistent with the current dimension definition and saved results. The current definition reproduced every saved AG value.

## 6. Translating the two Excel formulas

W2 in equivalent A1 notation:

```excel
=IF(V2>0,
    IF(OR(U2="Kit Match to Chewy",U2="Kit Match to Market"),
       (V2*Z2-E2)/(V2*Z2),
       (V2-E2)/V2),
    "")
```

AM2 exactly:

```excel
=IF((J2=TRUE),(V2*0.95),(V2))
```

SQL expressions for an outer SELECT over the chosen pricing rows:

```sql
CASE WHEN Market_Price > 0 THEN
    CASE WHEN Match_Type IN ('Kit Match to Chewy','Kit Match to Market')
         THEN (Market_Price * kit_quantity - RetailCostperUnit)
              / NULLIF(Market_Price * kit_quantity, 0)
         ELSE (Market_Price - RetailCostperUnit) / Market_Price
    END
END AS Market_Price_Implied_Margin,

CASE WHEN AutoShipEligibleFlag = 1
     THEN COALESCE(Market_Price, 0) * 0.95
     ELSE COALESCE(Market_Price, 0)
END AS Market_ATS_Price_Excel_Parity
```

SQL NULL represents the blank margin result. NULLIF additionally returns NULL for a zero kit denominator; Excel would error in that case. No such case appears in the saved rows. Excel coerces an empty V cell to zero in AM. The COALESCE above preserves that behavior; the saved workbook has 3,963 No Match rows with AM = 0. For an upload implementation, missing market prices need an explicit exclusion or NULL policy rather than becoming an approved zero price.

The embedded SQL also computes `0.95 * Market_Price AS Market_ATS_Price` for every row, regardless of autoship eligibility. The worksheet query metadata marks that imported field as deleted. The visible AM column instead uses the eligibility-aware Excel formula above. Reusing the SQL field without this adjustment would not reproduce the visible workbook.

There is no ROUND in AM. Retain full calculation precision for parity; explicitly establish rounding to cents when generating the upload file.

## 7. Findings that affect automation

1. **Duplicated SKU output:** 10,356 SKU-analysis rows represent 10,345 unique SKUs. Eleven SKU IDs occur twice. For example A1140:A1141 = 2109663934, with V1140 = 17.59 and V1141 = 17.99; both say Match to Chewy. Another example A1421:A1422 = 2109854144 has prices 232 and 265. Distinct `(SmartPakSkuNumber, ChewyPrice)` pairs can retain multiple prices for one SKU. The SQL needs an agreed resolution rule before producing one upload record per product. No minimum/latest choice has been invented.

2. **Standalone Kits query defect:** its market CTE uses `RIGHT(990000000000,10) AS skuid`, a constant expression returning `0000000000`, instead of converting the source SKU. It also includes doversaddlery in its competitor list. All market aggregate fields E:J are blank across its 34 saved data rows. The embedded SKU-analysis query has its own kit calculation using the normalized SKU and the current 11-competitor list; it does not depend on the saved Kits sheet. Do not copy the standalone Kits query as the authoritative implementation.

3. **Inventory source is absent:** AN2:AN10357 contains 10,175 `#N/A`, 164 TRUE, and 17 FALSE values, with zero formulas. The query-table metadata marks AN as not data-bound. The retained workbook cannot establish the original inventory lookup, thresholds, or source. This is the remaining source-rule gap for reproducing the SOP's inventory gate.

4. **Clean data is offer-level:** there can be multiple prices/sellers per SKU/competitor after DISTINCT. Count distinct competitors for competitive coverage; do not count clean rows as competitors or join clean rows directly to a SKU output without an aggregation strategy.

5. **Model logic versus manual selection:** For_Action is a pricing-source eligibility flag, not a complete upload approval. The SOP's category/buyer/inventory selections and any manual review must be specified separately if the goal expands from the clean pull to the final upload.

Independent recalculations of W (margin), AM (ATS), AF (live variance), and AG (live position) matched all 10,356 cached SKU-analysis rows within 1e-8 numeric tolerance and exact categorical equality. This establishes consistency with the saved workbook; it is not a live database refresh test.

For the requested clean-data pull, the source table, six output mappings, and filters are fully recovered. The parameterized SQL is the concrete starting point. For the complete upload workflow, resolve duplicate SKU pricing, identify the missing inventory source, and validate the current database results and final rounding rules.
