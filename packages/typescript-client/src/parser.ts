import { ColumnInfo, Value } from './types'

export type ParseFunction = (
  value: string,
  additionalInfo?: Omit<ColumnInfo, `type` | `dims`>
) => Value
export type Parser = { [key: string]: ParseFunction }

const parseNumber = (value: string) => Number(value)
const parseBool = (value: string) => value === `true` || value === `t`
const parseBigInt = (value: string) => BigInt(value)
const parseJson = (value: string) => JSON.parse(value)

export const defaultParser: Parser = {
  int2: parseNumber,
  int4: parseNumber,
  int8: parseBigInt,
  bool: parseBool,
  float8: parseNumber,
  json: parseJson,
  jsonb: parseJson,
}

// Taken from: https://github.com/electric-sql/pglite/blob/main/packages/pglite/src/types.ts#L233-L279
export function pgArrayParser(
  value: string,
  parser?: (s: string) => Value
): Value {
  let i = 0
  let char = null
  let str = ``
  let quoted = false
  let last = 0
  let p: string | undefined = undefined

  function loop(x: string): Value[] {
    const xs = []
    for (; i < x.length; i++) {
      char = x[i]
      if (quoted) {
        if (char === `\\`) {
          str += x[++i]
        } else if (char === `"`) {
          xs.push(parser ? parser(str) : str)
          str = ``
          quoted = x[i + 1] === `"`
          last = i + 2
        } else {
          str += char
        }
      } else if (char === `"`) {
        quoted = true
      } else if (char === `{`) {
        last = ++i
        xs.push(loop(x))
      } else if (char === `}`) {
        quoted = false
        last < i &&
          xs.push(parser ? parser(x.slice(last, i)) : x.slice(last, i))
        last = i + 1
        break
      } else if (char === `,` && p !== `}` && p !== `"`) {
        xs.push(parser ? parser(x.slice(last, i)) : x.slice(last, i))
        last = i + 1
      }
      p = char
    }
    last < i &&
      xs.push(parser ? parser(x.slice(last, i + 1)) : x.slice(last, i + 1))
    return xs
  }

  return loop(value)[0]
}
