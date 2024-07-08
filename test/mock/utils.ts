import { Message, Mutation } from '../../types'

type operation = { [key: string]: any } & { id: any }

const getKey = (id: any, table: string) => `${table}/${id}`

export const makeMessage = (
  action: 'insert' | 'update' | 'delete',
  table: string,
  value: operation
): Message => ({
  headers: { action },
  key: `${table}/${value.id}`,
  value,
})

export const makeMutation = (
  action: 'insert' | 'update' | 'delete',
  table: string,
  value: operation
): Mutation => ({
  action,
  key: getKey(value.id, table),
  value,
})
