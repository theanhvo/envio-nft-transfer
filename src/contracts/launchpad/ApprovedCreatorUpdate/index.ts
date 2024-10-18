import type {
  ApprovedCreatorUpdate,
  eventLog,
  handlerContext,
  Launchpad_0_0_2_ApprovedCreatorUpdate_eventArgs,
} from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import { EXCHANGE_LAUNCH_PAD, RABBITMQ_LAUNCH_PAD_KEY } from "../../../constants/queues"
import { ELaunchPadMessageType } from "../constants"

dotenv.config()

export async function approvedCreatorUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Launchpad_0_0_2_ApprovedCreatorUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { wallet_, status_ } = params

    const approvedCreatorUpdate: ApprovedCreatorUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),
      wallet_address: wallet_,
      status: status_,
    }

    const message = {
      type: ELaunchPadMessageType.ApprovedCreatorUpdate,
      data: approvedCreatorUpdate,
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_LAUNCH_PAD,
      routingKey: RABBITMQ_LAUNCH_PAD_KEY,
      message,
    })

    context.ApprovedCreatorUpdate.set(approvedCreatorUpdate)

    context.log.info(`ApprovedCreatorUpdate event processed: ${JSON.stringify(message)}`)
  } catch (error) {
    context.log.error(`Error processing ApprovedCreatorUpdate event: ${error}`)
    throw error
  }
}
