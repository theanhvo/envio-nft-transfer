import type {
  eventLog,
  handlerContext,
  RoyaltiesUpdate,
  Crate_RoyaltiesUpdate_eventArgs,
} from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import {
  EXCHANGE_COLLECTION_CREATOR_FLOW,
  RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
} from "../../../constants/queues"
import { ECrateContractMessageType } from "../constants"

dotenv.config()

export async function royaltiesUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_RoyaltiesUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { tokenId_, receiver_, bps_ } = params

    const royaltiesUpdate: RoyaltiesUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      token_id: Number(tokenId_),
      receiver: receiver_,
      bps: Number(bps_),
    }

    const message = {
      type: ECrateContractMessageType.RoyaltiesUpdate,
      data: royaltiesUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.RoyaltiesUpdate.set(royaltiesUpdate)

    context.log.info(`RoyaltiesUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing SupplyUpdate event: ${error}`)
    throw error
  }
}
