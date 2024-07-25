// Fix mismatch between type definitions
export type Mutation = {
  action: `insert` | `update` | `delete`;
  schema: string;
  tablename: string;
  row: Record<string, string>;
};
