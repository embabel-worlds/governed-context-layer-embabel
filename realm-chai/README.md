# realm-chai

Chai & Co. franchise operations (stores, orders, loyalty customers, tea and spice inventory,
suppliers) read live from Cloud SQL for PostgreSQL: instance `${CHAI_INSTANCE}`, project
`${CHAI_PROJECT_ID}`, region `${CHAI_REGION}`, database `chai_and_co`. Nothing is stored in the
world; every label is fetched when a query reaches it, through short (60-second) caches.

## Labels

| Label | From | Notes |
|---|---|---|
| `ChaiFranchise` | — | internal door for "all of them" questions: pin `by` to `store_id` or `supplier_id` |
| `ChaiStore` | `stores` | |
| `ChaiOrder` | `orders` | |
| `ChaiCustomer` | database view `customer_profiles` | display name only, never the full name or contact details |
| `ChaiInventoryItem` | database view `store_inventory` | one line per store and SKU, identity `item_key` |
| `ChaiSupplier` | `suppliers` | |

Joins: `(:ChaiFranchise {by:'store_id'})-[:STORE]->(s:ChaiStore)`,
`(s)-[:HAS_ORDER]->(o:ChaiOrder)-[:PLACED_BY]->(c:ChaiCustomer)`,
`(s)-[:STOCKS]->(i:ChaiInventoryItem)`, `(i)-[:AT_STORE]->(s)`,
`(:ChaiFranchise {by:'supplier_id'})-[:SUPPLIER]->(sup:ChaiSupplier)`,
`(sup)-[:SUPPLIES]->(i)`, `(i)-[:SUPPLIED_BY]->(sup)`.

## Saved views

`StoreNetRevenue` (parameter `city`), `LowStockAlerts` (`storeId`), `VipOrders` (`tier`),
`DelayedSupplierImpact` (`shipmentStatus`). Every parameter has a default.

## Business rules

The rules for this data (how Net Store Revenue is calculated, which customer columns are
personal data) are kept in Google Cloud Knowledge Catalog, not here. Each table's entry is

```
projects/${CHAI_PROJECT_ID}/locations/${CHAI_REGION}/entryGroups/@cloudsql/entries/cloudsql.googleapis.com/projects/${CHAI_PROJECT_ID}/locations/${CHAI_REGION}/instances/${CHAI_INSTANCE}/databases/chai_and_co/schemas/public/tables/<table>
```

with `<table>` one of `orders`, `customers`, `stores`, `tea_inventory`, `suppliers`. The
rules for orders and customers are in those two entries' overviews. `StoreNetRevenue`
implements the revenue rule; if the rule changes, the view's Cypher changes with it.

## Governance

Read-only. Every producer is `mode: governed`: its SELECT is generated from an explicit column
list, and a query naming any other column is refused. The datasource logs in as a SELECT-only
database role with column-level grants that match those lists, so the boundary holds in the
database as well as in the realm.
