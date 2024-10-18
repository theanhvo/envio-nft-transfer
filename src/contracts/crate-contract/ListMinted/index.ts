import type { eventLog, handlerContext, ListMinted, Crate_ListMinted_eventArgs } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import {
  EXCHANGE_COLLECTION_CREATOR_FLOW,
  RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
} from "../../../constants/queues"
import { ECrateContractMessageType } from "../constants"

dotenv.config()

export async function listMintedHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_ListMinted_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { minter_, listId_, amount_ } = params

    const listMinted: ListMinted = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),
      minter: minter_,
      list_id: Number(listId_),
      amount: Number(amount_),
    }

    const message = {
      type: ECrateContractMessageType.ListMinted,
      data: listMinted,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.ListMinted.set(listMinted)

    context.log.info(`ListMinted event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing ListMinted event: ${error}`)
    throw error
  }
}
