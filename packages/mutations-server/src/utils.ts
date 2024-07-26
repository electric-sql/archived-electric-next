import { JsonSerializable } from "../../typescript-client/src/types";
import { Mutation } from "./types";

export function getValuesInColumnOrder(
  columnNames: string[],
  row: Record<string, JsonSerializable>,
) {
  return columnNames.map((columnName) => row[columnName]);
}

export function buildRequest(
  url: string,
  userId: string,
  requestId: string,
  mutations: Mutation[],
) {
  return new Request(url, {
    method: `POST`,
    headers: {
      "Content-Type": `application/json`,
      "X-Electric-Request-Id": requestId,
      "X-Electric-User-Id": userId,
    },
    body: JSON.stringify(mutations),
  });
}
