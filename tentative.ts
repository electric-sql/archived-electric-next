import { Shape } from './client'
import { MatchFunction, MergeFunction, Message, Mutation } from './types'

type TentativeStateHandler = (incoming: Mutation) => Mutation

export class TentativeState {
  private shape: Shape
  private handlers: Map<string, TentativeStateHandler>

  private deregisterPublishHook: () => void

  constructor(shape: Shape) {
    this.shape = shape
    this.handlers = new Map()
    this.deregisterPublishHook = this.shape.stream.registerPublishHook(
      (message) => this.applyTentativeState(message)
    )
  }

  destroy() {
    this.deregisterPublishHook()
    // this.handlers.clear()
  }

  applyTentativeState(message: Message) {
    if (!message.headers?.[`action`]) {
      return
    }

    const { key, value, headers } = message

    const handler = this.handlers.get(key!)
    if (handler) {
      const incomingMutation = {
        action: headers?.[`action`] as 'insert' | 'update' | 'delete',
        key: key!,
        value,
      }

      const mutation = handler(incomingMutation)

      if (message.headers === undefined) {
        message.headers = {}
      }
      message.headers[`action`] = mutation.action
      message.value = mutation.value
    }
  }

  setTentativeValue<T>(
    mutation: Mutation,
    merge: MergeFunction,
    match: MatchFunction
  ) {
    if (!this.shape.stream.hasBeenUpToDate) {
      throw new Error('cannot set tentative value before shape is ready')
    }

    const key = mutation.key
    const exists = this.shape.value.get(key)

    if (!exists && mutation.action === 'delete') {
      throw new Error(`cannot delete non-existent key ${key}`)
    }
    if (exists && mutation.action === 'insert') {
      throw new Error(`cannot insert existing key ${key}`)
    }

    const handler = this.makeTentativeStateHandler(mutation, merge, match)
    this.handlers.set(key, handler)

    if (mutation.action === 'delete') {
      this.shape.value.delete(key)
    } else {
      this.shape.value.set(key, mutation.value)
    }
  }

  private makeTentativeStateHandler =
    (current: Mutation, merge: MergeFunction, match: MatchFunction) =>
    (incoming: Mutation) => {
      const key = current.key

      const isMatch = match(current, incoming)
      if (isMatch) {
        this.handlers.delete(key)
        return incoming
      } else {
        const merged = merge(current, incoming)
        const newHandler = this.makeTentativeStateHandler(merged, merge, match)
        this.handlers.set(key, newHandler)
        return merged
      }
    }

  isTentativeKey(key: string) {
    return this.handlers.has(key)
  }
}
