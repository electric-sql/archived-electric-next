import { ShapeStreamOptions, Subscriber } from '../../client'
import { Message } from '../../types'

type ShapeStreamOptionsMock = Omit<ShapeStreamOptions, 'baseUrl'>

export class ShapeStreamMock {
  private options: ShapeStreamOptionsMock
  private subscribers: Array<Subscriber> = []

  constructor(options: ShapeStreamOptionsMock) {
    this.options = options
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

  upToDate() {
    const upToDate: Message = {
      key: this.options.shape.table,
      headers: {
        control: `up-to-date`,
      },
    }

    this.publish([upToDate])
  }
}
