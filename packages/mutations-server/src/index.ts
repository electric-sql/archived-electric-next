import { makeMutationServer } from "./server";

const databaseUrl =
  process.env.DATABASE_URL ||
  `postgresql://postgres:password@localhost:54321/electric`;

export default makeMutationServer(databaseUrl);
