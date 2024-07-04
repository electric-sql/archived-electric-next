import { Message } from './types'

export type ShapeChangedCallback = (value: Map) => void

export interface ShapeStreamOptions {
  shape: { table: string }
  baseUrl: string
  subscribe?: boolean
  signal?: AbortSignal
  offset?: number
  shapeId?: string
}

class Subscriber {
  private messageQueue: Message[][] = []
  private isProcessing = false
  private callback: (messages: Message[]) => void | Promise<void>

  constructor(callback: (messages: Message[]) => void | Promise<void>) {
    this.callback = callback
  }

  enqueueMessage(messages: Message[]) {
    this.messageQueue.push(messages)
    if (!this.isProcessing) {
      this.processQueue()
    }
  }

  private async processQueue() {
    this.isProcessing = true
    while (this.messageQueue.length > 0) {
      const messages = this.messageQueue.shift()!
      await this.callback(messages)
    }
    this.isProcessing = false
  }
}

export class ShapeStream {
  private subscribers: Array<Subscriber> = []
  private instanceId: number
  private closedPromise: Promise<unknown>
  private outsideResolve?: (value?: unknown) => void
  options: ShapeStreamOptions
  shapeId?: string

  constructor(options: ShapeStreamOptions) {
    this.validateOptions(options)
    this.instanceId = Math.random()
    this.options = { subscribe: true, ...options }
    console.log(`constructor`, this)
    this.shapeId = this.options.shapeId
    this.startStream()

    this.outsideResolve
    this.closedPromise = new Promise((resolve) => {
      this.outsideResolve = resolve
    })
  }

  private validateOptions(options: ShapeStreamOptions): void {
    if (
      !options.shape ||
      !options.shape.table ||
      typeof options.shape.table !== `string`
    ) {
      throw new Error(
        `Invalid shape option. It must be an object with a "table" property that is a string.`
      )
    }
    if (!options.baseUrl) {
      throw new Error(`Invalid shape option. It must provide the baseUrl`)
    }
    if (options.signal && !(options.signal instanceof AbortSignal)) {
      throw new Error(
        `Invalid signal option. It must be an instance of AbortSignal.`
      )
    }

    if (
      options.offset !== undefined &&
      options.offset > -1 &&
      !options.shapeId
    ) {
      throw new Error(
        `shapeId is required if this isn't an initial fetch (i.e. offset > -1)`
      )
    }
  }

  private async startStream() {
    let lastOffset = this.options.offset || -1
    let upToDate = false
    let pollCount = 0

    // Variables for exponential backoff
    let attempt = 0
    const maxDelay = 10000 // 10 seconds in milliseconds
    const initialDelay = 100 // 100 milliseconds
    let delay = initialDelay

    // fetch loop.
    while (
      (!this.options.signal?.aborted && !upToDate) ||
      this.options.subscribe
    ) {
      const url = new URL(
        `${this.options.baseUrl}/shape/${this.options.shape.table}`
      )
      url.searchParams.set(`offset`, lastOffset.toString())
      if (upToDate) {
        url.searchParams.set(`live`, ``)
      } else {
        url.searchParams.set(`notLive`, ``)
      }

      // This should probably be a header for better cache breaking?
      url.searchParams.set(`shapeId`, this.shapeId!)
      console.log(
        `client`,
        { table: this.options.shape.table },
        {
          lastOffset,
          upToDate,
          pollCount,
          url: url.toString(),
        }
      )
      try {
        await fetch(url.toString(), {
          signal: this.options.signal ? this.options.signal : undefined,
        })
          .then(async (response) => {
            if (!response.ok) {
              throw new Error(`HTTP error! Status: ${response.status}`)
            }
            this.shapeId =
              response.headers.get(`x-electric-shape-id`) ?? undefined
            console.log({ shapeId: this.shapeId })
            attempt = 0
            if (response.status === 204) {
              console.log('Server returned 204')
              return []
            }

            return response.json()
          })
          .then((batch: Message[]) => {
            this.publish(batch)

            // Update upToDate & lastOffset
            if (batch.length > 0) {
              const lastMessages = batch.slice(-2)
              lastMessages.forEach((message) => {
                if (message.headers?.[`control`] === `up-to-date`) {
                  upToDate = true
                }
                if (typeof message.offset !== `undefined`) {
                  lastOffset = message.offset
                }
              })
            }

            pollCount += 1
          })
      } catch (e) {
        if (this.options.signal?.aborted) {
          // Break out of while loop when the user aborts the client.
          break
        } else {
          console.log(`fetch failed`, e)

          // Exponentially backoff on errors.
          // Wait for the current delay duration
          await new Promise((resolve) => setTimeout(resolve, delay))

          // Increase the delay for the next attempt
          delay = Math.min(delay * 1.3, maxDelay)

          attempt++
          console.log(`Retry attempt #${attempt} after ${delay}ms`)
        }
      }
    }

    console.log(`client is closed`, this.instanceId)
    this.outsideResolve && this.outsideResolve()
  }

  subscribe(callback: (messages: Message[]) => void | Promise<void>) {
    const subscriber = new Subscriber(callback)
    this.subscribers.push(subscriber)
  }

  publish(messages: Message[]) {
    for (const subscriber of this.subscribers) {
      subscriber.enqueueMessage(messages)
    }
  }
}

/**
 * A Shape is an object that subscribes to a shape log,
 * keeps a materialised shape `.value` in memory and
 * notifies subscribers when the value has changed.
 *
 * It can be used without a framework and as a primitive
 * to simplify developing framework hooks.
 *
 * @constructor
 * @param {stream} a ShapeStream instance
 */
export class Shape {
  private callbacks: Array<ShapeChangedCallback> = []
  private hasSyncedOnce: Boolean = false
  private initiallySyncing: Boolean = false
  private initialSyncPromise?: Promise
  private map: Map = new Map()
  private rejectInitialSync?: () => void
  private resolveInitialSync?: (value: Map) => void
  private stream: ShapeStream

  constructor(stream: ShapeStream) {
    this.stream = stream
  }

  get id() {
    return this.stream.shapeId
  }
  get value() {
    return this.map
  }

  subscribe(callback: ShapeChangedCallback): void {
    this.callbacks.push(callback)
  }

  unsubscribe(callback: ShapeChangedCallback): void {
    this.callbacks.pop(callback)
  }

  unsubscribeAll(): void {
    this.callbacks = []
  }

  async sync(): Map {
    if (this.hasSyncedOnce) {
      return this.value
    }

    if (this.initiallySyncing) {
      return this.initialSyncPromise
    }

    this.initiallySyncing = true

    this.initialSyncPromise = new Promise((resolve, reject) => {
      this.resolveInitialSync = resolve
      this.rejectInitialSync = reject
    })

    const handler = this.handle.bind(this)
    this.stream.subscribe(handler)

    return this.initialSyncPromise
  }

  private handle(messages: Message[]): void {
    let changed = false
    let done = false

    messages.forEach((message) => {
      switch (message.headers?.[`action`]) {
        case `insert`:
        case `update`:
          this.map.set(message.key, message.value)
          changed = true

          break

        case `delete`:
          this.map.delete(message.key)
          changed = true

          break
      }

      if (message.headers?.[`control`] === `up-to-date`) {
        done = true
      }
    })

    if (done) {
      if (this.initiallySyncing) {
        this.resolveInitialSync(this.value)
      }

      if (changed) {
        this.notify()
      }
    }
  }

  private notify(): void {
    this.callbacks.forEach((callback) => {
      callback(this.value)
    })
  }
}
