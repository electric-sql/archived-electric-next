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
    expect(mutationsServerUrl).toBeDefined();

    await fetch(`${mutationsServerUrl}`).then((res) => {
      expect(res.status).toBe(200);
    });
  });
});

describe(`mutation round trip`, () => {
  it(`match tentative state`, async ({ issuesTableUrl }) => {
    console.log(BASE_URL);

    const shapeStream = new TentativeShapeStream(
      {
        shape: { table: issuesTableUrl },
        baseUrl: BASE_URL,
      },
      getKeyFunction,
      localChangeWins,
      neverMatch
    );
    const shape = new MutableShape(shapeStream);
    const map = await shape.value;

    expect(map).toEqual(new Map());

    const uuid = `00000000-0000-0000-0000-000000000000`;

    // This will be fixed
    const mutationForServer: Mutation = {
      action: `insert`,
      schema: `public`,
      tablename: `issues`,
      row: { id: uuid, title: `hello` },
    };

    const mutationForShape: ShapeMutation = {
      action: `insert`,
      key: uuid,
      value: { id: uuid, title: `hello` },
    };

    shape.applyMutation(mutationForShape);
    expect(shapeStream[`handlers`].size).toEqual(1);

    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000);

      fetch(`${mutationsServerUrl}/mutations`, {
        method: `POST`,
        headers: {
          "Content-Type": `application/json`,
        },
        body: JSON.stringify([mutationForServer]),
      });

      shape.subscribe(() => {
        expect(shapeStream[`handlers`].size).toEqual(0);
        resolve();
      });
    });
  });
});
