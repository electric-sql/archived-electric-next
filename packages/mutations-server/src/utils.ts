import { JsonSerializable } from "../../typescript-client/src/types";
import { Mutation } from "./types";

export function bodyToMutation(json: any): Mutation[] {
  const mutations: Mutation[] = [];

  for (const data of json) {
    const mutation: Mutation = {
      action: data.action,
      schema: data.schema,
      tablename: data.tablename,
      row: data.row,
    };
    mutations.push(mutation);
  }

  return mutations;
}

export function getValuesInColumnOrder(
  columnNames: string[],
  row: Record<string, JsonSerializable>
) {
  return columnNames.map((columnName) => row[columnName]);
}
