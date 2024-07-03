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
    const title = `Item ${id}`

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
      "title": `Item ${id}`,
    })

    expect(map).toEqual(expectedValue)
  })
})
