import express, { Request, Response, NextFunction } from "express";
import bodyParser from "body-parser";
import "dotenv/config";
import { Client } from "pg";
import { Writer } from "./writer";
import { bodyToMutation } from "./utils";
import { Server } from "http";

const app = express();
app.use(bodyParser.json());

const port = process.env.MUTATIONS_SERVER_PORT || 8080;

export async function makeMutationServer(databaseUrl: string): Promise<Server> {
  const client = new Client({ connectionString: databaseUrl });

  try {
    await client.connect();
  } catch (error) {
    console.error(`Error connecting to the database: ${error}`);
    process.exit(1);
  } finally {
    console.log(`Connected to the database`);
  }

  return makeMutationServerWithClient(client);
}

export function makeMutationServerWithClient(client: Client) {
  const writer = new Writer(client);

  const server = app.listen(port, async () => {
    console.log(`Server is listening on port ${port}`);
  });

  app.post(`/`, async (req: Request, res: Response, next: NextFunction) => {
    try {
      const postData = req.body;
      if (!Array.isArray(postData)) {
        throw new Error(`Expected an array of mutations`);
      }

      const mutations = bodyToMutation(postData);
      console.log(`Received mutations: ${JSON.stringify(mutations)}`);
      const xid = await writer.write(mutations);

      // This is not enough for idempotent requests
      // a client might disconnect without knowing that
      // the request was handled.
      res.header(`X-Electric-Postgres-Xid`, xid);

      return res.send();
    } catch (error) {
      console.log(`Error processing request: ${error}`);
      return next(error);
    }
  });

  app.get(`/`, (_req: Request, res: Response) => {
    res.send({ hello: `World!` });
  });

  app.use(
    (err: Error, _req: Request, res: Response, _next: NextFunction): void => {
      if (process.env.NODE_ENV === `development`) {
        console.error(err);
      }
      res.status(500).send({
        message: err.message,
        stack: process.env.NODE_ENV === `development` ? err.stack : undefined,
      });
    }
  );

  return server;
}
