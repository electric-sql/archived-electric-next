import { Message } from '../../../packages/typescript-client/src/types'
import { baseUrl } from './electric'

export const issueShape = {
  url: `${baseUrl}/v1/shape/issue`,
  getKey: (message: Message) => (message as any).value.id,
  // With tentative state client needs to be able to compute keys locally.
  // We might want to change the strategy on the server so that they can be generated
  // on both sides. Otherwise, this transformation works.
}
