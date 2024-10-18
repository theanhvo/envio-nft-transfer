DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'CollectionCreated' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'CollectionCreated';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'TreasuryCreated' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'TreasuryCreated';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'SplitterCreated' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'SplitterCreated';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'NftPolicyUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'NftPolicyUpdate';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'TreasuryPolicyUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'TreasuryPolicyUpdate';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'SplitterPolicyUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'SplitterPolicyUpdate';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum 
        WHERE enumlabel = 'ApprovedCreatorUpdate' 
          AND enumtypid = 'entity_type'::regtype
    ) THEN
        ALTER TYPE entity_type ADD VALUE 'ApprovedCreatorUpdate';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "CollectionCreated" (
    id TEXT PRIMARY KEY,
    chain TEXT NOT NULL,
    block_timestamp INTEGER NOT NULL,
    block_number INTEGER NOT NULL,
    transaction_hash TEXT NOT NULL,
    contract_address TEXT NOT NULL,
    creator_address TEXT NOT NULL,
    collection_address TEXT NOT NULL,
    salt TEXT NOT NULL,
    policy_id INTEGER NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL
);


CREATE TABLE IF NOT EXISTS "TreasuryCreated" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "creator_address" TEXT NOT NULL,
    "collection_address" TEXT NOT NULL,
    "treasury_address" TEXT NOT NULL,
    "policy_id" INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS "SplitterCreated" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "creator_address" TEXT NOT NULL,
    "collection_address" TEXT NOT NULL,
    "splitter_address" TEXT NOT NULL,
    "policy_id" INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS "NftPolicyUpdate" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "nft_policy_id" INTEGER NOT NULL,
    "config" JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS "TreasuryPolicyUpdate" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "treasury_policy_id" INTEGER NOT NULL,
    "config" JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS "SplitterPolicyUpdate" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "splitter_policy_id" INTEGER NOT NULL,
    "config" JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS "ApprovedCreatorUpdate" (
    "id" TEXT PRIMARY KEY,
    "chain" TEXT NOT NULL,
    "block_timestamp" INTEGER NOT NULL,
    "block_number" INTEGER NOT NULL,
    "transaction_hash" TEXT NOT NULL,
    "contract_address" TEXT NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "wallet_address" TEXT NOT NULL,
    "status" BOOLEAN NOT NULL
);
