type JsonSerializable =
  | string
  | number
  | boolean
  | null
  | JsonSerializable[]
  | { [key: string]: JsonSerializable }

interface Header {
  [key: string]: JsonSerializable
}

// Define the type for a record
export type Message = {
  key?: string
  value?: unknown
  headers?: Header
  offset?: number
}


// Types for tentative shape
export type Mutation = {
  action: 'insert' | 'update' | 'delete'
  key: string
  value: any
}

export type MergeFunction = (
  current: Mutation,
  incoming: Mutation
) => Mutation

export type MatchFunction = (current?: Mutation, incoming?: Mutation) => boolean
