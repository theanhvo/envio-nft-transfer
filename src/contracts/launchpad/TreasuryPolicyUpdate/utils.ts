import { DEFAULT_ADDRESSES } from "../constants"

export function parsePolicy(
  config_: [string, string, string[], bigint[][], bigint[], bigint[], bigint[], boolean],
): {
  fee_ranges: [bigint, bigint][]
  fee_recipients: string[]
  interest_rate: [bigint, bigint]
  master_copy: string
  merkle_root: string
  paused: boolean
  royalty: [bigint, bigint]
  term_limit: [bigint, bigint]
} {
  const [master_copy, merkle_root, , fee_ranges, royalty, interest_rate, term_limit, paused] =
    config_
  let [, , fee_recipients] = config_
  fee_recipients = fee_recipients.map((address) => DEFAULT_ADDRESSES[address] || address)
  return {
    fee_ranges: fee_ranges as [bigint, bigint][],
    fee_recipients,
    master_copy,
    merkle_root,
    royalty: royalty as [bigint, bigint],
    interest_rate: interest_rate as [bigint, bigint],
    term_limit: term_limit as [bigint, bigint],
    paused,
  }
}
