import { DEFAULT_ADDRESSES } from "../constants"

export function parsePolicy(config_: [string, string, string[], bigint[][], boolean]): {
  fee_ranges: [bigint, bigint][]
  fee_recipients: string[]
  master_copy: string
  merkle_root: string
  paused: boolean
} {
  const [master_copy, merkle_root, , fee_ranges, paused] = config_
  let [, , fee_recipients] = config_
  fee_recipients = fee_recipients.map((address) => DEFAULT_ADDRESSES[address] || address)
  return {
    fee_ranges: fee_ranges as [bigint, bigint][],
    fee_recipients,
    master_copy,
    merkle_root,
    paused,
  }
}
