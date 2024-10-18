export const EXCHANGE_NFT_BALANCES = process.env["EXCHANGE_NFT_BALANCES"] || "nft_balances"
export const RABBITMQ_NFT_BALANCES_KEY =
  process.env["RABBITMQ_NFT_BALANCES_KEY"] || "nft_balances.balances"
export const QUEUE_NFT_BALANCES = process.env["QUEUE_NFT_BALANCES"] || "queue_nft_balances"

export const EXCHANGE_NFT_METADATA = process.env["EXCHANGE_NFT_METADATA"] || "nft_metadata"
export const RABBITMQ_NFT_METADATA_KEY =
  process.env["RABBITMQ_NFT_METADATA_KEY"] || "nft_metadata.metadata"
export const QUEUE_NFT_METADATA = process.env["QUEUE_NFT_METADATA"] || "queue_nft_metadata"

export const EXCHANGE_LAUNCH_PAD = process.env["EXCHANGE_LAUNCH_PAD"] || "launch_pad"
export const RABBITMQ_LAUNCH_PAD_KEY =
  process.env["RABBITMQ_LAUNCH_PAD_KEY"] || "launch_pad.collection"
export const QUEUE_LAUNCH_PAD = process.env["QUEUE_LAUNCH_PAD"] || "queue_launch_pad"

export const EXCHANGE_COLLECTION_CREATOR_FLOW =
  process.env["EXCHANGE_COLLECTION_CREATOR_FLOW"] || "collection_creator_flow"
export const RABBITMQ_COLLECTION_CREATOR_FLOW_KEY =
  process.env["RABBITMQ_COLLECTION_CREATOR_FLOW_KEY"] || "collection_creator_flow.metadata"
export const QUEUE_COLLECTION_CREATOR_FLOW =
  process.env["QUEUE_COLLECTION_CREATOR_FLOW"] || "queue_collection_creator_flow"
