CREATE DATABASE retail_analysis;

USE retail_analysis;

CREATE TABLE online_retail (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(255),
    Quantity INT,
    InvoiceDate VARCHAR(30),
    UnitPrice DECIMAL(10 , 2 ),
    CustomerID VARCHAR(20),
    Country VARCHAR(50)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/online_retail.csv'
INTO TABLE online_retail
CHARACTER SET latin1
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(InvoiceNo, StockCode, Description, Quantity, InvoiceDate, @UnitPrice, @CustomerID, Country)
SET
    CustomerID = NULLIF(@CustomerID, ''),
    UnitPrice = NULLIF(@UnitPrice, '');

-- STEP 1: CLEAN TRANSACTIONS
-- Rules (methodology):
--     - CustomerID must not be null (guest checkouts excluded)
--     - Cancelled orders (InvoiceNo starts with 'C') excluded
--     - Quantity and UnitPrice must be positive
--     - InvoiceDate parsed from text to a real datetime

CREATE OR REPLACE VIEW clean_transactions AS
    SELECT 
        InvoiceNo,
        CustomerID,
        STR_TO_DATE(InvoiceDate, '%m/%d/%Y %H:%i') AS invoice_date,
        StockCode,
        Quantity,
        UnitPrice,
        ROUND(Quantity * UnitPrice, 2) AS line_revenue
    FROM
        online_retail
    WHERE
        CustomerID IS NOT NULL AND Quantity > 0
            AND UnitPrice > 0
            AND InvoiceNo NOT LIKE 'C%';

--  STEP 2: ORDERS
--  Collapse line items into one row per invoice (one "order").

CREATE OR REPLACE VIEW orders AS
    SELECT 
        InvoiceNo,
        CustomerID,
        MIN(invoice_date) AS order_date,
        SUM(line_revenue) AS order_revenue
    FROM
        clean_transactions
    GROUP BY InvoiceNo , CustomerID;

-- STEP 3: CUSTOMER SUMMARY
--   One row per customer -- total orders, first purchase date,
--   total spend, and a repeat-customer flag (1 = repeat, 0 = not).

CREATE OR REPLACE VIEW Customer_summary AS
    SELECT 
        CustomerID,
        COUNT(DISTINCT (InvoiceNo)) AS total_order_per_customer,
        MIN(order_date) AS first_purchase_date,
        SUM(order_revenue) AS customer_total_spend,
        CASE
            WHEN COUNT(DISTINCT (InvoiceNo)) > 1 THEN TRUE
            ELSE FALSE
        END AS customer_return_case
    FROM
        orders
    GROUP BY CustomerID;

-- STEP 4: COHORT ASSIGNMENT
--   Every customer's cohort = the month of their first purchase.

CREATE OR REPLACE VIEW customer_cohort AS
    SELECT 
        CustomerID,
        DATE(DATE_FORMAT(first_purchase_date, '%Y/%m/01')) AS cohort_month
    FROM
        customer_summary;

-- STEP 5: CUSTOMER ACTIVITY
--   One row per customer per active month, with cohort_index = how many months after joining that activity happened.
--   Note the asymmetry:
--     - activity_month has NO MIN() -- it IS the GROUP BY column, already deterministic.
--     - cohort_index KEEPS MIN() around o.order_date, since multiple order dates can exist within one grouped month 
--       and MIN() picks one deterministically (doesn't matter which, since we're truncating to month anyway).

CREATE OR REPLACE VIEW customer_activity AS
SELECT
    o.CustomerID,
    DATE(DATE_FORMAT(o.order_date, '%Y-%m-01')) AS activity_month,
    cc.cohort_month,
    TIMESTAMPDIFF(
        MONTH,
        cc.cohort_month,
        DATE(DATE_FORMAT(MIN(o.order_date), '%Y-%m-01'))
    )  AS cohort_index
FROM orders AS o
JOIN customer_cohort AS cc ON o.CustomerID = cc.CustomerID
GROUP BY o.CustomerID, activity_month, cc.cohort_month;


-- STEP 6: COHORT SIZE
--   How many customers total belong to each cohort, the denominator for retention %.

CREATE OR REPLACE VIEW cohort_size AS
SELECT
    cohort_month,
    COUNT(DISTINCT CustomerID) AS total_no_of_customer_per_cohort
FROM customer_cohort
GROUP BY cohort_month;


-- STEP 7: COHORT RETENTION COUNTS
--  How many distinct customers from each cohort were active at each checkpoint (cohort_index), the numerator for retention %.

CREATE OR REPLACE VIEW cohort_retention_counts AS
    SELECT 
        COUNT(DISTINCT CustomerID) AS num_retained,
        cohort_month,
        cohort_index
    FROM
        customer_activity
    GROUP BY cohort_month , cohort_index;

-- STEP 8: FINAL RETENTION % TABLE
--   The heatmap output. INNER JOIN is safe here, both views trace back to the same customer base, so no cohort_month can
--   exist in one without existing in the other.

SELECT 
    r.cohort_month,
    r.cohort_index,
    r.num_retained,
    s.total_no_of_customer_per_cohort AS cohort_size,
    ROUND(100.0 * r.num_retained / s.total_no_of_customer_per_cohort,
            1) AS retention_pct
FROM
    cohort_retention_counts r
        INNER JOIN
    cohort_size s ON r.cohort_month = s.cohort_month
ORDER BY r.cohort_month , r.cohort_index;


-- REPEAT PURCHASE TIMING
--   Days between a customer's consecutive orders, using LAG to look back at the previous row within each customer's history.
--   First order for any customer will show NULL (no previous order exists) expected, not a bug.

CREATE OR REPLACE VIEW repeat_purchase_timing AS
SELECT CustomerID,
order_date,
LAG(order_date) OVER(PARTITION BY CustomerID ORDER BY order_date) AS previous_order_date,
DATEDIFF(order_date, LAG(order_date) OVER(PARTITION BY CustomerID ORDER BY order_date)) AS days_since_last_order
FROM orders;

-- OR

SELECT CustomerID,
order_date,
LAG( order_date) OVER(PARTITION BY CustomerID ORDER BY order_date) AS previous_order_date,
DATEDIFF(order_date, LAG( order_date) OVER(PARTITION BY CustomerID ORDER BY order_date)) AS days_since_last_order
FROM orders
ORDER BY CustomerID;

-- RETURNING VS FIRST-TIME CUSTOMER REVENUE
--  Revenue split between repeat and one-time customers, with each bucket's share of total revenue as a percentage.

CREATE OR REPLACE VIEW returning_vs_first_time_revenue AS 
SELECT 
CASE WHEN customer_return_case = 1 THEN  'Returning'
            ELSE 'First_time'
        END AS customer_type,
COUNT(CustomerID) AS customer_count_per_bucket,
SUM(customer_total_spend) AS total_revenue_per_bucket,
ROUND(SUM(customer_total_spend)/SUM(SUM(customer_total_spend)) OVER () * 100, 1) AS percentage_of_total_customer_spend_per_bucket
FROM customer_summary
GROUP BY customer_type;
