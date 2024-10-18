import type {
  eventLog,
  handlerContext,
  MintListUpdate,
  Crate_MintListUpdate_eventArgs,
  ListMinted,
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

export async function mintListUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_MintListUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { listId_, list_ } = params

    const mintListUpdate: MintListUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      list_id: Number(listId_),
      list: list_.toString().split(","),
    }

    const message = {
      type: ECrateContractMessageType.MintListUpdate,
      data: mintListUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.MintListUpdate.set(mintListUpdate)

    context.log.info(`MintListUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing MintListUpdate event: ${error}`)
    throw error
  }
}
