import { v4 as uuidv4 } from "uuid";
import { describe, expect, inject } from "vitest";
import { testWithIssuesTable as it } from "../../typescript-client/test/support/test-context";

// need to install monorepo dep
import {
  TentativeShapeStream,
  MutableShape,
} from "../../typescript-client/src/tentative";
import {
  GetKeyFunction,
  MatchFunction,
  MergeFunction,
  Message,
  Mutation as ShapeMutation,
} from "../../typescript-client/src/types";
import { Mutation } from "../src/types";

const localChangeWins: MergeFunction = (c, _) => c;
const neverMatch: MatchFunction = () => false;
const getKeyFunction: GetKeyFunction = (message: Message) => {
  if (`key` in message) {
    return message.value.id as string;
  }
  return ``;
};

const mutationsServerUrl = inject(`mutationsServerUrl`);
const BASE_URL = inject(`baseUrl`);

describe(`mutation server setup`, () => {
  it(`should be up`, async () => {
    const res = await fetch(`${mutationsServerUrl}`);
    expect(res.status).toBe(200);
  });
});

describe(`mutation round trip`, () => {
  it(`match tentative state`, async ({ issuesTableName, issuesTableUrl }) => {
    const title = `hello`;
    const matchOnTitle: MatchFunction = (_, incoming) =>
      incoming!.value.title === title;

    const shapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      matchOnTitle
    );

    const shape = new MutableShape(shapeStream);
    expect((await shape.value).size).toEqual(0);

    const uuid = uuidv4();

    // This will be fixed
    const mutationForServer: Mutation = {
      action: `insert`,
      schema: inject(`testPgSchema`),
      tablename: issuesTableName,
      row: { id: uuid, title, priority: 1 },
    };

    const mutationForShape: ShapeMutation = {
      action: `insert`,
      key: uuid,
      value: { id: uuid, title, priority: 1 },
    };

    shape.applyMutation(mutationForShape);
    expect(shapeStream[`handlers`].size).toEqual(1);

    await new Promise<void>(async (resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000);

      shape.subscribe(() => {
        expect(shapeStream[`handlers`].size).toEqual(0);
        resolve();
      });

      const request = new Request(`${mutationsServerUrl}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify([mutationForServer]),
      });

      const res = await fetch(request);
      expect(res.headers.has(`X-Electric-Postgres-Xid`)).toBeDefined();
    });
  });
});
