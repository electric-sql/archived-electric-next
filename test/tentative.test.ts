import { beforeEach, describe, expect, it } from 'vitest'
import { ShapeStreamMock } from './mock/mocks'
import { Shape, ShapeStream } from '../client'
import { TentativeState } from '../tentative'
import { MatchFunction, MergeFunction, Mutation } from '../types'
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

describe(`row matching works`, () => {
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

type ShoppingCartItem = {
  id: string
  cartId: string
  amount: number
  lastRequestId: string // used to match a request with a row
}

describe(`usage examples`, () => {
  beforeEach(({ stream }: Context) => {
    stream.upToDate()
  })

  it(`shopping cart with tentative state`, async ({
    shape,
    tentative,
    stream,
  }: Context) => {
    const cartId = 'cart-id'
    const id = 'item-1'
    const key1 = getKey(`${cartId}/${id}`)

    // make an out-of-band api call to add an item to the cart
    // const resp = fetch(`https://service-endpoint/cart/${cartId}/`, {
    //   method: 'POST',
    //   headers: {
    //     'Content-Type': 'application/json'
    //   },
    //   body: JSON.stringify({
    //     id,
    //     amount: 1
    //   })
    // })

    // the response returns a requestId to match with lastRequestId
    const requestId = 'fake-request-id'

    // define the merge function for shopping cart items
    const merge: MergeFunction = (current, incoming) => {
      const value = {
        ...current.value,
        amount: current.value.amount + incoming.value.amount,
      }
      return { ...current, value }
    }

    // define the matching function for the result of the request
    const match: MatchFunction = (current, incoming) =>
      incoming?.value.lastRequestId === current?.value.lastRequestId

    // store the change to the tentative state of the shape
    const mutation: Mutation = {
      action: 'insert',
      key: key1,
      value: { cartId, id, amount: 1, lastRequestId: requestId },
    }
    tentative.setTentativeValue(mutation, merge, match)

    // a concurrent add for same item
    const isUpToDate1 = shape.isUpToDate
    const incoming1 = {
      id,
      cartId,
      amount: 2,
      lastRequestId: 'another-request-1',
    }
    stream.publish([makeMessage('insert', getKey(cartId), incoming1)])
    stream.upToDate()
    await isUpToDate1
    expect(shape.value.get(key1).amount).toBe(3)

    // a new item is added to the cart
    const id2 = 'another-id'
    const key2 = getKey(`${cartId}/${id2}`)

    const isUpToDate2 = shape.isUpToDate
    const incoming2 = {
      id: id2,
      cartId,
      amount: 1,
      lastRequestId: 'another-request-2',
    }

    stream.publish([makeMessage('insert', getKey(cartId), incoming2)])
    stream.upToDate()
    await isUpToDate2
    expect(shape.value.get(key2).amount).toBe(1)

    // match response
    const isUpToDate3 = shape.isUpToDate
    const incoming3 = {
      id,
      cartId,
      amount: 3,
      lastRequestId: requestId,
    }

    stream.publish([makeMessage('insert', getKey(cartId), incoming3)])
    stream.upToDate()
    await isUpToDate3
    expect(tentative.isTentativeKey(key1)).toBe(false)

    // The client can persist the tentative state and catch up with
    // the stream later while the shape_id for the shape definition
    // does not change.
    // This way, the shape stream is guaranteed to send the matching
    // message, otherwise, the initial query for the shape might
    // have already 'compated' request_id.
  })
})