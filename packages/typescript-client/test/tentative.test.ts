import { describe, expect, inject } from 'vitest'
import { MutableShape, TentativeShapeStream } from '../src/tentative'
import {
  GetKeyFunction,
  MatchFunction,
  MergeFunction,
  Message,
} from '../src/types'
import { testWithIssuesTable as it } from './support/test-context'
import { ShapeStream } from '../src'

const BASE_URL = inject(`baseUrl`)

const localChangeWins: MergeFunction = (c, _) => c
const neverMatch: MatchFunction = () => false
const alwaysMatch: MatchFunction = () => true
const getKeyFunction: GetKeyFunction = (message: Message) => {
  if (`key` in message) {
    return message.value.id as string
  }
  return ``
}

describe(`ShapeStream prePublishHook`, () => {
  it(`fire prePublishHook`, async ({ issuesTableUrl, insertIssues }) => {
    const shapeStream = new ShapeStream({
      shape: { table: issuesTableUrl },
      baseUrl: BASE_URL,
    })

    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000)

      shapeStream.registerPrePublishHook(() => resolve())
      insertIssues({ title: `test title` })
    })
  })
})

describe(`TentativeShapeStream`, () => {
  it(`should sync an empty shape`, async ({ issuesTableUrl }) => {
    const shapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      neverMatch
    )
    const shape = new MutableShape(shapeStream)
    const map = await shape.value

    expect(map).toEqual(new Map())
  })

  it(`drop tentative value after match`, async ({
    issuesTableUrl,
    insertIssues,
  }) => {
    const title = `test title`
    const matchOnTitle: MatchFunction = (_, incoming) =>
      incoming!.value.id === id

    const tentativeShapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      matchOnTitle
    )

    const id = `00000000-0000-0000-0000-000000000000`

    tentativeShapeStream.registerMutation({
      action: `insert`,
      key: id,
      value: { id, title },
    })

    expect(tentativeShapeStream[`handlers`].size).toEqual(1)

    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000)

      insertIssues({ id, title: `test title` })

      tentativeShapeStream.subscribe(() => {
        expect(tentativeShapeStream[`handlers`].size).toEqual(0)
        resolve()
      })
    })
  })
})

describe(`MutableShape`, () => {
  it(`apply merge strategy`, async ({ issuesTableUrl, insertIssues }) => {
    const tentativeShapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      neverMatch
    )

    const mutableShape = new MutableShape(tentativeShapeStream)
    await mutableShape.value

    const id = `00000000-0000-0000-0000-000000000000`
    const title = `test title`

    mutableShape.applyMutation({
      action: `insert`,
      key: id,
      value: { id, title },
    })

    expect(mutableShape.valueSync.get(id)!.title).toEqual(title)
    expect(tentativeShapeStream[`handlers`].size).toEqual(1)

    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000)

      insertIssues({ id, title: `more recent title` })

      tentativeShapeStream.subscribe((message) => {
        expect(mutableShape.valueSync.get(id)!.title).toEqual(title)
        expect(tentativeShapeStream[`handlers`].size).toEqual(1)
        resolve()
      })
    })
  })

  it(`don't merge if match`, async ({ issuesTableUrl, insertIssues }) => {
    const tentativeShapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      alwaysMatch
    )

    const mutableShape = new MutableShape(tentativeShapeStream)
    await mutableShape.value

    const id = `00000000-0000-0000-0000-000000000000`
    const title = `test title`

    mutableShape.applyMutation({
      action: `insert`,
      key: id,
      value: { id, title },
    })

    expect(mutableShape.valueSync.get(id)!.title).toEqual(title)
    expect(tentativeShapeStream[`handlers`].size).toEqual(1)

    const incomingTitle = `more recent title`
    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000)

      insertIssues({ id, title: incomingTitle })

      tentativeShapeStream.subscribe(() => {
        expect(mutableShape.valueSync.get(id)!.title).toEqual(incomingTitle)
        expect(tentativeShapeStream[`handlers`].size).toEqual(0)
        resolve()
      })
    })
  })
})
