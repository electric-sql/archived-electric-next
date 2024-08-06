import { Client } from "pg";
import { createServer as s } from "./server";

const databaseUrl =
  process.env.DATABASE_URL ||
  `postgresql://postgres:password@localhost:54321/electric`;

async function createServer(databaseUrl: string) {
  const pg = new Client({ connectionString: databaseUrl });

  try {
    await pg.connect();
  } catch (error) {
    console.error(`Error connecting to the database: ${error}`);
    process.exit(1);
  } finally {
    console.log(`Connected to the database`);
  }

  return s(pg);
}

export default createServer(databaseUrl);
