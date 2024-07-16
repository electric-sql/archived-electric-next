import { describe, expect, assert } from 'vitest'
import { setTimeout as sleep } from 'node:timers/promises'
import { testWithCacheAndIssuesTable as it } from './support/test_context'
import { CacheStatus, getCacheStatus } from './support/test_helpers'

// FIXME: pull from environment?
const maxAge = 1 // seconds
const staleAge = 3 // seconds

describe(`HTTP Proxy Cache`, { timeout: 30000 }, () => {
  it(`should always get non-cached response in live mode`, async ({
    proxyCacheBaseUrl,
    issuesTableUrl,
  }) => {
    // First request gets non-cached response
    const originalRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1&live`,
      {}
    )

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request still gets non-cached response
    const cachedRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1&live`,
      {}
    )
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.MISS)
  })

  it(`should get cached response on second request`, async ({
    proxyCacheBaseUrl,
    issuesTableUrl,
  }) => {
    // First request gets non-cached response
    const originalRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)
  })

  it(`should get stale response when max age is passed but cache is not yet revalidated`, async ({
    proxyCacheBaseUrl,
    issuesTableUrl,
  }) => {
    // Make a first request such that response is cached
    const originalRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)

    // Now wait for the response to be passed its max-age but before the stale-while-revalidate
    await sleep(maxAge * 1000 + ((staleAge - maxAge) / 2) * 1000)

    // Third request gets cached response
    const staleRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )

    expect(staleRes.status).toBe(200)
    expect(getCacheStatus(staleRes)).toBe(CacheStatus.STALE)
  })

  it(`should get fresh response when age is passed the stale age`, async ({
    proxyCacheBaseUrl,
    issuesTableUrl,
  }) => {
    // Make a first request such that response is cached
    const originalRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )

    expect(originalRes.status).toBe(200)
    expect(getCacheStatus(originalRes)).toBe(CacheStatus.MISS)

    // Second request gets cached response
    const cachedRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )
    expect(cachedRes.status).toBe(200)

    expect(getCacheStatus(cachedRes)).toBe(CacheStatus.HIT)

    // Now wait for the response to be passed its max-age but before the stale-while-revalidate
    await sleep(staleAge * 1000 + 2000)

    // Third request gets cached response
    const staleRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )

    expect(staleRes.status).toBe(200)
    expect(getCacheStatus(staleRes)).toBe(CacheStatus.REVALIDATED)
  })
})

describe(`HTTP Initial Data Caching`, { timeout: 30000 }, () => {
  it(`tells client to resync when shape is out of scope`, async ({
    proxyCacheBaseUrl,
    issuesTableUrl,
    clearIssuesShape,
    insertIssues,
  }) => {
    // add some data
    await insertIssues({ title: `foo1` }, { title: `foo2` })

    // Make a client that fetches a shape
    // which forces the shape data to be cached
    const client1Res = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )
    expect(client1Res.status).toBe(200)
    const originalShapeId =
      client1Res.headers.get(`x-electric-shape-id`) ?? undefined
    assert(originalShapeId, `Should have shape ID`)
    expect(getCacheStatus(client1Res)).toBe(CacheStatus.MISS)
    //const messages = client1Res.status === 204 ? [] : await client1Res.json()

    // Make a 2nd client that fetches the shape
    // check that it is served from cached data
    const client2Res = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=-1`,
      {}
    )
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
    await clearIssuesShape(originalShapeId)

    // Now try to go live
    // should tell you to go back to initial sync
    // because the shape is out of scope
    const liveRes = await fetch(
      `${proxyCacheBaseUrl}/shape/${issuesTableUrl}?offset=${latestOffset}&shape_id=${originalShapeId}&live`,
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
      `${proxyCacheBaseUrl}${redirectLocation}`,
      {}
    )

    expect(newCacheIgnoredSyncRes.status).toBe(200)
    expect(getCacheStatus(newCacheIgnoredSyncRes)).toBe(CacheStatus.MISS)
    const cacheBustedShapeId =
      newCacheIgnoredSyncRes.headers.get(`x-electric-shape-id`)
    assert(cacheBustedShapeId)
    expect(cacheBustedShapeId).not.toBe(originalShapeId)

    // Then try do that and check that we get new shape id
    const newInitialSyncRes = await fetch(
      `${proxyCacheBaseUrl}${redirectLocation}`,
      {}
    )
    const cachedShapeId =
      newInitialSyncRes.headers.get(`x-electric-shape-id`) ?? undefined
    expect(newInitialSyncRes.status).toBe(200)
    expect(getCacheStatus(newInitialSyncRes)).toBe(CacheStatus.HIT)
    expect(cachedShapeId, `Got old shape id that is out of scope`).not.toBe(
      originalShapeId
    )
  })
})
