---
outline: deep
---

# Quickstart

## Getting Started

#### Create a new React app

`npm create vite@latest my-first-electric-app -- --template react-ts`

#### Setup Docker Compose to run Postgres and Electric

`docker-compose.yaml`

```docker
version: "3.8"
name: "my-first-electric-service"

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: electric
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    ports:
      - 55321:5432
    volumes:
      - ./postgres.conf:/etc/postgresql/postgresql.conf:ro
    command:
      - postgres
      - -c
      - config_file=/etc/postgresql/postgresql.conf
    extra_hosts:
      - "host.docker.internal:host-gateway"

  electric:
    image: electricsql/next:example
    environment:
      DATABASE_URL: postgresql://postgres:password@host.docker.internal:55321/electric
    ports:
      - "3000:3000"
    build:
      context: ~/programs/electric-next/packages/sync-service/
```

Add a `postgres.conf` file.

```
listen_addresses = '*'
wal_level = 'logical'
```

#### Start Docker

`docker compose -f ./docker-compose.yaml up`

#### Try a curl command against Electric's HTTP API

`curl -i http://localhost:3000/v1/shape/foo?offset=-1`

This request asks for a shape composed of the entire `foo` table.

A bit of explanation about the URL structure — `/v1/shape/` are standard
segments. `foo` is the name of the root table of the shape (and is required).
`offset=-1` means we're asking for the entire log of the Shape as we don't have
any of the log cached locally yet. If we had previously fetched the shape and
wanted to see if there was any updates, we'd set the offset of the last log
message we'd got the first time.

You should get a response like this:

```bash
HTTP/1.1 400 Bad Request
date: Wed, 17 Jul 2024 20:30:31 GMT
content-length: 62
vary: accept-encoding
cache-control: max-age=0, private, must-revalidate
x-request-id: F-MaJcF9A--cg9QAAAeF
access-control-allow-origin: *
access-control-expose-headers: *
access-control-allow-methods: GET, POST, OPTIONS
Server: ElectricSQL/0.0.1
content-type: application/json; charset=utf-8

{"offset":["can't be blank"],"root_table":["table not found"]}%
```

So it didn't work! Which makes sense... as it's a empty database without any tables or data. Let's fix that.

#### Create a table and insert some data

Use your favorite Postgres client to connect to Postgres e.g. with [psql](https://www.postgresql.org/docs/current/app-psql.html)
you run: `psql postgresql://postgres:password@localhost:55321/electric`

```sql
CREATE TABLE foo (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    value FLOAT
);

INSERT INTO foo (name, value) VALUES
    ('Alice', 3.14),
    ('Bob', 2.71),
    ('Charlie', -1.618),
    ('David', 1.414),
    ('Eve', 0);
```

#### Now try the curl command again

`curl http://localhost:3000/shape/foo?offset=-1`

Success! You should see the data you just put into Postgres in the shape response:

```bash
HTTP/1.1 200 OK
date: Wed, 17 Jul 2024 20:38:07 GMT
content-length: 643
vary: accept-encoding
cache-control: max-age=60, stale-while-revalidate=300
x-request-id: F-Maj_CikDKfZTIAAAAh
access-control-allow-origin: *
access-control-expose-headers: *
access-control-allow-methods: GET, POST, OPTIONS
Server: ElectricSQL/0.0.1
content-type: application/json; charset=utf-8
x-electric-shape-id: 3833821-1721248688126
x-electric-chunk-last-offset: 0_0
etag: 3833821-1721248688126:-1:0_0

[{"offset":"0_0","value":{"id":1,"name":"Alice","value":3.14},"key":"\"public\".\"foo\"/1","headers":{"action"
:"insert"}},{"offset":"0_0","value":{"id":2,"name":"Bob","value":2.71},"key":"\"public\".\"foo\"/2","headers":
{"action":"insert"}},{"offset":"0_0","value":{"id":3,"name":"Charlie","value":-1.618},"key":"\"public\".\"foo\
"/3","headers":{"action":"insert"}},{"offset":"0_0","value":{"id":4,"name":"David","value":1.414},"key":"\"pub
lic\".\"foo\"/4","headers":{"action":"insert"}},{"offset":"0_0","value":{"id":5,"name":"Eve","value":0.0},"key
":"\"public\".\"foo\"/5","headers":{"action":"insert"}},{"headers":{"control":"up-to-date"}}]%
```

#### Now let's fetch the same shape to use in our React app

Install the Electric React package:

`npm install @electric-sql/react`


Wrap your root in `src/main.tsx` with the `ShapesProvider`:

```tsx
import { ShapesProvider } from "@electric-sql/react"

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ShapesProvider>
      <App />
    </ShapesProvider>
  </React.StrictMode>,
)
```

Replace `App.tsx` with the following:

```tsx
import { useShape } from "@electric-sql/react";

function Component() {
  const { data: fooData } = useShape({
    shape: { table: `foo` },
    baseUrl: `http://localhost:3000`,
  });

  return JSON.stringify(fooData, null, 4);
}

export default Component;
```

Finally run the dev server to see it all in action!

`npm run dev`

You should see something like:

<img width="699" alt="Screenshot 2024-07-17 at 2 49 28 PM" src="https://github.com/user-attachments/assets/cda36897-2db9-4f6c-86bb-99e7e325a490">

#### Postgres as a real-time database

Go back to your postgres client and update a row. It'll instantly be synced to your component!

```sql
UPDATE foo SET name = 'James' WHERE id = 2;
```

Congratulations! You've now built your first Electric app!