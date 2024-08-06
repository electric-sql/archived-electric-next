import { JsonSerializable } from "../../typescript-client/src/types";

// Fix mismatch between type definitions
export type Mutation = {
  action: `insert` | `update` | `delete`;
  schema: string;
  tablename: string;
  row: Record<string, JsonSerializable>;
};

export type MutationIdentifier = {
  xid: string;
};

export type User = {
  userId: string;
};

export type Session = User & {
  lastRequest: string;
  lastCommit: string;
};

export enum RequestStatus {
  OK = `OK`,
  IDEMPOTENT = `IDEMPOTENT`,
  OLD = `OLD`,
}
