import express, { Request, Response, NextFunction } from "express";
import bodyParser from "body-parser";
import "dotenv/config";
import { Client } from "pg";
import { Server } from "http";
import { ElectricMutations } from "./mutations";

const app = express();
app.use(bodyParser.json());

const port = process.env.MUTATIONS_SERVER_PORT || 8080;

export function createServer(pg: Client): Server {
  const electric = new ElectricMutations(pg);

  const server = app.listen(port, async () => {
    await electric.init();
    console.log(`Server is listening on port ${port}`);
  });

  app.post(`/`, async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userId = req.header(`X-Electric-User-Id`);
      if (!userId) {
        const reason = `X-Electric-User-Id header is missing`;
        return res.status(400).send(reason);
      }

      const requestId = req.header(`X-Electric-Request-Id`);
      if (!requestId) {
        const reason = `X-Electric-Request-Id header is missing`;
        return res.status(400).send(reason);
      }

      // need to validate request
      const mutations = req.body;
      if (!Array.isArray(mutations)) {
        return res.status(400).send(`mutations should not be empty`);
      }

      if (mutations.length === 0) {
        return res.status(400).send(`mutations should not be empty`);
      }

      const user = { userId };
      const { status, session } = await electric.handleRequest(
        requestId,
        user,
        mutations,
      );

      if (status === `OLD`) {
        return res
          .status(409)
          .send(
            `Client has already submitted a request with an higher requestId than ${requestId}`,
          );
      }

      // A client will only miss the response if the server
      // rotates the shape or performs a compaction
      // before the client observing xid.

      // When a shape rotation occurs, any accepted
      // operations will be in the initial snapshot
      // for the new shapeId, therefore it is safe
      // to drop pending mutations.
      res.header(`X-Electric-Postgres-Xid`, session.lastCommit);

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
    },
  );

  return server;
}
