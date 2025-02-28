  -- PRODUCT PERFORMANCE

-- Q1. What are the company's top products? What are the best-selling products by order count? By revenue?
    
/* This query uses two CTEs: the first CTE returns the order count and revenue (in millions of dollars for improved readability) for each product,
and the second CTE converts these metrics into percentages and ranks each product by its sales or revenue performance. 
The final query computes a cumulative sum of the percent revenue to understand which combination of products drive the lion's share of total revenue. */

-- first check the different product names to see if cleaning is required
SELECT DISTINCT product_name
FROM core.orders;

WITH product_stats AS (
  -- clean product name
  SELECT CASE WHEN product_name = '27in"" 4k gaming monitor' THEN '27in 4K gaming monitor' 
      ELSE product_name 
      END AS product_name_clean,  
    COUNT(id) AS order_count,
    ROUND(SUM(usd_price)/1e6, 1) AS revenue_in_mill
  FROM core.orders
  GROUP BY 1),

 pct_stats AS (
  SELECT *,
    ROUND((order_count / SUM(order_count) OVER ())*100, 2) AS pct_order_count, 
    ROUND((revenue_in_mill / SUM(revenue_in_mill) OVER ())*100, 2) AS pct_revenue,
    RANK() OVER (ORDER BY order_count DESC) AS ranking_by_sales,
    RANK() OVER (ORDER BY revenue_in_mill DESC) AS ranking_by_revenue
  FROM product_stats)

SELECT *,
  ROUND(SUM(pct_revenue) OVER (ORDER BY pct_revenue DESC), 2) AS cum_pct_revenue
FROM pct_stats;
-- Insights:
-- 4 out of the company's 8 product offerings accounted for 96% of the total revenue (4K Gaming Monitor, Apple Airpods Headphones, Macbook Air Laptop, ThinkPad Laptop).
-- The Apple Airpods Headphones are the company's best-selling product, accounting for 45% of all sales for a total revenue of $7.7M.
-- Revenue-wise, the 27in 4K Gaming Monitor is the most profitable product, accounting for $9.9M in total revenue. 
  

-- Q2. Are there certain products that are getting refunded more frequently than others?

/* This query calculates the AOV, total refund count, and refund rate for each product based on data from the `orders` table joined to the `order_status` table. 
A binary helper column is created using CASE to indicate whether an order was refunded (0 = not refunded, 1 = refund). 
Based on this binary helper column, a refund count is calculated using SUM() and a refund rate is calculated using AVG(). 
The output is ordered by highest refund rate to lowest. */

SELECT CASE WHEN product_name = '27in"" 4k gaming monitor' THEN '27in 4K gaming monitor' 
	ELSE product_name 
	END AS product_name_clean,
  ROUND(AVG(usd_price), 2) AS aov,
  SUM(CASE WHEN refund_ts IS NOT NULL THEN 1 ELSE 0 END) AS refund_count,
  ROUND(AVG(CASE WHEN refund_ts IS NOT NULL THEN 1 ELSE 0 END)*100, 2) AS refund_rate
FROM core.orders
LEFT JOIN core.order_status
  ON orders.id = order_status.order_id
GROUP BY 1
ORDER BY 4 DESC;
-- Insights:
-- Products with the highest AOVs, such as Macbook Air Laptop, ThinkPad Laptop, Apple iPhone, had the highest refund rates.
-- Though the 27in 4K Gaming Monitor and the Apple Airpods Headphones are the company's best-performing products, they had lower refund rates. 


-- Q3. What was the most-purchased brand in each region?

/* This query uses a CTE to pull data from the `orders` table joined to the `customers` and `geo_lookup` tables. 
CASE is used to assign each product to a brand, and the data is grouped by region and brand to get an order count for each region-brand pair using COUNT(). 
The final query converts the order counts to a percentage based on the total order count across all brands in that region, and brands are ranked within each region based on order count. 
The QUALIFY clause is used to return the top-ranked brands in each region. */

WITH region_brand_count AS (
  SELECT geo_lookup.region,
    CASE WHEN LOWER(product_name) LIKE ANY ('%apple%', '%macbook%') THEN 'Apple'
      WHEN LOWER(product_name) LIKE '%samsung%' THEN 'Samsung'
      WHEN LOWER(product_name) LIKE '%thinkpad%' THEN 'Lenovo'
      WHEN LOWER(product_name) LIKE '%bose%' THEN 'Bose'
      ELSE 'Unknown' END AS brand,
    COUNT(orders.id) AS order_count
  FROM core.orders
  LEFT JOIN core.customers
    ON orders.customer_id = customers.id
  INNER JOIN core.geo_lookup
    ON customers.country_code = geo_lookup.country
  GROUP BY 1, 2)

SELECT *,
  ROUND((order_count / SUM(order_count) OVER (PARTITION BY region))*100, 2) AS pct_order_count,
  RANK() OVER (PARTITION BY region ORDER BY order_count DESC) AS ranking,
FROM region_brand_count
QUALIFY ranking = 1;
-- Insight: Apple was the most-purchased brand across all regions, driving 40% - 51% of total sales.


  -- OPERATIONAL EFFICIENCY 

-- Q1. What was the average time to deliver for each region? What was the average time spent in processing before an order was shipped?

/* Data is pulled from the `orders` table joined to the `order_status`, `customers`, and `geo_lookup` tables. 
DATE_DIFF() is used on the relevant columns to calculate the days spent in different stages of delivery, and an average time for each delivery stage is calculated for each region with AVG(). 
The final output is ordered by the longest overall delivery time. */

SELECT geo_lookup.region,
  ROUND(AVG(DATE_DIFF(order_status.ship_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_ship,
  ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.ship_ts, day)), 1) AS avg_days_in_transit,
  ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_deliver
FROM core.orders
LEFT JOIN core.order_status
  ON orders.id = order_status.order_id
LEFT JOIN core.customers
  ON orders.customer_id = customers.id
INNER JOIN core.geo_lookup
  ON customers.country_code = geo_lookup.country
GROUP BY 1
ORDER BY 4 DESC;
-- Insight: NA and LATAM had slightly shorter delivery times compared to APAC and EMEA, though the differences between regions are not substantial. 


-- Q2. Does the average delivery time differ between loyalty program customers and non-loyalty customers?

/* This query is similar to the one above, but groups by loyalty status (0 = non-loyalty, 1 = loyalty) instead of region. 
Because customer region was not needed, the `geo_lookup` table was not necessary in the join. */

SELECT customers.loyalty_program,
  ROUND(AVG(DATE_DIFF(order_status.ship_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_ship,
  ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.ship_ts, day)), 1) AS avg_days_in_transit,
  ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_deliver
FROM core.orders
LEFT JOIN core.customers
  ON orders.customer_id = customers.id
LEFT JOIN core.order_status
  ON orders.id = order_status.order_id
WHERE customers.loyalty_program IS NOT NULL
GROUP BY 1;
-- Insight: Loyalty and non-loyalty program customers experience the same average shipping, transit, and overall delivery times (7.5 days).


-- Q3. What were the quarterly trends in average delivery time?

/* This query pulls in data by joining `orders` and `order_status` tables. 
A CTE is used to compute the average time in days for shipping, transit, and overall time to delivery for each quarter (using DATE_TRUNC()).
The final query calculates a quarter-over-quarter percent difference in  shipping, transit, and overall delivery times using the LAG() window function. */

WITH quarterly_trends AS (
  SELECT DATE_TRUNC(order_status.purchase_ts, QUARTER) as purchase_quarter,
    ROUND(AVG(DATE_DIFF(order_status.ship_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_ship,
    ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.ship_ts, day)), 1) AS avg_days_in_transit,
    ROUND(AVG(DATE_DIFF(order_status.delivery_ts, order_status.purchase_ts, day)), 1) AS avg_days_to_deliver
  FROM core.orders
  LEFT JOIN core.order_status
    ON orders.id = order_status.order_id
  WHERE order_status.purchase_ts IS NOT NULL
  GROUP BY 1
  ORDER BY 1)

SELECT *,
  ROUND((avg_days_to_ship/LAG(avg_days_to_ship) OVER (ORDER BY purchase_quarter ASC) - 1)*100, 2) AS shipping_diff,
  ROUND((avg_days_in_transit/LAG(avg_days_in_transit) OVER (ORDER BY purchase_quarter ASC) - 1)*100, 2) AS transit_diff,
  ROUND((avg_days_to_deliver/LAG(avg_days_to_deliver) OVER (ORDER BY purchase_quarter ASC) - 1)*100, 2) AS delivery_diff
FROM quarterly_trends
ORDER BY 1 ASC; 
-- Insights:
-- Between Q1 and Q2 of 2019, there was on average a 60% increase in order shipping time, and overall delivery time increased by ~18%.
-- Operational efficiency improved between Q2 and Q3 of the same year, due mainly to a decrease in order shipping time. 
-- Logistics remained consistent throughout 2020 in spite of the pandemic, with a small reduction in shipping time in Q4 2020. However, this gain in efficiency was reversed in Q1 2021.


  -- MARKETING CHANNEL PERFORMANCE 

-- Q1. Which marketing channels contribute most to sales? Does this differ between regions?

/* This query pulls in data by joining `orders`, `customers`, and `geo_lookup` tables.
Rows with missing values for marketing channel are filtered out.
The CTE computes the total number of orders (COUNT()) and total revenue (SUM()) for each marketing channel and region pair.
The final query ranks the different channels in each region based on order count and revenue.
The output is ordered by the channel-region pair so it is easy to see how a particular channel has performed in each region across the selected metrics. */

-- first check the different marketing channels to see if there are missing values
SELECT DISTINCT marketing_channel
FROM core.customers;
-- the check reveals that there are missing values in the marketing_channel column

WITH marketing_channel_stats AS (
  SELECT customers.marketing_channel,
    geo_lookup.region,
    COUNT(DISTINCT orders.id) AS order_count,
    ROUND(SUM(orders.usd_price), 2) AS revenue
  FROM core.orders
  LEFT JOIN core.customers
    ON orders.customer_id = customers.id
  INNER JOIN core.geo_lookup
    ON customers.country_code = geo_lookup.country
  WHERE customers.marketing_channel IS NOT NULL
  GROUP BY 1, 2)

SELECT *,
	RANK() OVER (PARTITION BY region ORDER BY order_count DESC) AS order_count_rank,
	RANK() OVER (PARTITION BY region ORDER BY revenue DESC) AS revenue_rank
FROM marketing_channel_stats
ORDER BY 1, 2; 
-- Insights:
-- The top two most effective marketing channels across all regions by both order count and revenue were 1) direct and 2) email. 
-- Social media was the least effective marketing channel across all regions.


-- Q2. Within each purchase platform, what are the top two marketing channels ranked by average order value?

/* This query joins the `orders` and `customers` tables and groups by purchase_platform and marketing_channel. 
For each platform-channel pair, the AOV is computed using AVG(). 
Within each purchase platform, the marketing channels are ranked by their AOV using a RANK window function. 
The QUALIFY statement filters the rankings to return only the top two channels, and the final output is ordered alphabetically by the purchase_platform. */

SELECT orders.purchase_platform,
  customers.marketing_channel,
  ROUND(AVG(usd_price), 2) AS aov,
  RANK() OVER (PARTITION BY purchase_platform ORDER BY AVG(usd_price) DESC) AS ranking
FROM core.orders
LEFT JOIN core.customers
  ON orders.customer_id = customers.id
GROUP BY 1, 2
QUALIFY ranking <= 2
ORDER BY 1;
-- Insights:
-- For customers who purchased on mobile, social media and affiliate marketing drove the highest AOV. 
-- For customers who purchased on the website, affiliate and direct marketing drove the highest AOV.


-- Q3. Which marketing channel has the highest average signup rate for the loyalty program? How does this compare to the channel that has the highest number of loyalty program participants?

/* This query analyzes loyalty program signup rate in each marketing channel over time to understand which marketing channel was most effective in driving loyalty signups, 
and compares it to the channel with the highest total number of loyalty customers. 
Only the known marketing channels (email, direct, affiliate, and social media) are considered.
The CTE calculates the loyalty program signup rate and the number of loyalty signups for each channel across all years. 
The final query calculates the number of loyalty signups as a percentage of total loyalty customers. */

WITH loyalty_stats AS (
SELECT marketing_channel,
    ROUND(AVG(loyalty_program)*100, 2) AS loyalty_rate,
    SUM(loyalty_program) AS loyalty_customers,
  FROM core.customers
  WHERE marketing_channel IN ('email', 'direct', 'affiliate', 'social media') -- filter out missing values and unknown channel
  GROUP BY 1
  ORDER BY 1, 2)

SELECT *,
  ROUND(loyalty_customers / SUM(loyalty_customers) OVER ()*100, 2) AS pct_loyalty
FROM loyalty_stats
ORDER BY loyalty_rate DESC;
-- Insights: 
-- On average, email marketing drove the highest loyalty program enrollment rates across all years (59%).
-- Direct marketing had the highest number of loyalty program customers overall (73% of all loyalty signups at 23K). 
