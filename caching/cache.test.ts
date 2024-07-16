import {
  describe,
  it,
  expect,
  assert,
  beforeAll,
  beforeEach,
  afterAll,
} from 'vitest'
import { exec } from 'child_process'
import { Client } from 'pg'
import { v4 as uuidv4 } from 'uuid'

const dbClient = new Client({
  host: `localhost`,
  port: 54321,
  password: `password`,
  user: `postgres`,
  database: `electric`,
})

const PROXY_URL = `http://localhost:3002`

// name of proxy cache container to execute commands against,
// see docker-compose.yml that spins it up for details
const NGINX_CONTAINER_NAME = `electric_dev-nginx-1`
// path pattern for cache files inside proxy cache to clear
const NGINX_CACHE_MATCH = `/var/cache/nginx/*`

// see https://blog.nginx.org/blog/nginx-caching-guide for details
enum CacheStatus {
  MISS = `MISS`, // item was not in the cache
  BYPASS = `BYPASS`, // not used by us
  EXPIRED = `EXPIRED`, // there was a cache entry but was expired, so we got a fresh response
  STALE = `STALE`, // cache entry > max age but < stale-while-revalidate so we got a stale response
  UPDATING = `UPDATING`, // same as STALE but indicates proxy is updating stale entry
  REVALIDATED = `REVALIDATED`, // you this request revalidated at the server
  HIT = `HIT`, // cache hit
}

/**
 * Clear the proxy cache files to simulate an empty cache
 */
async function clearCache(): Promise<void> {
  return new Promise((res) =>
    exec(
      `docker exec ${NGINX_CONTAINER_NAME} sh -c 'rm -rf ${NGINX_CACHE_MATCH}'`,
      (_) => res()
    )
  )
}

function getCacheStatus(res: Response): CacheStatus {
  return res.headers.get(`X-Proxy-Cache`) as CacheStatus
}

async function initializeDb(): Promise<void> {
  await dbClient.query(`DROP TABLE IF EXISTS issues;`)
  await dbClient.query(`DROP TABLE IF EXISTS foo;`)

  // Add an initial row.
  const uuid = uuidv4()
  try {
    await dbClient.query(
      `CREATE TABLE IF NOT EXISTS issues (
        id UUID PRIMARY KEY,
        title TEXT NOT NULL
    );`,
      []
    )
    await dbClient.query(
      `CREATE TABLE IF NOT EXISTS foo (
      id UUID PRIMARY KEY,
      title TEXT NOT NULL
  );`,
      []
    )
    await dbClient.query(`insert into foo(id, title) values($1, $2)`, [
      uuid,
      `I AM FOO TABLE`,
    ])
  } catch (e) {
    console.log(e)
    throw e
  }
}

async function clearAllItems() {
  await Promise.all([
    dbClient.query(`TRUNCATE TABLE issues;`),
    dbClient.query(`TRUNCATE TABLE foo;`),
  ])
}

async function addItems(table: `issues` | `foo`, numItems: number) {
  try {
    await dbClient.query(`BEGIN`)
    const inserts = Array.from({ length: numItems }, (_, idx) => {
      const uuid = uuidv4()
      return dbClient.query(`INSERT INTO ${table}(id, title) VALUES($1, $2)`, [
        uuid,
        `Item ${idx}`,
      ])
    })
    await Promise.all(inserts)
    await dbClient.query(`COMMIT`)
  } catch (e) {
    await dbClient.query(`ROLLBACK`)
    throw e
  }
}

async function clearShape(table: string, shapeId?: string) {
  const res = await fetch(
    `${PROXY_URL}/shape/${table}${shapeId ? `?shape_id=${shapeId}` : ``}`,
    {
      method: `DELETE`,
    }
  )
  if (!res.ok) {
    throw new Error(`Could not delete shape ${table} with ID ${shapeId}`)
  }
}

async function sleep(time: number) {
  await new Promise((resolve) => setTimeout(resolve, time))
}

const maxAge = 1 // seconds
const staleAge = 3 // seconds

beforeAll(async () => {
  await dbClient.connect()
})

afterAll(async () => {
  await dbClient.end()
})

describe(`HTTP Proxy Cache`, { timeout: 30000 }, () => {
  beforeAll(async () => await initializeDb())
  beforeEach(async () => await clearCache())

  it(`should always get non-cached response in live mode`, async () => {
    // First request gets non-cached response
    const originalRes = await fetch(
      `${PROXY_URL}/shape/issues?offset=-1&live`,
      {}
    )

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request still gets non-cached response
    const cachedRes = await fetch(
      `${PROXY_URL}/shape/issues?offset=-1&live`,
      {}
    )
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.MISS)
  })

  it(`should get cached response on second request`, async () => {
    // First request gets non-cached response
    const originalRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)
  })

  it(`should get stale response when max age is passed but cache is not yet revalidated`, async () => {
    // Make a first request such that response is cached
    const originalRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)

    // Now wait for the response to be passed its max-age but before the stale-while-revalidate
    await new Promise((resolve) =>
      setTimeout(resolve, maxAge * 1000 + ((staleAge - maxAge) / 2) * 1000)
    )

    // Third request gets cached response
    const staleRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})

    expect(staleRes.status).toBe(200)
    expect(getCacheStatus(staleRes)).toBe(CacheStatus.STALE)
  })

  it(`should get fresh response when age is passed the stale age`, async () => {
    // Make a first request such that response is cached
    const originalRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)

    // Now wait for the response to be passed its max-age but before the stale-while-revalidate
    await sleep(staleAge * 1000 + 2000)

    // Third request gets cached response
    const staleRes = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})

    expect(staleRes.status).toBe(200)
    expect(getCacheStatus(staleRes)).toBe(CacheStatus.REVALIDATED)
  })
})

describe(`HTTP Initial Data Caching`, { timeout: 30000 }, () => {
  beforeAll(async () => await initializeDb())
  beforeEach(async () => {
    await clearAllItems()
    await clearCache()
    await addItems(`issues`, 10)
  })

  it(`tells client to resync when shape is out of scope`, async () => {
    // Make a client that fetches a shape
    // which forces the shape data to be cached
    const client1Res = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})
    expect(client1Res.status).toBe(200)
    const originalShapeId =
      client1Res.headers.get(`x-electric-shape-id`) ?? undefined
    assert(originalShapeId, `Should have shape ID`)
    expect(getCacheStatus(client1Res)).toBe(CacheStatus.MISS)
    //const messages = client1Res.status === 204 ? [] : await client1Res.json()

    // Make a 2nd client that fetches the shape
    // check that it is served from cached data
    const client2Res = await fetch(`${PROXY_URL}/shape/issues?offset=-1`, {})
    expect(client2Res.status).toBe(200)
    const shapeId2 = client2Res.headers.get(`x-electric-shape-id`) ?? undefined

    expect(
      originalShapeId,
      `Shape ID changed but expected it to stay the same`
    ).toBe(shapeId2)

    expect(getCacheStatus(client2Res)).toBe(CacheStatus.HIT)

    const latestOffset = client2Res.headers.get(`x-electric-chunk-last-offset`)
    assert(latestOffset, `latestOffset should be defined`)

    // Now GC the shape
    await clearShape(`issues`, originalShapeId)

    // Now try to go live
    // should tell you to go back to initial sync
    // because the shape is out of scope
    const liveRes = await fetch(
      `${PROXY_URL}/shape/issues?offset=${latestOffset}&shape_id=${originalShapeId}&live`,
      {}
    )
    expect(liveRes.status).toBe(409)
    const liveBody = (await liveRes.json()) as { message: string }
    expect(liveBody.message).toContain(
      `The shape associated with this shape_id and offset was not found.`
    )
    const redirectLocation = liveRes.headers.get(`location`)
    assert(redirectLocation)

    const newCacheIgnoredSyncRes = await fetch(
      `${PROXY_URL}${redirectLocation}`,
      {}
    )

    expect(newCacheIgnoredSyncRes.status).toBe(200)
    expect(getCacheStatus(newCacheIgnoredSyncRes)).toBe(CacheStatus.MISS)
    const cacheBustedShapeId =
      newCacheIgnoredSyncRes.headers.get(`x-electric-shape-id`)
    assert(cacheBustedShapeId)
    expect(cacheBustedShapeId).not.toBe(originalShapeId)

    // Then try do that and check that we get new shape id
    const newInitialSyncRes = await fetch(`${PROXY_URL}${redirectLocation}`, {})
    const cachedShapeId =
      newInitialSyncRes.headers.get(`x-electric-shape-id`) ?? undefined
    expect(newInitialSyncRes.status).toBe(200)
    expect(getCacheStatus(newInitialSyncRes)).toBe(CacheStatus.HIT)
    expect(cachedShapeId, `Got old shape id that is out of scope`).not.toBe(
      originalShapeId
    )
  })
})
