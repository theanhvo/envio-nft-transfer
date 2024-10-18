import dotenv from "dotenv"

dotenv.config()

import { Launchpad_0_0_2 } from "generated"
import { collectionCreatedHandler } from "./CollectionCreated"
import { treasuryCreatedHandler } from "./TreasuryCreated"
import { splitterCreatedHandler } from "./SplitterCreated"
import { nftPolicyUpdateHandler } from "./NftPolicyUpdate"
import { treasuryPolicyUpdateHandler } from "./TreasuryPolicyUpdate"
import { splitterPolicyUpdateHandler } from "./SplitterPolicyUpdate"
import { approvedCreatorUpdateHandler } from "./ApprovedCreatorUpdate"

Launchpad_0_0_2.CollectionCreated.handler(({ context, event }) =>
  collectionCreatedHandler({ context, event }),
)

Launchpad_0_0_2.CollectionCreated.contractRegister(({ context, event }) => {
  const { collection_ } = event.params
  context.addCrate(collection_)
})

Launchpad_0_0_2.TreasuryCreated.handler(({ context, event }) =>
  treasuryCreatedHandler({ context, event }),
)

Launchpad_0_0_2.SplitterCreated.handler(({ context, event }) =>
  splitterCreatedHandler({ context, event }),
)

Launchpad_0_0_2.NftPolicyUpdate.handler(({ context, event }) =>
  nftPolicyUpdateHandler({ context, event }),
)

Launchpad_0_0_2.TreasuryPolicyUpdate.handler(({ context, event }) =>
  treasuryPolicyUpdateHandler({ context, event }),
)

Launchpad_0_0_2.SplitterPolicyUpdate.handler(({ context, event }) =>
  splitterPolicyUpdateHandler({ context, event }),
)

Launchpad_0_0_2.ApprovedCreatorUpdate.handler(({ context, event }) =>
  approvedCreatorUpdateHandler({ context, event }),
)
