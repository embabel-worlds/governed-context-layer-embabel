# Chai & Co. on Embabel Worlds

A port of Google's governed-context-layer demo
([rominirani/governed-context-layer-gcp](https://github.com/rominirani/governed-context-layer-gcp))
to Embabel Worlds. The realm `realm-chai` gives an Embabel World governed, read-only access to
the Chai & Co. franchise database. The data stays in the demo's **Cloud SQL database** and the
business rules stay in its **Knowledge Catalog**; the agent reaches the rows only through the
realm. [PROBES.md](PROBES.md) has the questions that check the port, with their expected
answers.

What the port changes:

| In Google's demo | In the port |
|---|---|
| MCP Toolbox connects as `postgres` | `chai_reader`: SELECT on named columns only, read-only by default (`db/setup.sql`) |
| Knowledge Catalog overviews hold the business rules | **the same catalog**, read by the agent through the same MCP server; the realm's descriptions point to the entries |
| `tools.yaml`: hand-written SQL statements | `producers/chai.yml`: SELECTs generated from `expose:` lists, `mode: governed` |
| PII rule as text: "never select email…" | `customer_profiles` database view; no grant on `customers` |
| `supplier_cost_usd` left out of one query | `store_inventory` database view; no grant on `tea_inventory` |
| `delivery_note` returned by the "masked" tool | not exposed, not granted |
| 3 fixed tools | 4 saved views, plus any Cypher or SQL over the same governed labels |
| `single_pane_app.py`: a FastAPI server calling the Toolbox tools | `apps/franchise-pulse.html`: a page the appliance serves, running the saved views |

## What is in this repository

| Path | What it is |
|---|---|
| `realm-chai/` | the realm source. Your project, region, instance and proxy port appear as `${CHAI_*}` placeholders |
| `db/setup.sql` | run once as `postgres`: the reader role, its column grants, two database views |
| `db/teardown.sql` | removes exactly what `setup.sql` added |
| `scripts/configure.ps1`, `scripts/configure.sh` | render the realm and the Claude Code session folders from your `.env` |
| `scripts/embabel-headers.*`, `scripts/kc-headers.*` | Claude Code `headersHelper`s: read tokens at call time, so none sit in `.mcp.json` |
| `.env.example` | template for your `.env` |
| `PROBES.md` | the questions that check the port, how to run them, and the expected answers |

Made on your machine and gitignored: `.env` (your settings and secrets), `realms/realm-chai/`
(the rendered realm the appliance mounts), `sessions/` (one folder per Claude Code session,
each holding only a `.mcp.json`), the Cloud SQL Auth Proxy binary, and `local/` for your own
notes.

**Keep expected answers out of the realm.** The appliance's code door has a `realm_read` tool
that returns any file in an installed realm, comments included. Expected answers or notes
about the probes inside `realm-chai/` will reach the agent being tested.

## Before you start

- Google's demo set up in **your own** Google Cloud project, at least through the Cloud SQL
  instance being seeded and the Knowledge Catalog overviews on `orders` and `customers`. Note
  the project, region and instance you used. The demo's defaults are `asia-south1` and
  `chai-and-co-pg`.
- gcloud application-default credentials: `gcloud auth application-default login`.
- Docker: Docker Desktop on Windows and macOS, or Docker Engine on Linux.
- An Embabel Worlds appliance in worlds mode, running (`embabel status`). Its folder is
  `~/embabel/worlds` unless you installed it elsewhere with `EMBABEL_HOME`.
- Claude Code.

Run every command from the root of this checkout. Each step gives PowerShell (Windows) and
bash (macOS, Linux).

## Setup

### 1. Create `.env`, the reader password, and the rendered files

Copy the template and set `CHAI_PROJECT_ID`. Change `CHAI_REGION` and `CHAI_INSTANCE` only if
you didn't use the demo's defaults, and `CHAI_PROXY_PORT` only if port 5433 is taken.

```powershell
Copy-Item .env.example .env; notepad .env
```

```bash
cp .env.example .env && ${EDITOR:-nano} .env
```

Generate the password for the database role `chai_reader`. It stays in `.env`:

```powershell
$b = New-Object byte[] 18; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); $pw = [Convert]::ToBase64String($b) -replace '[/+=]', ''; (Get-Content .env) -replace '^CHAI_READER_PASSWORD=.*$', "CHAI_READER_PASSWORD=$pw" | Set-Content -Encoding ascii .env
```

```bash
pw="$(openssl rand -base64 18 | tr -d '/+=\n')"; sed -i.bak "s/^CHAI_READER_PASSWORD=.*/CHAI_READER_PASSWORD=$pw/" .env && rm .env.bak
```

`-Encoding ascii` matters: a byte-order mark would become part of the first variable's name.

Render the realm and the session folders. Re-run this whenever you change `.env` or anything
in `realm-chai/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1
```

```bash
bash scripts/configure.sh
```

It prints the exact commands for steps 3 and 6.

### 2. Create the role and views in Cloud SQL

Copy `db/setup.sql` to the clipboard with the password filled in:

```powershell
$pw = ((Get-Content .env | Select-String '^CHAI_READER_PASSWORD=').Line -split '=', 2)[1]; (Get-Content db\setup.sql -Raw -Encoding UTF8).Replace('REPLACE_WITH_READER_PASSWORD', $pw) | Set-Clipboard
```

```bash
pw="$(sed -n 's/^CHAI_READER_PASSWORD=//p' .env | tail -n 1 | tr -d '\r')"; sed "s/REPLACE_WITH_READER_PASSWORD/$pw/" db/setup.sql | pbcopy
```

On Linux, use `xclip -selection clipboard` or `wl-copy` in place of `pbcopy`.

Go straight to Cloud SQL Studio, because copying anything else first replaces the script.
Sign in to `chai_and_co` as `postgres`, paste into a new editor tab and click **Run**. Every
statement should succeed. The script only adds two views, a role and grants, and runs as one
transaction. Create the role this way, not with `gcloud sql users create` or the console:
Cloud SQL makes those users members of `cloudsqlsuperuser`.

Check it, still as `postgres`:

```sql
SELECT r.rolname,
       r.rolcanlogin,
       r.rolconfig,
       pg_has_role('chai_reader', 'cloudsqlsuperuser', 'MEMBER')                AS in_superuser_group,
       has_table_privilege('chai_reader', 'customer_profiles', 'SELECT')        AS profiles,
       has_table_privilege('chai_reader', 'customers', 'SELECT')                AS customers,
       has_table_privilege('chai_reader', 'tea_inventory', 'SELECT')            AS tea_inventory,
       has_column_privilege('chai_reader', 'orders', 'delivery_note', 'SELECT') AS delivery_note,
       has_column_privilege('chai_reader', 'stores', 'manager_email', 'SELECT') AS manager_email
FROM pg_roles r
WHERE r.rolname = 'chai_reader';
```

You should get one row: `chai_reader`, `true`, `{default_transaction_read_only=on}`, then
`false`, `true` and four more `false`. Close the Studio tab without saving, and clear the
clipboard: `Set-Clipboard -Value 'cleared'` or `printf cleared | pbcopy`.

### 3. Start the Cloud SQL Auth Proxy

Download the proxy into this folder (it is gitignored). These links are for v2.28.0; check
[Google's install page](https://cloud.google.com/sql/docs/postgres/sql-proxy#install) for the
current version.

```powershell
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.28.0/cloud-sql-proxy.x64.exe -OutFile cloud-sql-proxy.x64.exe -UseBasicParsing
```

```bash
curl -fsSLo cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.28.0/cloud-sql-proxy.darwin.arm64 && chmod +x cloud-sql-proxy
```

For an Intel Mac, use `darwin.amd64`; for Linux, `linux.amd64`.

Start it in a terminal of its own and leave it running. It uses your application-default
credentials. The command is the one `configure` printed: `--port`, then
`PROJECT:REGION:INSTANCE`.

```powershell
.\cloud-sql-proxy.x64.exe --port 5433 YOUR_PROJECT:asia-south1:chai-and-co-pg
```

```bash
./cloud-sql-proxy --port 5433 YOUR_PROJECT:asia-south1:chai-and-co-pg
```

It prints `Listening on 127.0.0.1:5433` when it is ready. Containers reach it as
`host.docker.internal:5433`. That works as-is on Docker Desktop. On Linux, add
`--address 0.0.0.0`, because the container arrives through the Docker bridge rather than
loopback; firewall the port from the network. On Windows, if Windows Firewall asks, allow
Private networks only.

### 4. Check the role through the proxy

Connect as `chai_reader` with `psql` in a throwaway container, the same route the appliance
takes. The first run pulls `postgres:16-alpine` (about 100 MB).

```powershell
$env:PGPASSWORD = ((Get-Content .env | Select-String '^CHAI_READER_PASSWORD=').Line -split '=', 2)[1]; docker run --rm -it -e PGPASSWORD postgres:16-alpine psql "host=host.docker.internal port=5433 dbname=chai_and_co user=chai_reader sslmode=disable"
```

```bash
PGPASSWORD="$(sed -n 's/^CHAI_READER_PASSWORD=//p' .env | tail -n 1 | tr -d '\r')" docker run --rm -it -e PGPASSWORD --add-host=host.docker.internal:host-gateway postgres:16-alpine psql "host=host.docker.internal port=5433 dbname=chai_and_co user=chai_reader sslmode=disable"
```

`-e PGPASSWORD` with no value passes the variable through, so the password never appears on a
command line. `sslmode=disable` covers only the hop to the local proxy, which encrypts the
connection to Cloud SQL. At the `chai_and_co=>` prompt:

```sql
SELECT current_user;                                    -- chai_reader
SELECT * FROM customer_profiles;                        -- 4 rows: Aarav K., Ananya I., Meera K., Vikram J.
SELECT email FROM customers;                            -- ERROR: permission denied for table customers
SELECT delivery_note FROM orders;                       -- ERROR: permission denied for table orders
SELECT supplier_cost_usd FROM tea_inventory;            -- ERROR: permission denied for table tea_inventory
SELECT * FROM orders;                                   -- ERROR: permission denied (* includes delivery_note)
SELECT order_id, status, gross_amount_usd FROM orders;  -- the 6 orders, no notes
SHOW default_transaction_read_only;                     -- on
UPDATE stores SET city = city;                          -- ERROR: cannot execute UPDATE in a read-only transaction
```

Leave with `\q`. In PowerShell, then run `Remove-Item Env:PGPASSWORD`.

### 5. Give the appliance the password

The realm's `sql/datasources.yml` names the variable `CHAI_READER_PASSWORD`, and the
appliance loads every line of `secrets.env`, in its own folder, into the server's
environment. Add the line there:

```powershell
$pw = ((Get-Content .env | Select-String '^CHAI_READER_PASSWORD=').Line -split '=', 2)[1]; Add-Content -Path "$HOME\embabel\worlds\secrets.env" -Encoding ascii -Value "`r`nCHAI_READER_PASSWORD=$pw"
```

```bash
pw="$(sed -n 's/^CHAI_READER_PASSWORD=//p' .env | tail -n 1 | tr -d '\r')"; printf '\nCHAI_READER_PASSWORD=%s\n' "$pw" >> ~/embabel/worlds/secrets.env
```

If your appliance is elsewhere (`EMBABEL_HOME`), change the path. If `secrets.env` already
has a `CHAI_READER_PASSWORD` line, edit that line instead. Recreate the server so it reads the
file (a plain container restart keeps the old environment), then check that the variable
arrived. This prints only its length:

```bash
embabel up
```

```powershell
$id = docker ps -q --filter "label=com.docker.compose.service=worlds"; docker exec $id sh -c 'echo ${#CHAI_READER_PASSWORD}'
```

```bash
docker exec "$(docker ps -q --filter label=com.docker.compose.service=worlds)" sh -c 'echo ${#CHAI_READER_PASSWORD}'
```

The length should match the password in `.env`. `0` means it did not arrive.

Server builds up to at least 2026-11-02 read the password this way. Later builds that follow
the realm spec's "Approved SQL callers" ignore the file. On one of those, approve a PostgreSQL
target in the console's Connect screen with URL
`jdbc:postgresql://host.docker.internal:5433/chai_and_co`, user `chai_reader` and the
password. Then replace `datasource: chai_and_co` in `realm-chai/producers/chai.yml` with the
target ID it gives you (all eight lines), and re-run `configure`.

### 6. Link and install the realm

Point the appliance at this checkout's `realms` folder, using the command `configure` printed.
The folder is mounted read-only into the server's container, so it holds only the rendered
realm. Your `.env` stays out of the container.

```bash
embabel realms link /path/to/this/checkout/realms
```

It should report `realm-chai` as visible. If it says the server has to be recreated to see
the folder, run `embabel up`.

Copy the MCP token the appliance created at setup into `.env`, without printing it:

```powershell
$id = docker ps -q --filter "label=com.docker.compose.service=worlds"; $line = docker exec $id cat /data/embabel/assistant/admin/providers.env | Select-String '^EMBABEL_SETUP_MCP_TOKEN=' | Select-Object -First 1; if ($line) { Add-Content -Path .env -Encoding ascii -Value ('EMBABEL_MCP_TOKEN=' + ($line.Line -split '=', 2)[1]); 'token added to .env' } else { 'No EMBABEL_SETUP_MCP_TOKEN line in the appliance' }
```

```bash
tok="$(docker exec "$(docker ps -q --filter label=com.docker.compose.service=worlds)" cat /data/embabel/assistant/admin/providers.env | sed -n 's/^EMBABEL_SETUP_MCP_TOKEN=//p' | head -n 1 | tr -d '\r')"; if [ -n "$tok" ]; then printf 'EMBABEL_MCP_TOKEN=%s\n' "$tok" >> .env; echo 'token added to .env'; else echo 'No EMBABEL_SETUP_MCP_TOKEN line in the appliance'; fi
```

The header helpers read the last `EMBABEL_MCP_TOKEN` line in `.env`, so the appended line
wins over the empty one from the template.

Then install the realm into the world. A realm in the mounted folder joins a world by
reference: nothing is copied, and later changes on disk are picked up with `realm_refresh`.
Start a Claude Code session with **`sessions/setup`** as its folder. Its `.mcp.json` has the
appliance and nothing else, and it is kept apart from `sessions/agent` because Claude Code
keeps memory per folder. Approve the `embabel` server and ask:

> Call the embabel MCP tool `install_realm_from_path` with `realm-chai` and show me its
> full reply. Don't call any other tool.

### 7. Check the saved views

The appliance's SQL door (port 11052 by default, `WORLDS_SQL_PORT`) shows every saved view as
a table. `psql` asks for your appliance password; an API key also works.

```powershell
$id = docker ps -q --filter "label=com.docker.compose.service=worlds"; $u = ((docker exec $id cat /data/embabel/assistant/admin/providers.env | Select-String '^EMBABEL_SETUP_MCP_TOKEN_USER=').Line -split '=', 2)[1]; docker run --rm -it postgres:16-alpine psql "host=host.docker.internal port=11052 dbname=world user=$u"
```

```bash
u="$(docker exec "$(docker ps -q --filter label=com.docker.compose.service=worlds)" cat /data/embabel/assistant/admin/providers.env | sed -n 's/^EMBABEL_SETUP_MCP_TOKEN_USER=//p' | head -n 1 | tr -d '\r')"; docker run --rm -it --add-host=host.docker.internal:host-gateway postgres:16-alpine psql "host=host.docker.internal port=11052 dbname=world user=$u"
```

```sql
SELECT * FROM store_net_revenue;
SELECT * FROM low_stock_alerts;
SELECT * FROM vip_orders;
SELECT * FROM delayed_supplier_impact;
SELECT * FROM store_net_revenue WHERE city = 'Mumbai';   -- sets the city parameter
```

A parameter is set by an equality on its column in `WHERE`. Calling the view as a function
(`store_net_revenue('Mumbai')`) fails on the 2026-11-02 build.

| View | Expected on the demo's seed data |
|---|---|
| `StoreNetRevenue` | Bandra 66.50 (2 completed, 1 excluded) · Indiranagar 60.00 (1, 1) · Connaught Place 56.00 (1, 0). Total **182.50**. Targets 150 / 180 / 120 |
| `LowStockAlerts` | Indiranagar cardamom mix, shortage 14.00 · Bandra Assam CTC, 6.50 · Connaught Place Darjeeling, 4.00 |
| `VipOrders` | ord-9004, Ananya I., 60.00 · ord-9001, Aarav K., 38.00 |
| `DelayedSupplierImpact` | Upper Assam co-op → Assam CTC at Bandra, 3.50 of 10.00, **1** VIP customer |

### 8. Run the probes

See [PROBES.md](PROBES.md). The agent session runs in `sessions/agent`, which has the
Knowledge Catalog and the appliance.

## The franchise pulse app

The realm ships a one-page dashboard, `realm-chai/apps/franchise-pulse.html`: the port of the
demo's Morning Franchise Pulse (`single_pane_app.py`). It shows store net revenue with a city
filter, the stock to reorder, recent Gold or Silver orders in store time (IST), and the
supply-chain blast radius, with a log of every view it ran and the database reads behind each.

Open it once the realm is installed (step 6), signed in to the appliance console as its owner.
`configure` prints the address; with the default port it is:

```
http://localhost:11043/apps/chai/franchise-pulse.html
```

- **No server of its own.** The appliance serves the page from the realm's `apps/` folder.
- **No queries or credentials in the page.** It names the four saved views and runs them
  through the appliance's view API (`POST /api/v1/admin/kg/views/<view>/run`) with the console
  session; that API needs the owner (admin) role, and the appliance answers 403 to a POST that
  carries the session cookie without an `X-Requested-With` header, so the page sends one. For
  Chai & Co. data, any query, from this page
  or anywhere else, goes through the same governed producers as `chai_reader`, so the boundary
  does not depend on the page.
- **Outages show.** When a producer cannot read Cloud SQL, the view answers with a warning,
  and the page shows it at the top instead of an empty table.
- **Not ported:** the demo's restock request, which writes to the database. The realm's
  datasource is read-only.

## Changing the realm

Edit files in `realm-chai/`, never in `realms/realm-chai/`: `configure` deletes and rewrites
that copy on every run. Then re-run `configure` and ask any session with the `embabel`
server to call `realm_refresh`. The placeholders `configure` fills in are `${CHAI_PROJECT_ID}`,
`${CHAI_REGION}`, `${CHAI_INSTANCE}` and `${CHAI_PROXY_PORT}`. It stops if it finds any other
`${CHAI_…}`, so a new placeholder means adding it to both `configure` scripts.

The revenue rule lives in Knowledge Catalog, and `StoreNetRevenue` implements it in Cypher. If
you change the rule in the catalog, change the view's Cypher too.

## Removing it

Run `db/teardown.sql` in Cloud SQL Studio as `postgres`, the same way as step 2. It removes the
views, the role and its grants, and leaves the demo's tables alone. Remove the
`CHAI_READER_PASSWORD` line from the appliance's `secrets.env` and run `embabel up`.

## Known behaviour

- **Catalog search can miss.** Knowledge Catalog's `search_entries` sometimes returns nothing
  for the Cloud SQL tables, while a lookup by full entry name works. That is why the type
  descriptions carry the full entry names.
- **Untyped columns arrive as text through the SQL door.** The types describe each property
  but give no type, so plain columns such as `daily_target_usd` come back as text. Values the
  Cypher computes, such as `net_revenue_usd`, are numbers.
- **Times are UTC.** Order times come back in UTC without a zone; the stores are in India
  (IST, UTC+5:30).
- **The types were written by hand** in the shape the platform's schema miner produces, not
  mined.
