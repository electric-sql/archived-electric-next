import { Client } from "pg";
import { Mutation } from "./types";
import { getValuesInColumnOrder } from "./utils";
import { JsonSerializable } from "../../typescript-client/src/types";

// Library that writes applies mutations sent by the client
// A mutations is just a INSERT, UPDATE, DELETE statement for a single row

// One idea is to extend it to apply a conflict resolution strategy.
// Interestingly, we can know if conflict resolution was applied for a row
// and inform the client immediately.

export class MutationWriter {
  pg: Client;

  constructor(pg: Client) {
    this.pg = pg;
  }

  async validateMutationTableSchema(mutation: Mutation): Promise<boolean> {
    // This code can probably be done better. A table name that has spaces
    // is passed around with quotes, but for this WHERE clause we need to remove them
    const tablename = mutation.tablename.replace(/['"]+/g, ``);
    const columnNamesQuery = {
      name: `get-column-names`,
      text: `SELECT column_name
             FROM information_schema.columns
             WHERE table_schema = $1::text AND table_name = $2::text`,
      values: [mutation.schema, tablename],
    };

    const { rows } = await this.pg.query(columnNamesQuery);

    // check that every sent column exists in the table
    return Object.keys(mutation.row).every((key) =>
      rows.some(({ column_name }) => column_name === key)
    );
  }

  async write(mutations: Mutation[]): Promise<string> {
    const mutationsPerTable: Record<string, Mutation[]> = mutations.reduce(
      (acc: Record<string, Mutation[]>, mutation: Mutation) => {
        const key = `${mutation.schema}_${mutation.tablename}`;
        acc[key] = acc[key] || [];
        acc[key].push(mutation);
        return acc;
      },
      {},
    );

    try {
      await this.pg.query(`BEGIN`);

      for (const [_, mutations] of Object.entries(mutationsPerTable)) {
        const firstMutation = mutations[0];

        const isValid = await this.validateMutationTableSchema(firstMutation);
        if (!isValid) {
          throw new Error(`Invalid mutation: ${JSON.stringify(firstMutation)}`);
        }

        const columnNames = Object.keys(firstMutation.row);
        await this.writeRows(
          firstMutation.schema,
          firstMutation.tablename,
          columnNames,
          mutations.map((mutation) =>
            getValuesInColumnOrder(columnNames, mutation.row),
          ),
        );
      }

      const res = await this.pg.query(`SELECT txid_current()::TEXT as xid`);

      await this.pg.query(`COMMIT`);

      return res.rows[0].xid;
    } catch (error) {
      await this.pg.query(`ROLLBACK`);
      throw error;
    }
  }

  async writeRows(
    _schema: string,
    tablename: string,
    columnNames: string[],
    rows: JsonSerializable[][],
  ): Promise<void> {
    const { values } = rows.reduce(
      ({ count, values }, row: JsonSerializable[]) => {
        values.push(`(${row.map((_, i) => `$${count + i + 1}`).join(`, `)})`);
        return { count: count + columnNames.length, values };
      },
      { count: 0, values: [] as string[] },
    );

    const insertQuery = {
      text: `INSERT INTO ${tablename} (${columnNames.join(`, `)})
             VALUES ${values.join(`, `)}`,
      values: rows.flat(),
    };

    await this.pg.query(insertQuery);
  }
}
