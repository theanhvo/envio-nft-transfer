import type { eventLog, handlerContext, Unpaused, Crate_Unpaused_eventArgs } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import {
  EXCHANGE_COLLECTION_CREATOR_FLOW,
  RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
} from "../../../constants/queues"
import { ECrateContractMessageType } from "../constants"

dotenv.config()

export async function unpausedHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_Unpaused_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { account } = params

    const unpaused: Unpaused = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      account,
    }

    const message = {
      type: ECrateContractMessageType.Unpaused,
      data: unpaused,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.Unpaused.set(unpaused)

    context.log.info(`Unpaused event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing Unpaused event: ${error}`)
    throw error
  }
}
