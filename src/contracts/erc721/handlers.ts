import dotenv from "dotenv"

dotenv.config()

import { ERC721 } from "generated"
import { transferHandler } from "./Transfer"

ERC721.Transfer.handler(
  ({ context, event }) => transferHandler({ context, event }),
  {
    wildcard: true,
  },
)
