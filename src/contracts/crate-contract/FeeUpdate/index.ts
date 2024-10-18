import type { eventLog, handlerContext, Crate_FeeUpdate_eventArgs, FeeUpdate } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import {
  EXCHANGE_COLLECTION_CREATOR_FLOW,
  RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
} from "../../../constants/queues"
import { ECrateContractMessageType } from "../constants"

dotenv.config()

export async function feeUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_FeeUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { feeRecipients_, fees_ } = params

    const feeUpdate: FeeUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      fee_recipients: feeRecipients_,
      fees: fees_.map((fee) => Number(fee)),
    }

    const message = {
      type: ECrateContractMessageType.FeeUpdate,
      data: feeUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.FeeUpdate.set(feeUpdate)

    context.log.info(`FeeUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing FeeUpdate event: ${error}`)
    throw error
  }
}
