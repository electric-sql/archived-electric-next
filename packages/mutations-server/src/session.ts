import { Client } from "pg";
import { User, Session } from "./types";

export interface SessionStore {
  get(user: User): Promise<Session>;
  create(user: User): Promise<Session>;
  update(userSession: Session): Promise<void>;
  delete(user: User): Promise<void>;
  cleanup(): Promise<void>;
}

export class SessionStorePg implements SessionStore {
  private pg: Client;

  constructor(pg: Client) {
    this.pg = pg;
  }

  async init() {
    const query = {
      text: `CREATE TABLE IF NOT EXISTS user_sessions (
            user_id VARCHAR PRIMARY KEY,
            last_request VARCHAR,
            last_commit VARCHAR
            )`,
    };
    await this.pg.query(query);
  }

  async get(user: User): Promise<Session> {
    const query = {
      name: `get-user-session`,
      text: `SELECT user_id, last_request, last_commit FROM user_sessions WHERE user_id = $1`,
      values: [user.userId],
    };

    const res = await this.pg.query(query);
    if (res.rowCount === 0) {
      const userSession = this.create(user);
      return userSession;
    } else {
      const { user_id, last_request, last_commit } = res.rows[0];
      return {
        userId: user_id,
        lastRequest: last_request,
        lastCommit: last_commit,
      };
    }
  }

  async create(user: User): Promise<Session> {
    const userSessions = {
      userId: user.userId,
      lastRequest: ``,
      lastCommit: ``,
    };

    const query = {
      name: `create-user-session`,
      text: `INSERT INTO user_sessions (user_id, last_request, last_commit) VALUES ($1, $2, $3)`,
      values: [
        userSessions.userId,
        userSessions.lastRequest,
        userSessions.lastCommit,
      ],
    };

    await this.pg.query(query);
    return userSessions;
  }

  async update(userSession: Session): Promise<void> {
    const query = {
      name: `update-user-session`,
      text: `UPDATE user_sessions SET last_request = $2, last_commit = $3 WHERE user_id = $1`,
      values: [
        userSession.userId,
        userSession.lastRequest,
        userSession.lastCommit,
      ],
    };

    await this.pg.query(query);
  }

  async delete(user: User): Promise<void> {
    const query = {
      name: `delete-user-session`,
      text: `DELETE FROM user_sessions WHERE user_id = $1`,
      values: [user.userId],
    };

    await this.pg.query(query);
  }

  async cleanup(): Promise<void> {
    const query = {
      text: `DROP TABLE IF EXISTS user_sessions`,
    };

    await this.pg.query(query);
  }
}
