import type {
  eventLog,
  handlerContext,
  Crate_TreasuryUpdate_eventArgs,
  TreasuryUpdate,
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

export async function treasuryUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_TreasuryUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { minAllocation, maxAllocation } = params

    const treasuryUpdate: TreasuryUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      min_allocation: Number(minAllocation),
      max_allocation: Number(maxAllocation),
    }

    const message = {
      type: ECrateContractMessageType.TreasuryUpdate,
      data: treasuryUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.TreasuryUpdate.set(treasuryUpdate)

    context.log.info(`TreasuryUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing TreasuryUpdate event: ${error}`)
    throw error
  }
}
