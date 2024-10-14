import type { eventLog, handlerContext, ERC721_Transfer_eventArgs, NftTransfers } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"
import { RabbitMqService } from "../../../utils/rabbitMQ"
import {
  EXCHANGE_NFT_BALANCES,
  RABBITMQ_NFT_BALANCES_KEY,
  EXCHANGE_NFT_METADATA,
  RABBITMQ_NFT_METADATA_KEY,
} from "../../../constants/queues"

import dotenv from "dotenv"
import { rabbitMqService } from "../../../connection"

dotenv.config()

export async function transferHandler({
  context,
  event,
  // rabbitMqService,
}: {
  context: handlerContext
  event: eventLog<ERC721_Transfer_eventArgs>
  // rabbitMqService: RabbitMqService
}): Promise<void> {
  try {
    const { block, chainId, params, srcAddress, transaction } = event
    const { from, to, tokenId } = params

    await rabbitMqService.connect()
    const transfer: NftTransfers = {
      id: `${chainId}_${srcAddress}_${tokenId.toString()}_${block.number}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      contract_address: srcAddress,
      from_address: from,
      to_address: to,
      caller_address: transaction.from ?? from,
      token_id: tokenId,
      quantity: BigInt(1),
      created_at: new Date(block.timestamp * 1000),
      updated_at: new Date(block.timestamp * 1000),
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
    }

    // Send to RabbitMQ to handle get metadata of nft
    if (from === "0x0000000000000000000000000000000000000000") {
      await rabbitMqService.sendMessageToExchange({
        exchange: EXCHANGE_NFT_METADATA,
        routingKey: RABBITMQ_NFT_METADATA_KEY,
        message: transfer,
      })
    }

    // Send to RabbitMQ to handle update balance of user
    await rabbitMqService.sendMessageToExchange({
      exchange: EXCHANGE_NFT_BALANCES,
      routingKey: RABBITMQ_NFT_BALANCES_KEY,
      message: transfer,
    })

    // await rabbitMqService.closeConnection()

    await context.NftTransfers.set(transfer)

    context.log.info(`NftTransfers event processed: ${srcAddress}`)
  } catch (error) {
    context.log.error(`Error processing NftTransfers event: ${error}`)
    throw error
  }
}
