import dotenv from "dotenv"

dotenv.config()

import { Crate } from "generated"
import { contractCreatedHandler } from "./ContractCreated"
import { supplyUpdateHandler } from "./SupplyUpdate"
import { priceUpdateHandler } from "./PriceUpdate"
import { royaltiesUpdateHandler } from "./RoyaltiesUpdate"
import { ownershipTransferredHandler } from "./OwnershipTransferred"
import { listMintedHandler } from "./ListMinted"
import { mintListUpdateHandler } from "./MintListUpdate"
import { mintListDeletedHandler } from "./MintListDeleted"
import { treasuryUpdateHandler } from "./TreasuryUpdate"
import { feeUpdateHandler } from "./FeeUpdate"
import { referralFeeUpdateHandler } from "./ReferralFeeUpdate"
import { referralHandler } from "./Referral"
import { pausedHandler } from "./Paused"
import { unpausedHandler } from "./UnPaused"
import { crateTransferHandler } from "./CrateTransfer"

Crate.ContractCreated.handler(({ context, event }) => contractCreatedHandler({ context, event }))

Crate.SupplyUpdate.handler(({ context, event }) => supplyUpdateHandler({ context, event }))

Crate.PriceUpdate.handler(({ context, event }) => priceUpdateHandler({ context, event }))

Crate.RoyaltiesUpdate.handler(({ context, event }) => royaltiesUpdateHandler({ context, event }))

Crate.OwnershipTransferred.handler(({ context, event }) =>
  ownershipTransferredHandler({ context, event }),
)

Crate.ListMinted.handler(({ context, event }) => listMintedHandler({ context, event }))

Crate.MintListUpdate.handler(({ context, event }) => mintListUpdateHandler({ context, event }))

Crate.MintListDeleted.handler(({ context, event }) => mintListDeletedHandler({ context, event }))

Crate.TreasuryUpdate.handler(({ context, event }) => treasuryUpdateHandler({ context, event }))

Crate.FeeUpdate.handler(({ context, event }) => feeUpdateHandler({ context, event }))

Crate.ReferralFeeUpdate.handler(({ context, event }) =>
  referralFeeUpdateHandler({ context, event }),
)

Crate.Referral.handler(({ context, event }) => referralHandler({ context, event }))

Crate.Paused.handler(({ context, event }) => pausedHandler({ context, event }))

Crate.Unpaused.handler(({ context, event }) => unpausedHandler({ context, event }))

// Crate.Transfer.handler(({ context, event }) => crateTransferHandler({ context, event }))
