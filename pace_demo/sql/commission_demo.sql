-- CREATE DATABASE:
CREATE DATABASE IF NOT EXISTS pace_demo
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- COMMISSION DEMO: Logistics (DDL + SAMPLE + CALC + CHECKS)
DROP TABLE IF EXISTS commission_adjustments;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS commission_policy;
DROP TABLE IF EXISTS commission_tiers;
DROP TABLE IF EXISTS employees;

CREATE TABLE employees (
  employee_id INT PRIMARY KEY,
  full_name   TEXT NOT NULL,
  department  TEXT,
  hire_date   DATE,
  is_active   BOOLEAN DEFAULT TRUE
);

CREATE TABLE orders (
  order_id      BIGINT PRIMARY KEY,
  order_date    DATE NOT NULL,
  employee_id   INT REFERENCES employees(employee_id),
  revenue_usd   NUMERIC(12,2) NOT NULL,
  cost_usd      NUMERIC(12,2) NOT NULL,
  is_chargeback BOOLEAN DEFAULT FALSE
);

CREATE TABLE commission_tiers (
  tier_id     INT PRIMARY KEY,
  margin_from NUMERIC(5,2),
  margin_to   NUMERIC(5,2),
  rate_pct    NUMERIC(5,2)
);

CREATE TABLE commission_adjustments (
  adj_id      BIGINT PRIMARY KEY,
  employee_id INT REFERENCES employees(employee_id),
  adj_date    DATE NOT NULL,
  amount_usd  NUMERIC(12,2) NOT NULL,
  reason      TEXT
);

CREATE TABLE commission_policy (
  policy_id     INT PRIMARY KEY,
  period_start  DATE NOT NULL,
  period_end    DATE NOT NULL,
  orders_target INT,
  target_bonus  NUMERIC(12,2),
  payout_cap    NUMERIC(12,2)
);

INSERT INTO employees (employee_id, full_name, department, hire_date, is_active) VALUES
(1001, 'John Smith', 'Dispatch', DATE '2023-03-10', 1),
(1002, 'Maria Lopez', 'Operations', DATE '2022-08-25', 1),
(1003, 'Kevin Lee', 'Dispatch', DATE '2024-01-12', 1),
(1004, 'Alice Brown', 'Sales Ops', DATE '2021-06-01', 1),
(1005, 'David Clark', 'Sales Ops', DATE '2020-11-20', 1),
(1006, 'Sofia Martinez', 'Dispatch', DATE '2023-07-15', 1);

INSERT INTO commission_tiers (tier_id, margin_from, margin_to, rate_pct) VALUES
(1.00, 0.00, 20.00, 1.50),
(2.00, 20.00, 30.00, 2.00),
(3.00, 30.00, NULL, 2.50);

INSERT INTO commission_policy (policy_id, period_start, period_end, orders_target, target_bonus, payout_cap) VALUES
(1, DATE '2025-09-01', DATE '2025-09-30', 100, 200.00, 3000.00);

INSERT INTO commission_adjustments (adj_id, employee_id, adj_date, amount_usd, reason) VALUES
(1, 1001, DATE '2025-09-20', 150.00, 'QA bonus'),
(2, 1004, DATE '2025-09-28', -120.00, 'Chargeback correction'),
(3, 1002, DATE '2025-09-12', 75.00, 'Spot bonus');

-- COPY full orders from CSV if needed; here are sample INSERTs:

INSERT INTO orders (order_id, order_date, employee_id, revenue_usd, cost_usd, is_chargeback) VALUES
(548, '2025-09-30', 1006, 80.00, 48.38, 0),
(82, '2025-09-27', 1001, 203.53, 169.48, 0),
(141, '2025-09-16', 1002, 394.54, 329.28, 0),
(80, '2025-09-26', 1001, 455.21, 364.95, 0),
(273, '2025-09-29', 1003, 450.88, 305.51, 0),
(361, '2025-09-23', 1004, 222.19, 153.73, 0),
(496, '2025-09-12', 1006, 384.45, 317.41, 0),
(480, '2025-09-06', 1006, 430.56, 270.59, 0),
(83, '2025-09-27', 1001, 536.34, 422.98, 0),
(362, '2025-09-23', 1004, 313.37, 190.04, 0),
(186, '2025-09-26', 1002, 480.98, 307.25, 0),
(11, '2025-09-04', 1001, 442.08, 349.42, 0),
(84, '2025-09-28', 1001, 297.26, 245.43, 0),
(223, '2025-09-11', 1003, 275.22, 218.77, 0),
(291, '2025-09-06', 1004, 386.32, 328.32, 0),
(85, '2025-09-28', 1001, 287.22, 236.64, 0),
(524, '2025-09-19', 1006, 214.79, 158.61, 0),
(7, '2025-09-03', 1001, 221.30, 134.82, 0),
(347, '2025-09-19', 1004, 366.02, 291.17, 0),
(258, '2025-09-25', 1003, 86.14, 66.62, 0),
(262, '2025-09-26', 1003, 338.10, 236.47, 0),
(156, '2025-09-19', 1002, 248.02, 150.89, 0),
(132, '2025-09-13', 1002, 415.20, 282.72, 0),
(110, '2025-09-07', 1002, 440.90, 305.38, 0),
(74, '2025-09-24', 1001, 603.36, 420.26, 0);

WITH
params AS (
  SELECT period_start, period_end, orders_target, target_bonus, payout_cap
  FROM commission_policy
  WHERE period_start = '2025-09-01' AND period_end = '2025-09-30'
),
base AS (
  SELECT
      o.employee_id,
      SUM(CASE WHEN o.is_chargeback = 0 THEN 1 ELSE 0 END)  AS orders_cnt,
      SUM(CASE WHEN o.is_chargeback = 0 THEN o.revenue_usd ELSE 0 END) AS revenue,
      SUM(CASE WHEN o.is_chargeback = 0 THEN o.cost_usd    ELSE 0 END) AS cost
  FROM orders o
  JOIN params p
    ON o.order_date BETWEEN p.period_start AND p.period_end
  GROUP BY o.employee_id
),
metrics AS (
  SELECT
      b.*,
      CASE WHEN IFNULL(b.revenue,0) = 0
           THEN 0
           ELSE ROUND(((b.revenue - b.cost) / b.revenue) * 100.0, 2)
      END AS margin_pct
  FROM base b
),
tier_rate AS (
  SELECT
      m.*,
      (
        SELECT t.rate_pct
        FROM commission_tiers t
        WHERE (t.margin_from IS NULL OR m.margin_pct >= t.margin_from)
          AND (t.margin_to   IS NULL OR m.margin_pct <  t.margin_to)
        ORDER BY (t.margin_from IS NOT NULL), t.margin_from
     --   LIMIT 1
      ) AS rate_pct
  FROM metrics m
),
calc AS (
  SELECT
      employee_id, orders_cnt, revenue, cost, margin_pct,
      IFNULL(rate_pct, 0)                            AS rate_pct,
      ROUND(revenue * IFNULL(rate_pct,0) / 100.0, 2) AS commission_base
  FROM tier_rate
),
with_bonus AS (
  SELECT
      c.*,
      CASE WHEN c.orders_cnt >= p.orders_target THEN p.target_bonus ELSE 0 END AS bonus_target
  FROM calc c
  CROSS JOIN params p
),
with_adj AS (
  SELECT
      wb.*,
      IFNULL(SUM(a.amount_usd), 0) AS adjustments
  FROM with_bonus wb
  CROSS JOIN params p
  LEFT JOIN commission_adjustments a
    ON a.employee_id = wb.employee_id
   AND a.adj_date BETWEEN p.period_start AND p.period_end
  GROUP BY wb.employee_id, wb.orders_cnt, wb.revenue, wb.cost,
           wb.margin_pct, wb.rate_pct, wb.commission_base, wb.bonus_target
),
final AS (
  SELECT
      wa.*,
      (wa.commission_base + wa.bonus_target + wa.adjustments) AS payout_raw,
      p.payout_cap,
      LEAST((wa.commission_base + wa.bonus_target + wa.adjustments), p.payout_cap) AS total_payout
  FROM with_adj wa
  CROSS JOIN params p
)
SELECT
  f.employee_id,
  e.full_name,
  f.orders_cnt,
  f.revenue,
  f.cost,
  f.margin_pct,
  f.rate_pct,
  f.commission_base,
  f.bonus_target,
  f.adjustments,
  f.payout_raw,
  f.payout_cap,
  f.total_payout
FROM final f
JOIN employees e
  ON e.employee_id = f.employee_id

-- CHECKS
-- SELECT * FROM orders WHERE revenue_usd < 0 OR cost_usd < 0;
-- SELECT * FROM orders WHERE employee_id IS NULL;
