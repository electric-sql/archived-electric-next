export type JsonSerializable =
  | string
  | number
  | boolean
  | null
  | JsonSerializable[]
  | { [key: string]: JsonSerializable }

interface Header {
  [key: string]: JsonSerializable
}

export type ControlMessage = {
  headers: Header
}

export type ChangeMessage<T> = {
  key: string
  value: T
  headers: Header & { action: 'insert' | 'update' | 'delete' }
  offset: number
}

// Define the type for a record
export type Message<T extends JsonSerializable = JsonSerializable> =
  | ControlMessage
  | ChangeMessage<T>
