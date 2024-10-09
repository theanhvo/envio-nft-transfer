export const EXCHANGE_NFT_BALANCES = process.env["EXCHANGE_NFT_BALANCES"] || "nft_balances"
export const RABBITMQ_NFT_BALANCES_KEY =
  process.env["RABBITMQ_NFT_BALANCES_KEY"] || "nft_balances.balances"
export const QUEUE_NFT_BALANCES = process.env["QUEUE_NFT_BALANCES"] || "queue_nft_balances"

export const EXCHANGE_NFT_METADATA = process.env['EXCHANGE_NFT_METADATA'] || 'nft_metadata';
export const RABBITMQ_NFT_METADATA_KEY = process.env['RABBITMQ_NFT_METADATA_KEY'] || 'nft_metadata.metadata';
export const QUEUE_NFT_METADATA = process.env['QUEUE_NFT_METADATA'] || 'queue_nft_metadata';