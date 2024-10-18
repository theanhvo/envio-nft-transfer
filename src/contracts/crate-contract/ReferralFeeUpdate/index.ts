import type {
  eventLog,
  handlerContext,
  ReferralFeeUpdate,
  Crate_ReferralFeeUpdate_eventArgs,
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

export async function referralFeeUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Crate_ReferralFeeUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { referralFee_ } = params

    const referralFeeUpdate: ReferralFeeUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),

      referral_fee: referralFee_.toString(),
    }

    const message = {
      type: ECrateContractMessageType.ReferralFeeUpdate,
      data: referralFeeUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_COLLECTION_CREATOR_FLOW,
      routingKey: RABBITMQ_COLLECTION_CREATOR_FLOW_KEY,
      message,
    })

    context.ReferralFeeUpdate.set(referralFeeUpdate)

    context.log.info(`ReferralFeeUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing ReferralFeeUpdate event: ${error}`)
    throw error
  }
}
