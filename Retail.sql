-- 1. Когортний аналіз с LTV, Retention
-- Колонки: Cohort_month - month_offset - active_users - cohort_size - total_ltv - retention_rate
WITH first_orders AS (
  SELECT "Customer ID", min("InvoiceDate"::TIMESTAMP) AS first_order_date
  FROM public.online_retail_ii
  GROUP BY "Customer ID"
),
orders_with_cohort AS (
  SELECT
    o."Customer ID",
    o."Price",
    o."Quantity",
    DATE_TRUNC('quarter', o."InvoiceDate"::timestamp) AS order_quarter,
	DATE_TRUNC('quarter', f.first_order_date) AS cohort_quarter,
	(EXTRACT(YEAR FROM o."InvoiceDate"::timestamp) - EXTRACT(YEAR FROM f.first_order_date)) * 4
	+ (EXTRACT(QUARTER FROM o."InvoiceDate"::timestamp) - EXTRACT(QUARTER FROM f.first_order_date)) AS quarter_offset
  FROM public.online_retail_ii o
  JOIN first_orders f ON o."Customer ID" = f."Customer ID"
),
active_users_by_cohort AS (
	SELECT
		cohort_quarter,
		quarter_offset,
		count(DISTINCT "Customer ID") AS active_users
	FROM orders_with_cohort
	GROUP BY cohort_quarter, quarter_offset
),
cohort_sizes AS (
	SELECT 
		cohort_quarter, 
		active_users AS cohort_size
	FROM active_users_by_cohort
	WHERE quarter_offset = 0
),
ltv_by_cohort AS (
	SELECT 
		cohort_quarter,
		quarter_offset,
		ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS total_ltv
	FROM orders_with_cohort
	GROUP BY cohort_quarter, quarter_offset
),

-- active_users_by_cohort a: cohort_quarter, quarter_offset, active_users
-- cohort_sizes c: cohort_size
-- ltv_by_cohort l: total_ltv
-- retention рахується вже тут
cohort_ltv_retention AS (
	SELECT 
		a.cohort_quarter,
		a.quarter_offset,
		a.active_users,
		c.cohort_size,
		l.total_ltv,
		ROUND((a.active_users::REAL / c.cohort_size::REAL)::NUMERIC, 3) AS retention_rate
	FROM active_users_by_cohort a
	LEFT JOIN cohort_sizes c ON a.cohort_quarter = c.cohort_quarter
	LEFT JOIN ltv_by_cohort l ON a.cohort_quarter = l.cohort_quarter AND a.quarter_offset = l.quarter_offset
	ORDER BY a.cohort_quarter
)
SELECT * FROM cohort_ltv_retention;


-- 2. Рахуємо метрики RFM по клієнтам
-- Стовбці: Customer ID, recency(Давність), frequency (частота), monetary (сколько потратил)
WITH rfm_base AS (
  SELECT
    "Customer ID",
    MAX("InvoiceDate"::timestamp) AS last_order_date,
    COUNT(*) AS frequency,
    ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS monetary
  FROM public.online_retail_ii
  GROUP BY "Customer ID"
)
SELECT
  "Customer ID",
  '2011-12-09 12:50:00'::timestamp - last_order_date AS recency, -- это макс дата 
  frequency,
  monetary
FROM rfm_base
WHERE "Customer ID" IS NOT NULL;


-- 2.1 Формування RFM-сегментів
WITH rfm_base AS (
  SELECT
    "Customer ID",
    MAX("InvoiceDate"::timestamp) AS last_order_date,
    COUNT(*) AS frequency,
    ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS monetary
  FROM public.online_retail_ii
  WHERE "Customer ID" IS NOT NULL
  GROUP BY "Customer ID"
),
rfm_ranked AS (
 	SELECT "Customer ID",
    	NTILE(5) OVER (ORDER BY '2011-12-09 12:50:00'::timestamp - last_order_date DESC) AS r_score,
    	NTILE(5) OVER (ORDER BY frequency) AS f_score,
    	NTILE(5) OVER (ORDER BY monetary) AS m_score
  	FROM rfm_base
),
rfm_final AS (
SELECT
  "Customer ID",
  r_score::text || f_score::text || m_score::text AS rfm_segment,
  r_score,
  f_score,
  m_score 
FROM rfm_ranked
)
SELECT *
FROM rfm_final;

SELECT sum("Quantity" * "Price")
FROM public.online_retail_ii;

-- По країнам
SELECT "Country", ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS "total amount", count(DISTINCT "Customer ID") AS "Number of active users"
FROM public.online_retail_ii
GROUP BY "Country"
ORDER BY "total amount" desc; 

-- по країнам топ 10 по клієнтам
SELECT "Country", ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS "total amount", count(DISTINCT "Customer ID") AS "Number of active users"
FROM public.online_retail_ii
GROUP BY "Country"
ORDER BY "Number of active users" DESC
LIMIT 10; 


-- По дням
	SELECT 	date_trunc('day', "InvoiceDate"::timestamp) AS day,
			ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS "Revenue This Day",
			count(DISTINCT "Customer ID") AS "Number of active users",
			ROUND(ROUND(SUM(("Quantity" * "Price")::numeric), 2)/count(DISTINCT "Customer ID"), 2) AS "ARPDAU"
	FROM public.online_retail_ii
	GROUP BY date_trunc('day', "InvoiceDate"::timestamp);
	
-- По клієнтам
WITH CustomerID_grouped AS (
	SELECT
	  	"Customer ID",
	  	DATE_TRUNC('month', MIN("InvoiceDate"::timestamp)) AS cohort_month,
	 	max("Country") AS "Country", 
	 	count(DISTINCT "Invoice") AS "Number of unique Invoice",
	 	'2011-12-09 12:50:00'::timestamp - MAX("InvoiceDate"::timestamp) AS recency,
	    COUNT(*) AS frequency,
	    ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS monetary
	FROM public.online_retail_ii
	WHERE "Customer ID" IS NOT NULL
	GROUP BY "Customer ID"
	ORDER BY "Customer ID"
)
	SELECT	"Customer ID", cohort_month, "Country", "Number of unique Invoice",
			pg_typeof(EXTRACT(DAY FROM recency)) AS recency_days, frequency, monetary,
			NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
			NTILE(5) OVER (ORDER BY frequency) AS f_score,
			NTILE(5) OVER (ORDER BY monetary) AS m_score
	FROM CustomerID_grouped;

-- 10 найприбутковіших товарів
SELECT "Description", ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS total_revenue
FROM public.online_retail_ii
GROUP BY "Description"
ORDER BY total_revenue DESC
LIMIT 10

-- Топ 10 країн по витратам
SELECT "Country", ROUND(SUM(("Quantity" * "Price")::numeric), 2) AS total_revenue
FROM public.online_retail_ii
GROUP BY "Country"
ORDER BY total_revenue DESC
LIMIT 10
