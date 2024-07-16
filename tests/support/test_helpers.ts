import { ShapeStream } from '../../client'
import { Client, ClientConfig } from 'pg'
import { exec } from 'child_process'
import { JsonSerializable, Message } from '../../types'

export function makePgClient(overrides: ClientConfig = {}) {
  return new Client({
    host: `localhost`,
    port: 54321,
    password: `password`,
    user: `postgres`,
    database: `electric`,
    options: `-csearch_path=electric_test`,
    ...overrides,
  })
}

export function forEachMessage<T extends JsonSerializable>(
  stream: ShapeStream,
  controller: AbortController,
  handler: (
    resolve: () => void,
    message: Message<T>,
    nthDataMessage: number
  ) => Promise<void> | void
) {
  return new Promise<void>((resolve, reject) => {
    let messageIdx = 0

    stream.subscribe(async (messages) => {
      for (const message of messages) {
        try {
          await handler(
            () => {
              controller.abort()
              return resolve()
            },
            message as Message<T>,
            messageIdx
          )
          if (`action` in message.headers) messageIdx++
        } catch (e) {
          controller.abort()
          return reject(e)
        }
      }
    }, reject)
  })
}

// see https://blog.nginx.org/blog/nginx-caching-guide for details
export enum CacheStatus {
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
export async function clearProxyCache({
  proxyCacheContainerName,
  proxyCachePath,
}: {
  proxyCacheContainerName: string
  proxyCachePath: string
}): Promise<void> {
  return new Promise((res) =>
    exec(
      `docker exec ${proxyCacheContainerName} sh -c 'rm -rf ${proxyCachePath}'`,
      (_) => res()
    )
  )
}

/**
 * Retrieve the {@link CacheStatus} from the provided response
 */
export function getCacheStatus(res: Response): CacheStatus {
  return res.headers.get(`X-Proxy-Cache`) as CacheStatus
}
