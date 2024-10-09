type Version = `${number}.${number}.${number}`
type ChainVersion = {
  [timeStamp: number]: Version
}

type Versions = {
  [chainId: number]: ChainVersion
}

export const SEAPORT_VERSION = {
  80084: {
    741310: "1.6.0",
  },
} as const satisfies Versions

export const NFT_VERSION = {
  80084: {
    0: "0.0.1",
    3075715: "0.0.2",
  },
} as const satisfies Versions

function findLargestLessOrEqualKey<L>(obj: { [key: number]: L }, key: number): number {
  const keyStrings: (string | number)[] = Object.keys(obj)
  if (keyStrings.length === 0) {
    return 0
  }

  const keys = keyStrings.map(Number).sort((a, b) => a - b)

  let left = 0
  let right = keys.length - 1
  let result: number | undefined

  const last = keys[right]
  if (key >= last) return last

  while (left <= right) {
    const mid = Math.floor((left + right) / 2)

    if (keys[mid] <= key) {
      result = keys[mid]
      left = mid + 1
    } else {
      right = mid - 1
    }
  }

  return result as number
}

export const findNftVersion = ({
  blockNumber,
  chainId,
}: {
  blockNumber: number
  chainId: number
}): Version => {
  const chainVersion = NFT_VERSION[chainId as keyof typeof NFT_VERSION] as ChainVersion | undefined
  if (!chainVersion) {
    throw new Error(`Chain ID ${chainId} not found`)
  }
  const versionKey = findLargestLessOrEqualKey(chainVersion, blockNumber)
  return chainVersion[versionKey]
}
