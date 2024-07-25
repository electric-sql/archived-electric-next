import { Shape, ShapeStream, ShapeStreamOptions } from './client'
import {
  GetKeyFunction,
  MatchFunction,
  MergeFunction,
  Message,
  Mutation,
} from './types'

type TentativeStateHandler = (incoming: Mutation) => Mutation

export class MutableShape extends Shape {
  protected stream: TentativeShapeStream

  constructor(stream: TentativeShapeStream) {
    super(stream)
    this.stream = stream
  }

  // FIX: a mutation should be a group of effects
  applyMutation(
    mutation: Mutation,
    mergeFunction?: MergeFunction,
    matchFunction?: MatchFunction
  ) {
    // I'm not sure about lifting this restriction, so I'm leaving it here
    if (!this.hasNotifiedSubscribersUpToDate) {
      throw new Error(`cannot set tentative value before shape is ready`)
    }

    const key = mutation.key
    const exists = this.valueSync.get(key)

    if (!exists && mutation.action === `delete`) {
      throw new Error(`cannot delete non-existent key ${key}`)
    }
    if (exists && mutation.action === `insert`) {
      throw new Error(`cannot insert existing key ${key}`)
    }

    if (mutation.action === `delete`) {
      this.valueSync.delete(key)
    } else {
      this.valueSync.set(key, mutation.value)
    }

    this.stream.registerMutation(mutation, mergeFunction, matchFunction)
  }
}

export class TentativeShapeStream extends ShapeStream {
  private handlers: Map<string, TentativeStateHandler>

  private defaultMergeFunction?: MergeFunction
  private defaultMatchFunction?: MatchFunction
  private getKey: GetKeyFunction

  private prePublishHookCloseHandler: () => void

  constructor(
    options: ShapeStreamOptions,
    getKey: GetKeyFunction,
    mergeFunction?: MergeFunction,
    matchFunction?: MatchFunction
  ) {
    super(options)

    this.handlers = new Map()

    this.getKey = getKey
    this.defaultMergeFunction = mergeFunction
    this.defaultMatchFunction = matchFunction

    this.prePublishHookCloseHandler = this.registerPrePublishHook((m) =>
      this.modifyAgainstTentativeState(m)
    )
  }

  destroy() {
    this.prePublishHookCloseHandler()
  }

  registerMutation(
    mutation: Mutation,
    mergeFunction?: MergeFunction,
    matchFunction?: MatchFunction
  ) {
    const merge = mergeFunction ?? this.defaultMergeFunction
    const match = matchFunction ?? this.defaultMatchFunction

    if (merge === undefined || match === undefined) {
      throw new Error(
        `No merge or match function defined for the mutation your are trying to register`
      )
    }

    const key = mutation.key
    const handler = this.makeTentativeStateHandler(mutation, merge, match)

    this.handlers.set(key, handler)
  }

  modifyAgainstTentativeState(message: Message) {
    if (!(`key` in message)) {
      return
    }

    const { value, headers } = message

    const key = this.getKey(message)

    const handler = this.handlers.get(key!)
    if (handler) {
      const incomingMutation = {
        action: headers?.[`action`] as `insert` | `update` | `delete`,
        key: key!,
        value,
      }

      const mutation = handler(incomingMutation)

      message.headers[`action`] = mutation.action
      message.value = mutation.value
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
