import { DEFAULT_ADDRESSES } from "../constants"

export function parsePolicy(config_: [string, string, string[], bigint[][], bigint[], boolean]): {
  fee_ranges: [bigint, bigint][]
  fee_recipients: string[]
  master_copy: string
  merkle_root: string
  paused: boolean
  royalty: [bigint, bigint]
} {
  const [masterCopy, merkleRoot, , feeRanges, royalty, paused] = config_
  let [, , feeRecipients] = config_
  feeRecipients = feeRecipients.map((address) => DEFAULT_ADDRESSES[address] || address)
  return {
    fee_ranges: feeRanges as [bigint, bigint][],
    fee_recipients: feeRecipients,
    master_copy: masterCopy,
    merkle_root: merkleRoot,
    paused,
    royalty: royalty as [bigint, bigint],
  }
}
