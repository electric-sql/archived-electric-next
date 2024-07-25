import type { GlobalSetupContext } from "vitest/node";

const mutationsServerUrl =
  process.env.ELECTRIC_MUTATIONS_URL ?? `http://localhost:3100`;

// eslint-disable-next-line quotes -- eslint is acting dumb with enforce backtick quotes mode, and is trying to use it here where it's not allowed.
declare module "vitest" {
  export interface ProvidedContext {
    mutationsServerUrl: string;
    baseUrl: string;
  }
}

/**
 * Global setup for the test suite. Validates that our server is running, and creates and tears down a
 * special schema in Postgres to ensure clean slate between runs.
 */
export default async function ({ provide }: GlobalSetupContext) {
  const { server } = await import("../../src/index");

  provide(`mutationsServerUrl`, mutationsServerUrl);

  return () => {
    server.close();
  };
}
