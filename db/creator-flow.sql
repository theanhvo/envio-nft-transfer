DO $$
BEGIN
    -- ContractCreated
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'ContractCreated' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'ContractCreated';
    END IF;

    -- SupplyUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'SupplyUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'SupplyUpdate';
    END IF;

    -- PriceUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'PriceUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'PriceUpdate';
    END IF;

    -- RoyaltiesUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'RoyaltiesUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'RoyaltiesUpdate';
    END IF;

    -- OwnershipTransferred
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'OwnershipTransferred' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'OwnershipTransferred';
    END IF;

    -- Paused
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'Paused' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'Paused';
    END IF;

    -- Unpaused
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'Unpaused' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'Unpaused';
    END IF;

    -- ListMinted
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'ListMinted' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'ListMinted';
    END IF;

    -- MintListUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'MintListUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'MintListUpdate';
    END IF;

    -- MintListDeleted
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'MintListDeleted' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'MintListDeleted';
    END IF;

    -- TreasuryUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'TreasuryUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'TreasuryUpdate';
    END IF;

    -- FeeUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'FeeUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'FeeUpdate';
    END IF;

    -- ReferralFeeUpdate
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'ReferralFeeUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'ReferralFeeUpdate';
    END IF;

    -- Referral
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'Referral' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'Referral';
    END IF;

    -- CrateTransfer
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'CrateTransfer' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'CrateTransfer';
    END IF;

END $$;

CREATE TABLE IF NOT EXISTS "ContractCreated" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  name TEXT NOT NULL,
  symbol TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "SupplyUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  supply INT NOT NULL
);

CREATE TABLE IF NOT EXISTS "PriceUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  price TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "RoyaltiesUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  token_id INT NOT NULL,
  receiver TEXT NOT NULL,
  bps INT NOT NULL
);

CREATE TABLE IF NOT EXISTS "OwnershipTransferred" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  old_owner TEXT NOT NULL,
  new_owner TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "ListMinted" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  minter TEXT NOT NULL,
  list_id INT NOT NULL,
  amount INT NOT NULL
);

CREATE TABLE IF NOT EXISTS "MintListUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  list_id INT NOT NULL,
  list JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS "MintListDeleted" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  list_id INT NOT NULL
);

CREATE TABLE IF NOT EXISTS "TreasuryUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  min_allocation INT NOT NULL,
  max_allocation INT NOT NULL
);

CREATE TABLE IF NOT EXISTS "FeeUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  fee_recipients JSONB NOT NULL,
  fees JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS "ReferralFeeUpdate" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  referral_fee TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "Referral" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  referral TEXT NOT NULL,
  referred TEXT NOT NULL,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "Paused" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  account TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "Unpaused" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  account TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "CrateTransfer" (
  id TEXT PRIMARY KEY,
  chain TEXT NOT NULL,
  block_timestamp INT NOT NULL,
  block_number INT NOT NULL,
  transaction_hash TEXT NOT NULL,
  contract_address TEXT NOT NULL,
  from_address TEXT NOT NULL,
  to_address TEXT NOT NULL,
  caller_address TEXT NOT NULL,
  token_id NUMERIC NOT NULL,
  quantity NUMERIC NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
