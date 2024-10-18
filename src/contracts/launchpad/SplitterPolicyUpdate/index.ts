import type {
  eventLog,
  handlerContext,
  Launchpad_0_0_2_SplitterPolicyUpdate_eventArgs,
  SplitterPolicyUpdate,
} from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"
import { EXCHANGE_LAUNCH_PAD, RABBITMQ_LAUNCH_PAD_KEY } from "../../../constants/queues"
import { ELaunchPadMessageType } from "../constants"
import { parsePolicy } from "./utils"

dotenv.config()

export async function splitterPolicyUpdateHandler({
  context,
  event,
}: {
  context: handlerContext
  event: eventLog<Launchpad_0_0_2_SplitterPolicyUpdate_eventArgs>
}): Promise<void> {
  try {
    await rabbitMqService.connect()
    const { block, chainId, params, srcAddress, transaction } = event
    const { id_, config_ } = params

    const parsedPolicy = parsePolicy(config_)

    const splitterPolicyUpdate: SplitterPolicyUpdate = {
      id: `${chainId}_${transaction.hash}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
      contract_address: srcAddress,
      created_at: new Date(),
      updated_at: new Date(),
      splitter_policy_id: Number(id_),
      config: config_.toString().split(","),
    }

    const message = {
      type: ELaunchPadMessageType.SplitterPolicyUpdate,
      data: {
        ...splitterPolicyUpdate,
        ...parsedPolicy,
      },
    }

    rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_LAUNCH_PAD,
      routingKey: RABBITMQ_LAUNCH_PAD_KEY,
      message,
    })

    context.SplitterPolicyUpdate.set(splitterPolicyUpdate)

    context.log.info(
      `SplitterPolicyUpdate event processed: ${JSON.stringify(message, (_, value) =>
        typeof value === "bigint" ? value.toString() : value,
      )}`,
    )
  } catch (error) {
    context.log.error(`Error processing SplitterPolicyUpdate event: ${error}`)
    throw error
  }
}
