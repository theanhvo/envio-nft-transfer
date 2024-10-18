CREATE TABLE public."NftTransfers" (
    block_number integer NOT NULL,
    block_timestamp integer NOT NULL,
    caller_address text NOT NULL,
    chain text NOT NULL,
    contract_address text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    from_address text NOT NULL,
    id text NOT NULL,
    quantity numeric NOT NULL,
    to_address text NOT NULL,
    token_id numeric NOT NULL,
    transaction_hash text NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    db_write_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);