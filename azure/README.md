# RFM Segmentation on Azure

The [RFM customer segmentation project](../README.md) originally ran entirely in pandas on a laptop. This rebuilds the data layer on Azure: CSVs land in blob storage, load into a SQL warehouse, and the RFM scoring runs as T-SQL next to the data instead of pulling 2.6 million rows across the network.

Same 2,500 households, same eight segments, same four-page dashboard. Different plumbing underneath — and three defects the first build hadn't noticed.

---

## Architecture

```
7 local CSVs
   │  one-time upload (Azure Storage Explorer)
   ▼
ADLS Gen2  ──  data/raw/
   │  BULK INSERT, authenticated by managed identity
   ▼
Azure SQL Database (serverless, free offer)
   ├── stg      untyped landing, no constraints
   ├── silver   typed, keyed, deduplicated
   └── gold     rfm_household
   │  NTILE(5) quintile scoring
   ▼
Power BI Desktop  ──  Import mode, 4 pages
```

| Service | Choice | Why |
|---|---|---|
| Storage | ADLS Gen2, Standard, LRS, Hot | Same per-GB price as plain blob, real directories via hierarchical namespace |
| Warehouse | Azure SQL Database, serverless GP, free offer | 100,000 vCore-seconds and 32 GB per month, permanently, with overage billing disabled |
| Transform | T-SQL stored in `sql/` | Compute sits next to the data. `NTILE(5)` is the direct equivalent of `pd.qcut(q=5)` |
| Auth | System-assigned managed identity | No SAS token or storage key anywhere in the codebase |
| Region | Central India | Everything in one region; cross-region transfer is billed separately |

---

## Why not the bigger services

**Synapse dedicated SQL pool** is an MPP column-store engine built for terabyte scale, billed per hour whether queried or not. This dataset is 2.6 million rows. Sizing the tool to the data matters more than sizing it to the job title.

**Microsoft Fabric** has a 60-day trial, after which items in trial workspaces become inaccessible and the smallest capacity (F2) runs a few hundred dollars a month. A portfolio project that dies two months after it's built is worse than no portfolio project.

**Azure Data Factory** was deliberately left out. Orchestration earns its keep when there is something to orchestrate on a schedule. This load runs once. Adding ADF would have meant a pipeline with nothing to trigger it and a watermark table with nothing to watermark. It's the obvious next step, not a gap.

---

## Running it

Scripts run in order and each is safe to re-run.

| File | What it does |
|---|---|
| `sql/01_create_schema.sql` | Three schemas, 15 tables, one covering index |
| `sql/02_bulk_insert_staging.sql` | Managed identity setup, then seven loads with verification |
| `sql/03_staging_to_silver.sql` | Casts, deduplicates, enforces keys |
| `sql/04_rfm_transform.sql` | Quintile scoring and segment assignment |

Before running `02`, two things have to exist in the portal: the SQL server's system-assigned managed identity must be On, and that identity needs **Storage Blob Data Reader** on the storage account. Role assignments take a few minutes to propagate; a permissions error on the first attempt usually means waiting rather than misconfiguration.

`02` also needs a master key password substituting for the placeholder.

---

## What the data turned out to contain

Four things the rebuild surfaced. Three are defects pandas and the original dashboard had absorbed silently; the fourth is a divergence between the two implementations that's worth understanding rather than fixing.

### 56 rows of floating-point noise

`BULK INSERT` aborted at row 211,151 on a conversion error. The value was `5.551115E-17` in `SALES_VALUE` — floating-point residue from the source system's arithmetic, on a row with `QUANTITY = 0`. Semantically zero.

56 rows across the file, 63 values once `RETAIL_DISC` is included. pandas read them without comment because `float64` handles exponent notation natively. `BULK INSERT` cannot parse exponent notation into a `DECIMAL` target.

The fix was to land `stg.transactions` as `NVARCHAR` and cast in the transform layer, going through `FLOAT` first so the exponent parses, then `DECIMAL(10,2)` to round to `0.00`. That keeps load failures separate from data quality problems: the load always succeeds, and conversion becomes something measurable rather than fatal.

### 5,164 duplicate coupon rows

`silver.coupon` has a primary key on `(COUPON_UPC, PRODUCT_ID, CAMPAIGN)`. The load failed on it. The source holds 124,548 rows against 119,384 distinct combinations — 4.1% duplicates, with campaign 27 accounting for most and some combinations repeating 19 times.

Since the file has only those three columns, every duplicate is byte-identical and carries no extra information. Most likely the export dropped a dimension such as store or week. Deduplicated with `DISTINCT` on the way into silver, and the 4.1% gap between the two layers is a data quality number rather than a silent correction.

### Segment counts differ from pandas by up to 4 households

| Segment | SQL | pandas | Diff |
|---|---|---|---|
| At Risk | 568 | 565 | +3 |
| Champions | 512 | 509 | +3 |
| Lost | 500 | 500 | 0 |
| Loyal | 327 | 330 | −3 |
| Potential Loyalists | 302 | 306 | −4 |
| One-time Buyers | 199 | 198 | +1 |
| Low Value | 61 | 62 | −1 |
| New Customers | 31 | 30 | +1 |
| Others | 0 | 0 | 0 |

Base metrics match exactly: 2,500 households, recency 1–658, frequency 1–1,300, monetary $8.17–$38,319.79. The divergence is entirely in quintile assignment.

Recency is heavily tied at low values — 367 households last shopped 1 day before the reference date, 262 at 2 days, 194 at 3. `NTILE(5)` must produce exactly 500 rows per bucket, so the R=5/R=4 boundary falls inside the 2-day group at position 500 of a cumulative 629, splitting it by sort position. `pd.qcut` keeps tied values in the same bucket, which is why the pandas R buckets came out uneven at 436–629.

Neither is wrong. Around 15 households change R score and at most 4 move segment. `Lost` matches exactly at 500 because it's defined as `R = 1`, and `NTILE` guarantees that bucket's size — which confirms the mechanism rather than leaving it as a guess.

### A wrong measure in the dashboard, reporting Champions at half the real figure

This one wasn't a warehouse problem. It was found *because* of the warehouse.

With the data in SQL, "what share of coupon redemptions do Champions account for" became a query:

```sql
SELECT r.segment,
       COUNT(*) AS redemptions,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_all
FROM silver.coupon_redempt c
JOIN gold.rfm_household r ON r.household_key = c.household_key
GROUP BY r.segment
ORDER BY redemptions DESC;
```

Answer: Champions hold 1,408 of 2,318 redemptions, **60.74%**. The dashboard's 100% stacked bar had been showing roughly 30%.

The cause was feeding a *rate* into a visual that normalises *counts*. The Y well held `Coupon Redemption Rate` — redeeming households divided by total households — and a 100% stacked bar divides each category by the column total. Dividing one segment's rate by the sum of all eight segments' rates produces a number with no meaning. It happened to land near 44%, which looked plausible enough that nobody questioned it.

The fix is a second measure, not a reworked one:

```dax
Coupon Redemptions = COUNTROWS(coupon_redempt)          -- for share-of-total visuals
Coupon Redemption Rate =                                 -- for per-segment penetration
DIVIDE(
    DISTINCTCOUNT(coupon_redempt[household_key]),
    DISTINCTCOUNT(rfm_segments[household_key])
)
```

Both are correct and they answer different questions. A rate says how deeply a segment engages with coupons; a count says how much of the coupon budget a segment consumes. Only the count can be normalised to a share of total.

**The original pandas dashboard had the same bug.** It had been in the project since the Power BI build and survived a full review, because a plausible-looking percentage doesn't announce itself. Having the same number derivable two ways — in SQL and in DAX — is what exposed it. That's the strongest argument in this rebuild for pushing logic into a queryable layer: not performance, but the ability to check the BI layer against something.

---

## Repointing the dashboard

The warehouse replaced the CSV sources under an existing four-page report rather than a new one being built. Five things broke, all for reasons worth knowing.

**Table identity.** Power BI keys relationships and measures to table *names*, not to contents. Loading `gold.rfm_household` alongside the existing `rfm_segments` creates a second, unrelated table — every measure still points at the old one. The old tables were hidden, the new ones loaded, each measure repointed by hand, and only then were the originals deleted. Deleting first would have invalidated every measure at once with nothing to compare against.

**Demographics arrived split.** The silver layer keeps `hh_demographic` normalised, so the single wide CSV table became several. Visuals bound to the old column paths needed rebinding, not just a source swap.

**Calculated columns don't travel with the data.** `income_sort` and `month_seq` existed only in the report, not in the database. A reload brings data, not model objects, so both had to be recreated — and `income_sort` hit a circular dependency when written as a calculated column referencing a column that was itself sorting by it. Resolved by sorting on a plain integer column with no reverse reference.

**`CALCULATE` intersects across columns but replaces within one.** MoM Growth % returned blank after the reload because the measure's previous-month filter was being intersected with the visual's own month filter, producing an empty set. `REMOVEFILTERS` on the date table inside the `CALCULATE` restores the behaviour. This is the single most common DAX misunderstanding and it only surfaces once a visual filters the same column the measure does.

**Format strings are inherited on duplication.** `Coupon Redemptions`, created by duplicating the rate measure, inherited its percentage format and rendered 2,318 as `231,800.0%`. A new measure needs its format set explicitly; duplicating one carries baggage.

**Import, not DirectQuery.** The model loads data on refresh rather than querying live. DirectQuery against a serverless database would wake it on every slicer click, and the free offer's budget is 100,000 vCore-seconds a month against a 0.5 vCore floor while awake. Import also means the published `.pbix` works for anyone who opens it, with no credentials and no live server. The trade-off is that the report is as fresh as its last refresh — correct for a dataset that hasn't changed since 2019.

One thing that wasn't a bug: slicers are scoped to their page in Power BI. A segment slicer on page 2 does not filter page 3 unless **View → Sync slicers** says so. Here they were deliberately left unsynced, because pages 1 and 3 compare all eight segments against each other and a filter would collapse the comparison.

---

## Cost

| Resource | Now | After 12 months |
|---|---|---|
| Azure SQL free offer | $0 | $0, for the lifetime of the subscription |
| Blob storage (~250 MB) | $0 (5 GB free) | ~$0.005/month at $0.018/GB hot LRS |

The SQL free offer is set to **auto-pause when the monthly limit is reached** rather than continue with charges, which makes it a hard cap rather than an alert. A ₹5 budget alert sits on top as a second layer, though Azure budgets only notify — there is no general hard spending cap on pay-as-you-go, which is why the auto-pause setting is the one that actually matters.

Serverless auto-pause matters more than it looks. An idle but awake database bills at the 0.5 vCore floor, 1,800 vCore-seconds an hour, so a query tool left connected drains the monthly allowance while doing nothing.

---

## What I'd change at scale

**Incremental loading.** Every run is currently a full reload. At 2.6M rows that takes under a minute, so it isn't worth the complexity. Past roughly 50M rows it would be: partition the fact table by day, keep a watermark table holding the last successfully loaded partition, and load only what's new. The source day-partitioned files for this already exist in `data/bronze/` from an earlier iteration.

**Delete-insert at partition grain over row-level MERGE.** For a day-partitioned load, deleting and reinserting whole days is idempotent at the grain the pipeline actually operates on, and avoids needing a reliable row-level match condition. At larger scale, partition switching makes the same operation metadata-only.

**Orchestration.** Azure Data Factory with a daily schedule trigger, a Lookup activity reading the watermark, Copy for movement and Stored Procedure for the transform. Mapping Data Flows would be avoided — they spin up a Spark cluster billed per vCore-hour with an 8-vCore minimum, and everything they do here a stored procedure does for free.

**Run history.** A `ctl.load_audit` table recording pipeline name, row counts, status and timestamps per run, so "did last night's load work" is answerable in SQL rather than by reading the orchestrator's monitoring UI.

**Network isolation.** Public network access is currently enabled on both storage and SQL, gated by firewall rules and an IP allowlist. In a production environment both would sit behind private endpoints on a VNet.

**Least privilege.** The managed identity has Storage Blob Data Reader, scoped to read because the pipeline only reads. Adding an export step would require Contributor, and that's the point at which the scope should be revisited rather than granted pre-emptively.

**Data quality as a first-class output.** The findings above were discovered by things failing — or, in the coupon measure's case, by someone happening to check. A mature pipeline would assert them: row count reconciliation between layers, a check that the staging-to-silver delta stays within expected bounds, and alerting when it doesn't. The BI layer deserves the same treatment: a handful of headline numbers tested against SQL on each refresh would have caught the coupon measure the day it was written.

---

## Notes

The `data/bronze/` folder in blob storage holds `transaction_data.csv` split into 711 day-partitions plus the reference tables. It was built for an incremental-loading design that was later scoped out. Left in place because it costs nothing and is the starting point if orchestration gets added.

`causal_data.csv` (36.7M rows) is excluded. It holds in-store display and mailer exposure at product × store × week grain, with no `household_key`. It joins to transactions on `PRODUCT_ID`, `STORE_ID` and `WEEK_NO` and would support a promotional lift analysis by segment, which is a separate piece of work with its own methodology questions rather than an extension of household-level RFM.
