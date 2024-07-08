import { beforeEach, describe, expect, it } from 'vitest'
import { ShapeStreamMock } from './mocks'
import { Shape, ShapeOptions, ShapeStream } from '../../client'
import { makeMessage } from './utils'

type Context = {
  shape: Shape
  stream: ShapeStreamMock
}

const table = `mock-table`
const shapeDefinition = { table }
const streamOptions = {
  baseUrl: '',
  shape: shapeDefinition,
  subscribe: true,
}

const initContext = () => {
  const stream = new ShapeStreamMock(streamOptions)
  const shape = new Shape(shapeDefinition, {}, stream as unknown as ShapeStream)

  return { shape, stream }
}

beforeEach((context: any) => {
  const { shape, stream } = initContext()
  context.shape = shape
  context.stream = stream
})

describe(`Shape works with MockStream`, () => {
  it(`should initially syncOnce a shape/table`, async ({ shape }: Context) => {
    expect(shape.value).toEqual(new Map())
  })

  it(`should keep returning an empty shape if no more updates`, async (context: Context) => {
    const { shape, stream } = context

    const isUpToDate = shape.isUpToDate

    stream.upToDate()

    await isUpToDate

    expect(shape.value).toEqual(new Map())
  })

  it(`should initially sync a shape/table`, async (context: Context) => {
    const { shape, stream } = context

    const id = `id`
    const title = `title`
    const message = makeMessage('insert', table, { id, title })

    const isUpToDate = shape.isUpToDate
    stream.publish([message])
    stream.upToDate()

    const expectedValue = new Map()
    expectedValue.set(message.key, message.value)

    expect(await isUpToDate).toEqual(expectedValue)
  })

  it(`should notify with the initial value`, async (context: Context) => {
    const { shape, stream } = context

    const id = `id`
    const title = `title`
    const message = makeMessage('insert', table, { id, title })

    const isUpToDate = shape.isUpToDate
    stream.publish([message])
    stream.upToDate()

    const expectedValue = new Map()
    expectedValue.set(message.key, { id, title })

    expect(await isUpToDate).toEqual(expectedValue)
  })

  it(`should continually sync a shape/table`, async (context: Context) => {
    const { shape, stream } = context

    const id1 = `id1`
    const title1 = `title1`
    const message1 = makeMessage('insert', table, { id: id1, title: title1 })

    const isUpToDate1 = shape.isUpToDate
    stream.publish([message1])
    stream.upToDate()
    await isUpToDate1

    const expectedValue = new Map()
    expectedValue.set(message1.key, { id: id1, title: title1 })
    expect(shape.value).toEqual(expectedValue)

    const id2 = `id2`
    const title2 = `fake-title`
    const message2 = makeMessage('insert', table, { id: id2, title: title2 })

    const isUpToDate2 = shape.isUpToDate
    stream.publish([message2])
    stream.upToDate()
    await isUpToDate2

    expectedValue.set(message2.key, message2.value)
    expect(shape.value).toEqual(expectedValue)

    shape.unsubscribeAll()
  })
})
