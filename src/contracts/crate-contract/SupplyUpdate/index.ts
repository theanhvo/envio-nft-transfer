import type {
  eventLog,
  handlerContext,
  SupplyUpdate,
  Crate_SupplyUpdate_eventArgs,
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

export async function supplyUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_SupplyUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { supply_ } = params

    const supplyUpdate: SupplyUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),
      supply: Number(supply_),
    }

    const message = {
      type: ECrateContractMessageType.SupplyUpdate,
      data: supplyUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.SupplyUpdate.set(supplyUpdate)

    context.log.info(`SupplyUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing SupplyUpdate event: ${error}`)
    throw error
  }
}
