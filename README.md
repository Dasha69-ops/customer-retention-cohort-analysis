# Customer Retention & Cohort Analysis

SQL project analyzing customer purchasing behavior, retention, and revenue concentration for an online retailer, using the UCI Online Retail dataset.

## Business Scenario

An online retail company is acquiring new customers, but its management team doesn't know how many customers return to make another purchase, how long customers remain active, or which customer groups are more likely to return.

**Role:** Junior Data Analyst
**Main question:** Are customers returning to shop, and how does retention change over time?

## Dataset

[UCI Online Retail Dataset](https://archive.ics.uci.edu/dataset/352/online+retail) — real transaction data from a UK-based online retailer, covering December 2010 through December 2011 (~542,000 rows).

Fields: `InvoiceNo`, `StockCode`, `Description`, `Quantity`, `InvoiceDate`, `UnitPrice`, `CustomerID`, `Country`

## Tools

- MySQL 8.0 (all analysis; cleaning, cohort logic, retention calculations, window functions)
- Excel (retention heatmap visualization, conditional formatting)

## Methodology

**Customer definition:** A customer is identified by `CustomerID`. Transactions with no `CustomerID` (guest checkouts) were excluded, since retention and cohort behavior can only be measured for identifiable, returning individuals.

**Valid purchase definition:** A transaction was counted as valid only if:

- `Quantity > 0` and `UnitPrice > 0` (excludes data-entry errors and zero-value line items)
- The invoice was not a cancellation (`InvoiceNo` does not start with `'C'`)

**Order definition:** Multiple line items sharing the same `InvoiceNo` were treated as a single order. Order date is the earliest line-item timestamp within that invoice; order revenue is the sum of all line items within it.

**Repeat customer definition:** A customer is "returning" if they placed more than one distinct order. A customer with exactly one order is "first-time."

**Cohort assignment:** Each customer was assigned to a cohort based on the calendar month of their first valid purchase, truncated to month. Retention for each cohort is measured at each subsequent month ("cohort index"), counting how many of that cohort's customers placed at least one order in that specific month-after-joining, regardless of whether they'd been active in the months between.

**Handling incomplete observation periods:** Cohorts formed later in the dataset (particularly October–December 2011) have fewer subsequent months available for observation, since the dataset ends in December 2011. Their retention figures at higher checkpoints are not directly comparable to earlier, fully-observed cohorts, this is visible in the heatmap as a natural staircase of missing cells, and should be kept in mind when reading the late-2011 rows.

**Known data limitations:**

- Source data contained rows with blank `CustomerID` and `UnitPrice` (imported as NULL and excluded per the rules above), and required Latin-1 encoding correction during import.
- One outlier customer (`CustomerID 12346`) placed a single order of unusually high value (£77,183.60), which may disproportionately influence first-time customer revenue figures.

## Analysis Process

1. **Data cleaning** — filtered raw transactions per the validity rules above (`clean_transactions`)
2. **Order-level aggregation** — collapsed line items into one row per invoice (`orders`)
3. **Customer-level summary** — first purchase date, total orders, total spend, repeat-customer flag (`customer_summary`)
4. **Cohort assignment** — grouped customers by first-purchase month (`customer_cohort`)
5. **Monthly activity tracking** — mapped each customer's active months against their cohort start, producing a "months since joining" index for every order (`customer_activity`)
6. **Retention calculation** — joined cohort sizes against monthly active-customer counts to produce retention percentages (`cohort_size`, `cohort_retention_counts`, final retention query)
7. **Supplementary analysis** — repeat purchase timing between orders (`repeat_purchase_timing`), and revenue split between returning vs. first-time customers (`returning_vs_first_time_revenue`)

## Key SQL Skills Demonstrated

`GROUP BY` & aggregate functions · `CASE WHEN` · Views (`CREATE OR REPLACE VIEW`) · Date functions (`STR_TO_DATE`, `DATE_FORMAT`, `TIMESTAMPDIFF`, `DATEDIFF`) · `JOIN` · `COUNT(DISTINCT)` · Window functions (`LAG`, `SUM() OVER()`) · `ROUND`

## Key Findings

1. **Retention drops sharply after the first month, across every cohort.** Most cohorts fall from 100% (month 0) to roughly 15–25% by month 1, then plateau in a noisy 15–35% range rather than continuing to decline steadily, suggesting a large "one-and-done" segment, but relatively stable ongoing retention among those who do return once.

2. **Revenue is heavily concentrated among returning customers.** Returning customers make up ~65% of the customer base (2,845 of 4,338) but account for 93.1% of total revenue, while first-time customers (35% of the base) contribute only 6.9%. This is a sharper concentration than the commonly cited "20% of customers drive 80% of revenue" pattern.

3. **The December 2010 cohort shows an unusual retention spike at month 11 (November 2011)** 50.3%, well above its surrounding months (37.4% and 26.6%). Plausible explanations include a November promotional event, seasonal restocking ahead of the holidays, or a win-back campaign, though the dataset alone doesn't confirm the cause.

4. **Cohort size shows a seasonal uptick from September through November 2011**, rising from 169 new customers in August to 358 in October before dropping in the partial December cohort, consistent with increased holiday-season acquisition for a UK retailer.

## Recommendations

1. **Prioritize second-purchase conversion.** Since the steepest drop-off happens between month 0 and month 1, and retention stabilizes afterward, the highest-leverage intervention is likely a targeted push to get first-time customers to place a second order within ~30 days.

2. **Investigate the November 2011 retention spike** in the December 2010 cohort, and if it traces to a deliberate campaign, consider replicating that approach with other aging cohorts.

3. **Treat retention figures for cohorts from October 2011 onward as provisional**, and revisit once fuller observation windows are available.

## Repo Structure

```
/sql       -- all view definitions and the final retention query, in build order
/output    -- retention query CSV export, cohort heatmap image
README.md
```

## Limitations

This analysis is based on a single retailer's historical transaction data and does not account for external factors (marketing spend, seasonality drivers, site changes) that may have influenced the patterns observed. Retention is defined purely by purchase activity and does not capture other forms of engagement (site visits, email opens, etc.). Findings around specific spikes (e.g. the November 2011 retention jump) are hypotheses based on the data pattern alone, not confirmed causes.
