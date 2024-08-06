import { Client } from "pg";
import { MutationWriter } from "./writer";
import { SessionStorePg } from "./session";

import {
  Mutation,
  MutationIdentifier,
  RequestStatus,
  User,
  Session,
} from "./types";

export class ElectricMutations {
  private writer: MutationWriter;
  private sessions: SessionStorePg;

  constructor(pg: Client) {
    this.writer = new MutationWriter(pg);
    this.sessions = new SessionStorePg(pg);
  }

  async init() {
    await this.sessions.init();
  }

  async handleRequest(
    requestId: string,
    user: User,
    mutations: Mutation[],
  ): Promise<{ status: RequestStatus; session: Session }> {
    const session = await this.sessions.get(user);

    const res = this.validateRequest(requestId, session);
    switch (res) {
      case RequestStatus.OK: {
        const res = await this.applyMutations(mutations);
        const newSession = {
          ...session,
          lastRequest: requestId,
          lastCommit: res.xid,
        };
        this.sessions.update(newSession);
        return { status: RequestStatus.OK, session: newSession };
      }
      case RequestStatus.IDEMPOTENT:
        console.log(session);
        return { status: RequestStatus.IDEMPOTENT, session };
      case RequestStatus.OLD:
        return { status: RequestStatus.OLD, session };
    }
  }

  validateRequest(requestId: string, session: Session): RequestStatus {
    console.log(`validateRequest`, requestId, session);
    if (requestId < session.lastRequest) {
      return RequestStatus.OLD;
    }
    if (requestId == session.lastRequest) {
      // TODO: validate requests hasn't changed
      return RequestStatus.IDEMPOTENT;
    }
    return RequestStatus.OK;
  }

  async applyMutations(mutations: Mutation[]): Promise<MutationIdentifier> {
    const xid = await this.writer.write(mutations);
    return { xid };
  }
}
