import { beforeAll, afterAll, describe, it, expect, assert } from "vitest"
import { Shape, ShapeStream } from "./client"
import { v4 as uuidv4 } from "uuid"
import { Client } from "pg"

let context: { client: Client }

// const uuid = uuidv4()

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

afterAll(async () => {
  await context.client.query(`TRUNCATE TABLE items`)
  await context.client.end()

  // TODO do any needed server cleanup.
  context = {}
})

describe(`Shape`, () => {
  it(`should sync an empty shape/table`, async () => {

    const stream = new ShapeStream({
      shape: { table: `items` },
      baseUrl: `http://localhost:3000`,
      subscribe: false
    })
    const shape = new Shape(stream)
    const map = await shape.sync()

    expect(map).toEqual(new Map())
  })
})
