import type { eventLog, handlerContext, ERC721_Transfer_eventArgs, NftTransfers } from "generated"
import { CHAIN_ID_TO_CHAIN_NAME } from "../../../constants/common"

import dotenv from "dotenv"

dotenv.config()

export async function transferHandler({
  context,
  event
}: {
  context: handlerContext
  event: eventLog<ERC721_Transfer_eventArgs>
}): Promise<void> {
  try {
    const { block, chainId, params, srcAddress, transaction } = event
    const { from, to, tokenId } = params
    const data = {
      id: `${chainId}_${srcAddress}_${tokenId.toString()}_${block.number}`,
      chain: CHAIN_ID_TO_CHAIN_NAME[chainId as keyof typeof CHAIN_ID_TO_CHAIN_NAME],
      contract_address: srcAddress,
      from_address: from,
      to_address: to,
      caller_address: transaction.from ?? from,
      token_id: tokenId.toString(),
      quantity: BigInt(1),
      created_at: new Date(block.timestamp * 1000),
      updated_at: new Date(block.timestamp * 1000),
      block_number: block.number,
      block_timestamp: block.timestamp,
      transaction_hash: transaction.hash,
    }
    context.log.info(`NftTransfers process data: ${data}`);

    const transfer: NftTransfers = data

    await context.NftTransfers.set(transfer);
    // Send to RabbitMQ to handle get metadata of nft
    context.log.info(`NftTransfers event processed: ${srcAddress}`);


  } catch (error) {
    context.log.error(`Error processing NftTransfers event: ${error}`)
    throw error
  }
}
