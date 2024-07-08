import { MessageProcessor, ShapeStreamOptions } from '../../client'
import { Message } from '../../types'

export class ShapeStreamMock {
  private subscribers: Array<MessageProcessor> = []

  private upToDateSubscribers = new Map<string, () => void>()

  private subscriptionCounter = 0
  public hasBeenUpToDate = false

  private publishHooks: Array<(message: Message) => void> = []

  constructor(_options: ShapeStreamOptions) {}

  subscribe(callback: (messages: Message[]) => void | Promise<void>) {
    const subscriber = new MessageProcessor(callback)
    this.subscribers.push(subscriber)
  }

  publish(messages: Message[]) {
    this.publishHooks.forEach((hook) =>
      messages.forEach((message) => hook(message))
    )

    for (const subscriber of this.subscribers) {
      subscriber.process(messages)
    }
  }

  subscribeOnceToUpToDate(callback: () => void | Promise<void>) {
    const subscriptionId = `${this.subscriptionCounter++}`

    this.upToDateSubscribers.set(subscriptionId, callback)

    return () => {
      this.upToDateSubscribers.delete(subscriptionId)
    }
  }

  unsubscribeAllUpToDateSubscribers(): void {
    this.upToDateSubscribers.clear()
  }

  private notifyUpToDateSubscribers() {
    this.upToDateSubscribers.forEach((callback: any) => callback())
  }

  start() {
    return Promise.resolve()
  }

  stop() {
    return Promise.resolve()
  }

  setLiveMode(value?: boolean) {}

  upToDate() {
    this.hasBeenUpToDate = true
    this.notifyUpToDateSubscribers()
  }

  public registerPublishHook(hook: (message: Message) => void) {
    this.publishHooks.push(hook)

    return () => {
      this.publishHooks = this.publishHooks.filter((h) => h !== hook)
    }
  }
}
