import { beforeEach, describe, expect, it } from 'vitest'
import { ShapeStreamMock } from './mock/mocks'
import { Shape, ShapeStream } from '../client'
import { TentativeState } from '../tentative-shape'
import { MatchFunction, MergeFunction } from '../types'
import { makeMessage, makeMutation } from './mock/utils'

type Context = {
  shape: Shape
  tentative: TentativeState
  stream: ShapeStreamMock
}

const baseTable = 'table'
const getKey = (id: any, table?: string) => `${table ?? baseTable}/${id}`

const returnLocal: MergeFunction = (_) => _
const returnIncoming: MergeFunction = (_, incoming) => incoming!

const neverMatch = () => false

const getHasUpdatedPromise = (shape: Shape) =>
  new Promise((resolve) => {
    shape.subscribe(resolve)
  })

const initContext = () => {
  const options = {
    subscribe: true,
    shape: { table: baseTable },
  }

  const stream = new ShapeStreamMock(options)
  const shape = new Shape(stream as unknown as ShapeStream)
  return { shape, tentative: new TentativeState(shape), stream }
}

beforeEach((context: any) => {
  const { shape, tentative, stream } = initContext()
  context.shape = shape
  context.tentative = tentative
  context.stream = stream
})

describe(`Setting up shape with tentative state`, () => {
  it(`can't be modified before sync`, async ({ tentative }: Context) => {
    const mutation = makeMutation('insert', baseTable, { id: '' })

    expect(() =>
      tentative.setTentativeValue(mutation, returnLocal, neverMatch)
    ).toThrowError('cannot set tentative value before shape is ready')
  })

  it(`can be modified after sync`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const tentativeRow = { id: 'id', title: 'test' }
    const mutation = makeMutation('insert', baseTable, tentativeRow)
    const ready = shape.sync()
    stream.upToDate()

    await ready
    tentative.setTentativeValue(mutation, returnLocal, neverMatch)

    expect(shape.value.get(getKey(tentativeRow.id))).toBe(tentativeRow)
  })
})

describe(`merge logic`, () => {
  beforeEach(async ({ shape, stream }: any) => {
    const ready = shape.sync()
    stream.upToDate()
    await ready
  })

  it(`merge function is applied`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const tentativeRow = { id, title: 'test' }
    const tentativeMutation = makeMutation('insert', baseTable, tentativeRow)
    tentative.setTentativeValue(tentativeMutation, returnLocal, neverMatch)

    const hasUpdated = getHasUpdatedPromise(shape)

    const incoming = { id, title: 'incoming' }
    stream.publish([makeMessage('insert', baseTable, incoming)])
    stream.upToDate()

    await hasUpdated

    expect(shape.value.get(getKey(id))).toBe(tentativeRow)
  })

  it(`merge function is applied multiple times`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const tentativeRow = { id, title: 'test' }
    const tentativeMutation = makeMutation('insert', baseTable, tentativeRow)
    tentative.setTentativeValue(tentativeMutation, returnLocal, neverMatch)

    const hasUpdated = getHasUpdatedPromise(shape)

    const incoming1 = { id, title: 'incoming1' }
    stream.publish([makeMessage('insert', baseTable, incoming1)])
    stream.upToDate()

    await hasUpdated

    const hasUpdatedAgain = getHasUpdatedPromise(shape)

    const incoming2 = { id, title: 'incoming2' }
    stream.publish([makeMessage('insert', baseTable, incoming2)])
    stream.upToDate()

    await hasUpdatedAgain

    expect(shape.value.get(getKey(id))).toBe(tentativeRow)
  })

  it(`ignore tentative mutations after destroy`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const tentativeRow = { id, title: 'test' }
    const mutation = makeMutation('insert', baseTable, tentativeRow)
    const ready = shape.sync()
    stream.upToDate()

    await ready
    tentative.setTentativeValue(mutation, returnLocal, neverMatch)

    expect(shape.value.get(getKey(id))).toBe(tentativeRow)

    tentative.destroy()

    const hasUpdated = getHasUpdatedPromise(shape)

    const incoming = { id, title: 'incoming' }
    stream.publish([makeMessage('insert', baseTable, incoming)])
    stream.upToDate()

    await hasUpdated

    expect(shape.value.get(getKey(id))).toBe(incoming)
  })
})

describe(`match logic`, () => {
  beforeEach(async ({ shape, stream }: any) => {
    const ready = shape.sync()
    stream.upToDate()
    await ready
  })

  it(`no more merging after match`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const tentativeRow = { id, title: 'local wins' }
    const tentativeMutation = makeMutation('insert', baseTable, tentativeRow)

    const matchOnSameRowValues: MatchFunction = (current, incoming) =>
      current?.key === incoming?.key && current?.value === incoming?.value

    tentative.setTentativeValue(
      tentativeMutation,
      returnLocal,
      matchOnSameRowValues
    )

    const hasUpdated = getHasUpdatedPromise(shape)

    const incoming1 = { id, title: 'merge replaces this value' }
    stream.publish([makeMessage('insert', baseTable, incoming1)])
    stream.upToDate()

    await hasUpdated

    expect(shape.value.get(getKey(id))).toBe(tentativeRow)

    const hasUpdatedAgain = getHasUpdatedPromise(shape)

    const incoming2 = { id, title: 'new remote' }

    // after receiving row with tentative values, drop tentative change
    stream.publish([
      makeMessage('insert', baseTable, tentativeRow),
      makeMessage('insert', baseTable, incoming2),
    ])
    stream.upToDate()

    await hasUpdatedAgain

    expect(shape.value.get(getKey(id)).title).toBe('new remote')
    expect(tentative.isTentativeKey(getKey(id))).toBe(false)
  })
})
