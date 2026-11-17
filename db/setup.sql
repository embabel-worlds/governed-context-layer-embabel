-- realm-chai database setup. Run ONCE in Cloud SQL Studio, signed in as postgres,
-- against database chai_and_co, after the schema and seed script of Google's demo
-- (github.com/rominirani/governed-context-layer-gcp).
--
-- Creates the realm's SELECT-only role and the two database views it reads. The GCP demo's
-- MCP Toolbox connects as postgres; this realm never does.
--
-- REPLACE_WITH_READER_PASSWORD is substituted on the way to the clipboard (README.md, step 2);
-- the password is never written into this file.
--
-- It only ADDS objects (two views, one role, grants) and touches no table or row. It runs as
-- one transaction, so an error anywhere leaves the database exactly as it was. Running it a
-- second time fails at CREATE ROLE and changes nothing; run db/teardown.sql first to redo it.

BEGIN;

-- 1. Customers as the realm sees them. The display name ("Aarav K.") is computed HERE, so a
--    full name, email, phone number or home address never leaves the database.
CREATE OR REPLACE VIEW customer_profiles AS
SELECT customer_id,
       CASE
         WHEN position(' ' IN btrim(full_name)) = 0 THEN btrim(full_name)
         ELSE split_part(btrim(full_name), ' ', 1) || ' ' ||
              left(split_part(btrim(full_name), ' ', 2), 1) || '.'
       END AS display_name,
       loyalty_tier,
       loyalty_points
FROM customers;

-- 2. Inventory lines with one identity each (a type has a single identity property), and
--    without the confidential wholesale supplier_cost_usd.
CREATE OR REPLACE VIEW store_inventory AS
SELECT store_id || ':' || sku_id AS item_key,
       store_id, sku_id, item_name, unit, stock_on_hand, reorder_threshold, supplier_id
FROM tea_inventory;

-- 3. The realm's own role: can log in and read, cannot write.
--    Created in SQL on purpose: Cloud SQL makes a user created with `gcloud sql users create`
--    or the console a member of cloudsqlsuperuser, which would undo everything below.
CREATE ROLE chai_reader LOGIN PASSWORD 'REPLACE_WITH_READER_PASSWORD';
ALTER ROLE chai_reader SET default_transaction_read_only = on;
GRANT CONNECT ON DATABASE chai_and_co TO chai_reader;
GRANT USAGE ON SCHEMA public TO chai_reader;

-- 4. Exactly the columns realm-chai/producers/chai.yml exposes, and nothing else.
--    No grant at all on customers, tea_inventory or restock_requests.
--    orders.delivery_note (free text: a phone number and a prompt injection in the sample
--    data) and stores.manager_email are left out deliberately.
GRANT SELECT (store_id, store_name, city, manager_name, daily_target_usd)
  ON stores TO chai_reader;
GRANT SELECT (order_id, store_id, customer_id, order_timestamp, status,
              gross_amount_usd, discount_usd, tax_usd)
  ON orders TO chai_reader;
GRANT SELECT ON suppliers TO chai_reader;
GRANT SELECT ON customer_profiles, store_inventory TO chai_reader;

COMMIT;
