# SmartPak SQL pricing candidates

`smartpak_price_update_candidates.sql` is one SQL Server batch producing the upload template's three columns: ProductID, New OTS Price, New ATS Price. It reads source data and creates session-local temporary tables; it does not update prices or upload anything.

## Required before running

Run the entire batch against `livereporting`, database `SPDW`, using DbVisualizer's SQL Commander > Execute Buffer. Warehouse prices refresh daily; the team batches competitor data on Tuesdays. No linked-server configuration is required: current OTS is `SPDW.core.DimProductSKU.RetailPricePerUnit` with `RowCurrentFlag = 1`. The upload identifier is `SKUID`, not this table's `ProductID`.

This is the latest warehouse record, not a live-site price guarantee. Begin/end dates do not establish refresh freshness, so no extra date filter is imposed. The internal `LivePrices`/`ComputedPrice` names are retained solely to minimize changes to downstream calculations. REVIEW labels the actual price source and query run time; that time is not the warehouse refresh time.

The other referenced databases are `SPDW_ODS` and `sandbox`. Read permissions are required. The script requires SQL Server 2016 or later for `DROP TABLE IF EXISTS`.

The default is `@OutputMode = 'REVIEW'`. For this team test, `@AsOfDate` is explicitly pinned to September 8, 2026: the team confirmed 18,105 market rows and 1,729 Chewy rows for that date. Both competitor queries and their availability checks use this date. Current warehouse prices and the run-date-based sales lookback remain unchanged, so this is not a historical reconstruction of September 8 prices.

After the Tuesday September 15 batch completes, verify the date available in both feeds and change `@AsOfDate` to that date (for example, `'20260915'` only if both feeds contain it). The setting does not advance automatically. REVIEW includes `CompetitorSnapshotDate` and `CompetitorSnapshotAgeDays`. A six-day-old snapshot before the next Tuesday load is consistent with the stated cadence and is not by itself evidence of a failed feed.

Missing market or Chewy snapshots stop execution. The script does not assess whether a present snapshot is complete. Keep this pinned-date test in REVIEW mode; after team validation, `'UPLOAD'` returns the three template columns but does not upload them.

For the first team test, compare eligible rows and exclusions with a human-approved run, spot-check warehouse OTS and cost for a few SKUs, and confirm proposed OTS is never below cost. Send back any SQL error with its line number, or SKU examples whose decisions differ from expectations.

## Implemented rules

- Workbook market-price priority, SKU normalization, sales/product eligibility, and SOP buyer/product-group/match-type filters.
- No OTS/ATS inventory quantity eligibility filter.
- Exclude a candidate when its rounded proposed OTS is below unit cost; OTS equal to cost passes. ATS below cost does not exclude it.
- Standard-product ATS is 95% of OTS when autoship-eligible, otherwise OTS. OTS is rounded to cents before ATS is calculated and rounded; confirm this sequencing against the upload system.
- Warehouse-price comparisons, workbook market-position tolerances, unchanged-OTS exclusion, known supplier/SKU holds, and exclusion of ambiguous duplicate SKU rows.

## Remaining differences from a fully automatic human workflow

- Kit pricing is deferred. Both kit-component joins are removed; only products explicitly classified as `Non Kit Product` pass the kit-status gate. Kit-derived matches and blank/unknown kit status are excluded, including directly matched kit products. SmartPak candidates also require non-kit status for the SmartPak and comparison bucket. Restore authoritative kit mappings and discounts before enabling kits.
- Third-party SmartPaks need confirmed, comparable 28-day cost and current OTS values in `@SmartPakBasis`. Until supplied, they cannot pass. Their comparison-bucket lookup currently reuses the sales-qualified SKU dataset; this is narrower than the standalone workbook SmartPak source and must be reconciled before enabling that cohort.
- MAP-restriction eligibility is deferred at the user's request. Both joins to the unavailable `reporting.dbo.manufacturers` table and the flag-based exclusion checks have been removed. REVIEW explicitly labels MAP as not evaluated; eligible rows are not evidence of MAP compliance. The existing `MAP Retail Price` fallback classification remains for source parity, but those matches still do not qualify for upload under the existing match-type rules. The kit-table dependency has also been removed; this test script no longer reads from `reporting`.
- E3 is screened using product names, not an authoritative brand field. Supply that field for reliable brand exclusion.
- Supplier holds reflect the provided SOP and need an owner-maintained source for unattended operation. Private-label escalation cases remain outside automatic selection.
- Human UPC/pack-size checks and large-variance reviews have no complete machine-readable approval rules yet. The batch cannot reproduce those judgments exactly without approved mappings and thresholds.

## Verification

The standard-candidate decision CTEs were adapted to SQLite and retested using the original pricing workbook's cached RetailPricePerUnit and anchor warehouse prices: 6,432 scoped rows and 101 eligible standard-product rows with MAP eligibility and kit pricing deferred. This is an offline sample, not a prediction of the team's current results, and does not test the population changes from removing the manufacturer and kit joins. All fourteen focused scenarios passed, covering equal-cost OTS with below-cost ATS, below-cost OTS rejection, autoship eligibility, unchanged prices, duplicate SKU rows, kit-derived matches, directly matched kits, and unknown kit status exclusions, deferred MAP eligibility, invalid prices, tolerance, conflicting comparison prices, and missing comparison prices. Static checks also verified removal of manufacturer-table, kit-table, kit-discount, and MAP-flag dependencies, the current-row warehouse lookup, removal of the external connection setting, and REVIEW default.

This validates a subset of calculation/filter behavior, not SQL Server syntax, schema binding, the source joins, current data, or the SmartPak branch. Team SQL Server attempts exposed and led to fixes for batch splitting and the reserved RowCount alias, followed by missing snapshot and manufacturer-object checks. Successful end-to-end SQL Server execution has not yet been verified. No upload has occurred. Reconcile REVIEW output against a human-approved run before operational use; the current script is not a verified exact replacement for all human decisions.
