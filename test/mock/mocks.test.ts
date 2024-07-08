import { describe, expect, it } from 'vitest'
import { ShapeStreamMock } from './mocks'
import { Shape, ShapeStream } from '../../client'
import { makeMessage } from './utils'

describe(`Shape works with MockStream`, () => {
  it.only(`should sync an empty shape/table`, async () => {
    const table = `mock-table`
    const options = {
      subscribe: true,
      shape: { table },
    }

    const stream = new ShapeStreamMock(options)
    const shape = new Shape(stream as unknown as ShapeStream)

    const sync = shape.sync()

    stream.upToDate()

    const map = await sync
    expect(map).toEqual(new Map())
  })

  it.only(`should sync an empty shape/table with subscribe: true`, async (context) => {
    const table = `mock-table`
    const options = {
      subscribe: true,
      shape: { table },
    }

    const stream = new ShapeStreamMock(options)
    const shape = new Shape(stream as unknown as ShapeStream)

    const sync = shape.sync()

    stream.upToDate()

    const map = await sync
    expect(map).toEqual(new Map())
  })

  it.only(`should initially sync a shape/table`, async () => {
    const table = `mock-table`
    const options = {
      subscribe: true,
      shape: { table },
    }

    const stream = new ShapeStreamMock(options)
    const shape = new Shape(stream as unknown as ShapeStream)

    const id = `id`
    const title = `title`
    const message = makeMessage('insert', table, { id, title })

    const sync = shape.sync()

    stream.publish([message])
    stream.upToDate()
    const map = await sync

    const expectedValue = new Map()
    expectedValue.set(message.key, message.value)

    expect(map).toEqual(expectedValue)
  })

  it.only(`should notify with the initial value`, async () => {
    const table = `mock-table`
    const options = {
      subscribe: true,
      shape: { table },
    }

    const stream = new ShapeStreamMock(options)
    const shape = new Shape(stream as unknown as ShapeStream)

    const id = `id`
    const title = `title`
    const message = makeMessage('insert', table, { id, title })
    const hasUpdated = new Promise((resolve) => {
      shape.subscribe(resolve)
    })
    shape.sync()
    stream.publish([message])
    stream.upToDate()

    const map = await hasUpdated

    const expectedValue = new Map()
    expectedValue.set(message.key, { id, title })

    expect(map).toEqual(expectedValue)
  })

  it.only(`should continually sync a shape/table`, async () => {
    const table = `mock-table`
    const options = {
      subscribe: true,
      shape: { table },
    }

    const stream = new ShapeStreamMock(options)
    const shape = new Shape(stream as unknown as ShapeStream)

    const id1 = `id1`
    const title1 = `title1`
    const message1 = makeMessage('insert', table, { id: id1, title: title1 })

    const sync = shape.sync()
    stream.publish([message1])
    stream.upToDate()

    const map = await sync

    const expectedValue = new Map()
    expectedValue.set(message1.key, { id: id1, title: title1 })
    expect(map).toEqual(expectedValue)

    const hasUpdated = new Promise((resolve) => {
      shape.subscribe(resolve)
    })

    const id2 = `id2`
    const title2 = `fake-title`
    const message2 = makeMessage('insert', table, { id: id2, title: title2 })

    stream.publish([message2])
    stream.upToDate()
    await hasUpdated

    expectedValue.set(message2.key, message2.value)
    expect(shape.value).toEqual(expectedValue)

    shape.unsubscribeAll()
  })
})
