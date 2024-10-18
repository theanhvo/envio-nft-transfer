import type {
  eventLog,
  handlerContext,
  Launchpad_0_0_2_NftPolicyUpdate_eventArgs,
  NftPolicyUpdate,
} from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import { EXCHANGE_LAUNCH_PAD, RABBITMQ_LAUNCH_PAD_KEY } from "../../../constants/queues"
import { ELaunchPadMessageType } from "../constants"
import { parsePolicy } from "./utils"

dotenv.config()

export async function nftPolicyUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Launchpad_0_0_2_NftPolicyUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { id_, config_ } = params

    const parsedPolicy = parsePolicy(config_)

    const nftPolicyUpdate: NftPolicyUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      nft_policy_id: Number(id_),
      config: config_.toString().split(","),
      created_at: new Date(),
      updated_at: new Date(),
    }

    const message = {
      type: ELaunchPadMessageType.NftPolicyUpdate,
      data: {
        ...nftPolicyUpdate,
        ...parsedPolicy,
      },
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_LAUNCH_PAD,
      routingKey: RABBITMQ_LAUNCH_PAD_KEY,
      message,
    })

    context.NftPolicyUpdate.set(nftPolicyUpdate)

    context.log.info(
      `NftPolicyUpdate event processed: ${JSON.stringify(message, (key, value) =>
        typeof value === "bigint" ? value.toString() : value,
      )}`,
    )
  } catch (error) {
    context.log.error(`Error processing NftPolicyUpdate event: ${error}`)
    throw error
  }
}
