import type { eventLog, handlerContext, Referral, Crate_Referral_eventArgs } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import {
  EXCHANGE_COLLECTION_CREATOR_FLOW,
  RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
} from "../../../constants/queues"
import { ECrateContractMessageType } from "../constants"

dotenv.config()

export async function referralHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_Referral_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { referral_, referred_, value_ } = params

    const referral: Referral = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      referral: referral_,
      referred: referred_,
      value: value_.toString(),
    }

    const message = {
      type: ECrateContractMessageType.Referral,
      data: referral,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.Referral.set(referral)

    context.log.info(`Referral event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing Referral event: ${error}`)
    throw error
  }
}
