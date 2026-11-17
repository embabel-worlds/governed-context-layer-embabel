-- Undo db/setup.sql. Run in Cloud SQL Studio, signed in as postgres, against chai_and_co.
-- Removes only what setup.sql added: the two views, the chai_reader role and its grants.
-- The GCP demo's tables, rows and Toolbox login are untouched. One transaction, like setup.

BEGIN;

-- Column grants on stores and orders go with the table-level revoke.
REVOKE ALL ON stores, orders, suppliers FROM chai_reader;

-- Dropping the views drops their grants with them.
DROP VIEW IF EXISTS customer_profiles, store_inventory;

REVOKE ALL ON SCHEMA public FROM chai_reader;
REVOKE ALL ON DATABASE chai_and_co FROM chai_reader;
DROP ROLE IF EXISTS chai_reader;

COMMIT;
