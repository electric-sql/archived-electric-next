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
import { v4 as uuidv4 } from 'uuid'

const BASE_URL = inject(`baseUrl`)

const localChangeWins: MergeFunction = (c, _) => c
const neverMatch: MatchFunction = () => false
const getKeyFunction: GetKeyFunction = (message: Message) => {
  if (`key` in message) {
    return message.value.title as string
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
      localChangeWins,
      neverMatch,
      getKeyFunction
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
      incoming!.value.title === title

    const tentativeShapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      localChangeWins,
      matchOnTitle,
      getKeyFunction
    )

    const id = uuidv4()

    tentativeShapeStream.registerMutation({
      action: `insert`,
      key: title,
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
