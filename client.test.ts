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
  client: Client,
  tablename: string
}

/*
 * We need to work hard to get proper seperation between tests.
 *
 * The database has a replication stream.
 * The sync service has shape logs.
 *
 * So, we isolote each test to its own table and we clean
 * up the DB and shape log after each test.
 */
beforeAll(async () => {
  const client = new Client({
    host: `localhost`,
    port: 54321,
    password: `password`,
    user: `postgres`,
    database: `electric`,
  })
  await client.connect()

  context = { client }

  return async () => {
    await context.client.end()
  }
})
beforeEach(async () => {
  const aborter = new AbortController()

  const tablename = `items${uuidv4().replaceAll('-', '').slice(25)}`
  await context.client.query(
    `CREATE TABLE ${tablename} (
      id UUID PRIMARY KEY,
      title TEXT NOT NULL
    );`
  )

  context.aborter = aborter
  context.tablename = tablename

  return async () => {
    aborter.abort()

    const resp = await fetch(
      `http://localhost:3000/shape/${tablename}`, {
        method: 'DELETE'
      }
    )

    await context.client.query(`DROP TABLE ${tablename}`)
  }
})

describe(`Shape`, () => {
  it(`should sync an empty shape/table`, async () => {
    const { aborter, tablename } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal,
      subscribe: false
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    expect(map).toEqual(new Map())
  })

  it(`should sync an empty shape/table with subscribe: true`, async () => {
    const { aborter, tablename } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal,
      subscribe: true
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    expect(map).toEqual(new Map())
  })

  it(`should initially sync a shape/table`, async () => {
    const { aborter, client, tablename } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test3 ${id}`
    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    const expectedValue = new Map()
    expectedValue.set(`"public"."${tablename}"/${id}`, {
      "id": id,
      "title": title,
    })

    expect(map).toEqual(expectedValue)
  })

  it(`should notify with the initial value`, async () => {
    const { aborter, client, tablename } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test3 ${id}`
    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const hasUpdated = new Promise((resolve) => {
      shape.subscribe(resolve)
    })
    shape.sync()
    const map = await hasUpdated

    const expectedValue = new Map()
    expectedValue.set(`"public"."${tablename}"/${id}`, {
      "id": id,
      "title": title,
    })

    expect(map).toEqual(expectedValue)
  })

  it(`should continually sync a shape/table`, async () => {
    const { aborter, client, tablename } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test4 ${id}`
    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const map = await shape.sync()

    const expectedValue = new Map()
    expectedValue.set(`"public"."${tablename}"/${id}`, {
      "id": id,
      "title": title,
    })
    expect(map).toEqual(expectedValue)

    const hasUpdated = new Promise((resolve) => {
      shape.subscribe(resolve)
    })

    const id2 = uuidv4()
    const title2 = `Test4 ${id2}`

    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id2, title2])
    await hasUpdated

    expectedValue.set(`"public"."${tablename}"/${id2}`, {
      "id": id2,
      "title": title2,
    })
    expect(shape.value).toEqual(expectedValue)

    shape.unsubscribeAll()
  })

  it(`should notify subscribers when the value changes`, async () => {
    const { aborter, client, tablename } = context

    // Add an item.
    const id = uuidv4()
    const title = `Test5 1 ${id}`
    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id, title])

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
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
    await client.query(`insert into ${tablename} (id, title) values ($1, $2)`, [id2, title2])

    const value = await hasChanged
    const expectedValue = new Map()
    expectedValue.set(`"public"."${tablename}"/${id}`, {
      "id": id,
      "title": title,
    })
    expectedValue.set(`"public"."${tablename}"/${id2}`, {
      "id": id2,
      "title": title2,
    })
    expect(value).toEqual(expectedValue)

    shape.unsubscribeAll()
  })

  it(`should support unsubscribe`, async () => {
    const { aborter, client, tablename } = context

    const stream = new ShapeStream({
      baseUrl: `http://localhost:3000`,
      shape: { table: tablename },
      signal: aborter.signal
    })

    const shape = new Shape(stream)
    const subscriptionId = shape.subscribe((value) => { console.log(value) })
    shape.unsubscribe(subscriptionId)

    expect(shape.numSubscribers).toBe(0)
  })
})
