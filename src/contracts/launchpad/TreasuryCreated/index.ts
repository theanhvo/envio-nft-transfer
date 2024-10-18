import type {
  eventLog,
  handlerContext,
  Launchpad_0_0_2_TreasuryCreated_eventArgs,
  TreasuryCreated,
} from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import { EXCHANGE_LAUNCH_PAD, RABBITMQ_LAUNCH_PAD_KEY } from "../../../constants/queues"
import { ELaunchPadMessageType } from "../constants"

dotenv.config()

export async function treasuryCreatedHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Launchpad_0_0_2_TreasuryCreated_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { creator_, collection_, treasury_, policyId_ } = params

    const treasuryCreated: TreasuryCreated = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      creator_address: creator_,
      collection_address: collection_,
      treasury_address: treasury_,
      policy_id: Number(policyId_),
      created_at: new Date(),
      updated_at: new Date(),
    }

    const message = {
      type: ELaunchPadMessageType.TreasuryCreated,
      data: treasuryCreated,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_LAUNCH_PAD,
      routingKey: RABBITMQ_LAUNCH_PAD_KEY,
      message,
    })

    context.TreasuryCreated.set(treasuryCreated)

    context.log.info(`TreasuryCreated event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing TreasuryCreated event: ${error}`)
    throw error
  }
}
