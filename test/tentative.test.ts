import { beforeEach, describe, expect, it } from 'vitest'
import { ShapeStreamMock } from './mock/mocks'
import { Shape, ShapeStream } from '../client'
import { TentativeState } from '../tentative'
import { MatchFunction, MergeFunction } from '../types'
import { makeMessage, makeMutation } from './mock/utils'

type Context = {
  stream: ShapeStreamMock
  shape: Shape
  tentative: TentativeState
}

const baseTable = `mock-table`
const shapeDefinition = { table: baseTable }
const streamOptions = {
  baseUrl: '',
  shape: shapeDefinition,
}

const initContext = (subscribe?: boolean) => {
  const stream = new ShapeStreamMock({ ...streamOptions, subscribe })
  const shape = new Shape(shapeDefinition, {}, stream as unknown as ShapeStream)
  const tentative = new TentativeState(shape)

  return { stream, shape, tentative }
}

const getKey = (id: any, table?: string) => `${table ?? baseTable}/${id}`

const returnLocalRow: MergeFunction = (_) => _
const neverMatch: MatchFunction = () => false

beforeEach((context: any) => {
  const { stream, shape, tentative } = initContext(false)
  context.stream = stream
  context.shape = shape
  context.tentative = tentative
})

describe(`Setting up shape with tentative state`, () => {
  it(`can't be modified before syncyinc once`, async (context: Context) => {
    const { tentative } = context

    const mutation = makeMutation('insert', baseTable, { id: '' })
    const setTentativeValue = () =>
      tentative.setTentativeValue(mutation, returnLocalRow, neverMatch)

    expect(setTentativeValue).toThrowError(
      `cannot set tentative value before shape is ready`
    )
  })

  it(`can be modified after first sync`, async (context: Context) => {
    const { shape, tentative, stream } = context

    const synced = shape.syncOnce()
    stream.upToDate()
    await synced

    const localRow = { id: 'id', title: 'test' }
    const mutation = makeMutation('insert', baseTable, localRow)
    tentative.setTentativeValue(mutation, returnLocalRow, neverMatch)

    expect(shape.value.get(getKey(localRow.id))).toBe(localRow)
  })
})

describe(`merge logic`, () => {
  beforeEach(({ stream }: Context) => {
    stream.upToDate()
  })

  it(`merge function works`, async ({ shape, tentative, stream }: Context) => {
    const id = 'id'

    const localRow = { id, title: 'test' }
    const mutation = makeMutation('insert', baseTable, localRow)
    tentative.setTentativeValue(mutation, returnLocalRow, neverMatch)

    const isUpToDate = shape.isUpToDate
    const incoming = { id, title: 'incoming' }
    stream.publish([makeMessage('insert', baseTable, incoming)])
    stream.upToDate()
    await isUpToDate

    expect(shape.value.get(getKey(id))).toBe(localRow)
  })

  it(`ignore tentative mutations after destroy`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const localRow = { id, title: 'test' }
    const mutation = makeMutation('insert', baseTable, localRow)
    tentative.setTentativeValue(mutation, returnLocalRow, neverMatch)

    tentative.destroy()

    const isUpToDate = shape.isUpToDate
    const incoming = { id, title: 'incoming' }
    stream.publish([makeMessage('insert', baseTable, incoming)])
    stream.upToDate()
    await isUpToDate

    expect(shape.value.get(getKey(id))).toBe(incoming)
  })

  it(`merge function is applied multiple times`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const concatTitle: MergeFunction = (current, incoming) => ({
      action: 'update',
      key: current.key,
      value: {
        id: current.value.id,
        title: `${current.value.title}${incoming.value.title}`,
      },
    })

    const localRow = { id, title: 'foo' }
    const mutation = makeMutation('insert', baseTable, localRow)
    tentative.setTentativeValue(mutation, concatTitle, neverMatch)

    const isUpToDate1 = shape.isUpToDate
    const incoming1 = { id, title: 'bar' }
    stream.publish([makeMessage('insert', baseTable, incoming1)])
    stream.upToDate()
    await isUpToDate1

    const isUpToDate2 = shape.isUpToDate
    const incoming2 = { id, title: 'baz' }
    stream.publish([makeMessage('insert', baseTable, incoming2)])
    stream.upToDate()
    await isUpToDate2

    expect(shape.value.get(getKey(id)).title).toBe('foobarbaz')
  })
})

describe(`match logic`, () => {
  beforeEach(({ stream }: Context) => {
    stream.upToDate()
  })

  it(`no more merging after match`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const id = 'id'

    const localRow = { id, title: 'local wins' }
    const mutation = makeMutation('insert', baseTable, localRow)

    const matchOnSameRowValues: MatchFunction = (current, incoming) =>
      current?.key === incoming?.key && current?.value === incoming?.value

    tentative.setTentativeValue(mutation, returnLocalRow, matchOnSameRowValues)

    const isUpToDate1 = shape.isUpToDate
    const incoming1 = { id, title: 'first incoming' }
    stream.publish([makeMessage('insert', baseTable, incoming1)])
    stream.upToDate()
    await isUpToDate1

    expect(shape.value.get(getKey(id))).toBe(localRow)

    const isUpToDate2 = shape.isUpToDate
    const incoming2 = { id, title: 'second incoming' }
    stream.publish([makeMessage('insert', baseTable, localRow)])
    stream.publish([makeMessage('insert', baseTable, incoming2)])
    stream.upToDate()
    await isUpToDate2

    expect(shape.value.get(getKey(id)).title).toBe('second incoming')
    expect(tentative.isTentativeKey(getKey(id))).toBe(false)
  })
})
