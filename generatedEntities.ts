/* 
* SPDX-License-Identifier: LicenseRef-AllRightsReserved
*
* License-Url: https://github.com/beramarket/torchbearer/LICENSES/LicenseRef-AllRightsReserved.txt
*
* SPDX-FileType: SOURCE
*
* SPDX-FileCopyrightText: 2024 Johannes Krauser III <detroitmetalcrypto@gmail.com>
*
* SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com>

* This file is generated by generateSchemaTypes.ts. Do not modify it manually.
*/
import { Decimal } from 'decimal.js';

/* eslint-disable typescript-sort-keys/interface */
type NftTransfers = {
  id: string
  chain: string
  block_timestamp: number
  block_number: number
  transaction_hash: string
  contract_address: string
  from_address: string
  to_address: string
  caller_address: string
  token_id: string
  quantity: bigint
  created_at_id: string
  updated_at_id: string
}

export const INITIAL_NFT_TRANSFERS: NftTransfers = {
  id: "",
  chain: "",
  block_timestamp: 0,
  block_number: 0,
  transaction_hash: "",
  contract_address: "",
  from_address: "",
  to_address: "",
  caller_address: "",
  token_id: "",
  quantity: 0n,
  created_at_id: "",
  updated_at_id: "",
} satisfies NftTransfers
