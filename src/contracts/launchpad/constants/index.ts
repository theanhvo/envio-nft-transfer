export enum ELaunchPadMessageType {
  CollectionCreated = "CollectionCreated",
  TreasuryCreated = "TreasuryCreated",
  SplitterCreated = "SplitterCreated",
  NftPolicyUpdate = "NftPolicyUpdate",
  TreasuryPolicyUpdate = "TreasuryPolicyUpdate",
  SplitterPolicyUpdate = "SplitterPolicyUpdate",
  ApprovedCreatorUpdate = "ApprovedCreatorUpdate",
}

export const DEFAULT_ADDRESSES: { [key: string]: string } = {
  "0x0000000000000000000000000000000000000001": "THIS_LAUNCHPAD",
  "0x0000000000000000000000000000000000000002": "THIS_CONTRACT",
  "0x0000000000000000000000000000000000000003": "THIS_TREASURY",
  "0x0000000000000000000000000000000000000004": "THIS_PARENT",
  "0x0000000000000000000000000000000000000005": "FEE_SPLITTER",
}
