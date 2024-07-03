import { Client } from "pg"
import { v4 as uuidv4 } from "uuid"
import {
  afterAll,
  afterEach,
  assert,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it
} from "vitest"

import { Shape, ShapeStream } from "./client"

let context: {
  aborter?: AbortController,
  client: Client
}

beforeAll(async () => {
  const client = new Client({
    host: `localhost`,
    port: 54321,
    password: `password`,
    user: `postgres`,
    database: `electric`,
  })
  await client.connect()
  await client.query(
    `CREATE TABLE IF NOT EXISTS items (
        id UUID PRIMARY KEY,
        title TEXT NOT NULL
    );`
  )

  context = { client }
})
beforeEach(async () => {
  context.aborter = new AbortController()
})
afterEach(async () => {
  context.aborter.abort()

  await context.client.query(`TRUNCATE TABLE items`)
})
afterAll(async () => {
  await context.client.end()

  // TODO do any needed server cleanup.
  context = {}
})

describe(`Shape`, () => {
  it(`should sync an empty shape/table`, async () => {
    const { aborter } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal,
      subscribe: false
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    expect(map).toEqual(new Map())
  })

  it(`should sync an empty shape/table with subscribe: true`, async () => {
    const { aborter } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    expect(map).toEqual(new Map())
  })

  it(`should initially sync a shape/table`, async () => {
    const { aborter, client } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test3 ${id}`

    await client.query(`insert into items (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    const expectedValue = new Map()
    expectedValue.set(`public-items-${id}`, {
      "id": id,
      "title": title,
    })

    expect(map).toEqual(expectedValue)
  })

  it(`should continually sync a shape/table`, async () => {
    const { aborter, client } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test4 ${id}`

    await client.query(`insert into items (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    const expectedValue = new Map()
    expectedValue.set(`public-items-${id}`, {
      "id": id,
      "title": title,
    })
    expect(map).toEqual(expectedValue)

    const hasUpdated = new Promise((resolve) => {
      shape.subscribe(resolve)
    })

    const id2 = uuidv4()
    const title2 = `Test4 ${id2}`

    await client.query(`insert into items (id, title) values ($1, $2)`, [id2, title2])
    await hasUpdated

    expectedValue.set(`public-items-${id2}`, {
      "id": id2,
      "title": title2,
    })
    expect(shape.value).toEqual(expectedValue)

    shape.unsubscribeAll()
  }, 1000)

  it(`should notify subscribers when the value changes`, async () => {
    const { aborter, client } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test5 1 ${id}`

    await client.query(`insert into items (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    await shape.sync()

    const hasChanged = new Promise((resolve) => {
      shape.subscribe((value) => {
        resolve(value)
      })
    })

    // Add an item.
    const id2 = uuidv4()
    const title2 = `Test5 2 ${id2}`

    await client.query(`insert into items (id, title) values ($1, $2)`, [id2, title2])
    const value = await hasChanged

    const expectedValue = new Map()
    expectedValue.set(`public-items-${id}`, {
      "id": id,
      "title": title,
    })
    expectedValue.set(`public-items-${id2}`, {
      "id": id2,
      "title": title2,
    })
    expect(value).toEqual(expectedValue)

    shape.unsubscribeAll()
  }, 1000)

  it(`should support unsubscribe`, async () => {
    const { aborter, client } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: `items` },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const subscriptionId = shape.subscribe((value) => { console.log(value) })
    shape.unsubscribe(subscriptionId)

    expect(shape.numSubscribers).toBe(0)
  })
})
