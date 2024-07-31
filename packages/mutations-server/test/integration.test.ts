import { v7 as uuidv7 } from "uuid";
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
import { buildRequest } from "../src/utils";

const localChangeWins: MergeFunction = (c, _) => c;
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

  it(`request requires headers`, async () => {
    const request = new Request(`${mutationsServerUrl}`, {
      method: `POST`,
    });

    const res = await fetch(request);
    expect(res.status).toBe(400);
  });
});

describe(`mutation round trip`, () => {
  it(`idempotency test`, async ({ issuesTableName, insertIssues }) => {
    // hack to init schema
    await insertIssues({ title: `test title` });

    const uuid = uuidv7();

    const mutationForServer: Mutation = {
      action: `insert`,
      schema: inject(`testPgSchema`),
      tablename: issuesTableName,
      row: { id: uuid, title: `test title`, priority: 1 },
    };

    const request1 = buildRequest(mutationsServerUrl, `fake-user`, uuid, [
      mutationForServer,
    ]);

    const res1 = await fetch(request1);
    expect(res1.status).toEqual(200);
    const xid1 = res1.headers.get(`X-Electric-Postgres-Xid`);

    const request2 = buildRequest(mutationsServerUrl, `fake-user`, uuid, [
      mutationForServer,
    ]);

    const res2 = await fetch(request2);
    expect(res2.status).toEqual(200);

    const xid2 = res2.headers.get(`X-Electric-Postgres-Xid`);
    expect(xid2).toEqual(xid1);
  });

  it(`late operations are rejected`, async ({
    issuesTableName,
    insertIssues,
  }) => {
    // hack to init schema
    await insertIssues({ title: `test title` });

    const oldUuid = uuidv7();
    const newUuid = uuidv7();

    const mutationForServer: Mutation = {
      action: `insert`,
      schema: inject(`testPgSchema`),
      tablename: issuesTableName,
      row: { id: uuidv7(), title: `test title`, priority: 1 },
    };

    const request1 = buildRequest(mutationsServerUrl, `fake-user`, newUuid, [
      mutationForServer,
    ]);
    await fetch(request1);

    const request2 = buildRequest(mutationsServerUrl, `fake-user`, oldUuid, [
      mutationForServer,
    ]);
    const res2 = await fetch(request2);
    expect(res2.status).toEqual(409);
  });

  it(`match tentative state`, async ({ issuesTableName, issuesTableUrl }) => {
    const title = `hello`;
    const matchOnTitle: MatchFunction = (_, incoming) =>
      incoming!.value.title === title;

    const shapeStream = new TentativeShapeStream({
      shape: { table: issuesTableUrl },
      baseUrl: BASE_URL,
      getKey: getKeyFunction,
      mergeFunction: localChangeWins,
      matchFunction: matchOnTitle,
    });

    const shape = new MutableShape(shapeStream);
    expect((await shape.value).size).toEqual(0);

    const uuid = uuidv7();

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

    await new Promise<void>((resolve, reject) => {
      setTimeout(() => reject(`Timed out waiting for data changes`), 1000);

      shape.subscribe(() => {
        expect(shapeStream[`handlers`].size).toEqual(0);
        resolve();
      });

      const request = buildRequest(mutationsServerUrl, `fake-user`, uuidv7(), [
        mutationForServer,
      ]);

      fetch(request).then((res) =>
        expect(res.headers.has(`X-Electric-Postgres-Xid`)).toBeTruthy(),
      );
    });
  });
});
