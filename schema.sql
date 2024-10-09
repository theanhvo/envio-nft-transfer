--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Debian 16.4-1.pgdg120+1)
-- Dumped by pg_dump version 16.3 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hdb_catalog; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA hdb_catalog;


ALTER SCHEMA hdb_catalog OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA public IS '';


--
-- Name: contract_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.contract_type AS ENUM (
    'Treasury'
);


ALTER TYPE public.contract_type OWNER TO postgres;

--
-- Name: entity_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.entity_type AS ENUM (
    'RFVChanged'
);


ALTER TYPE public.entity_type OWNER TO postgres;

--
-- Name: gen_hasura_uuid(); Type: FUNCTION; Schema: hdb_catalog; Owner: postgres
--

CREATE FUNCTION hdb_catalog.gen_hasura_uuid() RETURNS uuid
    LANGUAGE sql
    AS $$select gen_random_uuid()$$;


ALTER FUNCTION hdb_catalog.gen_hasura_uuid() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: entity_history_filter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entity_history_filter (
    entity_id text NOT NULL,
    chain_id integer NOT NULL,
    old_val json,
    new_val json,
    block_number integer NOT NULL,
    block_timestamp integer NOT NULL,
    previous_block_number integer,
    log_index integer NOT NULL,
    previous_log_index integer NOT NULL,
    entity_type public.entity_type NOT NULL
);


ALTER TABLE public.entity_history_filter OWNER TO postgres;

--
-- Name: get_entity_history_filter(integer, integer, integer, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_entity_history_filter(start_timestamp integer, start_chain_id integer, start_block integer, start_log_index integer, end_timestamp integer, end_chain_id integer, end_block integer, end_log_index integer) RETURNS SETOF public.entity_history_filter
    LANGUAGE plpgsql STABLE
    AS $$
      BEGIN
          RETURN QUERY
          SELECT
              DISTINCT ON (coalesce(old.entity_id, new.entity_id))
              coalesce(old.entity_id, new.entity_id) as entity_id,
              new.chain_id as chain_id,
              coalesce(old.params, 'null') as old_val,
              coalesce(new.params, 'null') as new_val,
              new.block_number as block_number,
              old.block_number as previous_block_number,
              new.log_index as log_index,
              old.log_index as previous_log_index,
              new.entity_type as entity_type
          FROM
              entity_history old
              INNER JOIN entity_history next ON
              old.entity_id = next.entity_id
              AND old.entity_type = next.entity_type
              AND old.block_number = next.previous_block_number
              AND old.log_index = next.previous_log_index
            -- start <= next -- QUESTION: Should this be <?
              AND lt_entity_history(
                  start_timestamp,
                  start_chain_id,
                  start_block,
                  start_log_index,
                  next.block_timestamp,
                  next.chain_id,
                  next.block_number,
                  next.log_index
              )
            -- old < start -- QUESTION: Should this be <=?
              AND lt_entity_history(
                  old.block_timestamp,
                  old.chain_id,
                  old.block_number,
                  old.log_index,
                  start_timestamp,
                  start_chain_id,
                  start_block,
                  start_log_index
              )
            -- next <= end
              AND lte_entity_history(
                  next.block_timestamp,
                  next.chain_id,
                  next.block_number,
                  next.log_index,
                  end_timestamp,
                  end_chain_id,
                  end_block,
                  end_log_index
              )
              FULL OUTER JOIN entity_history new ON old.entity_id = new.entity_id
              AND new.entity_type = old.entity_type -- Assuming you want to check if entity types are the same
              AND lte_entity_history(
                  start_timestamp,
                  start_chain_id,
                  start_block,
                  start_log_index,
                  new.block_timestamp,
                  new.chain_id,
                  new.block_number,
                  new.log_index
              )
            -- new <= end
              AND lte_entity_history(
                  new.previous_block_timestamp,
                  new.previous_chain_id,
                  new.previous_block_number,
                  new.previous_log_index,
                  end_timestamp,
                  end_chain_id,
                  end_block,
                  end_log_index
              )
          WHERE
              lte_entity_history(
                  new.block_timestamp,
                  new.chain_id,
                  new.block_number,
                  new.log_index,
                  end_timestamp,
                  end_chain_id,
                  end_block,
                  end_log_index
              )
              AND lte_entity_history(
                  coalesce(old.block_timestamp, 0),
                  old.chain_id,
                  old.block_number,
                  old.log_index,
                  start_timestamp,
                  start_chain_id,
                  start_block,
                  start_log_index
              )
              AND lte_entity_history(
                  start_timestamp,
                  start_chain_id,
                  start_block,
                  start_log_index,
                  coalesce(new.block_timestamp, start_timestamp + 1),
                  new.chain_id,
                  new.block_number,
                  new.log_index
              )
          ORDER BY
              coalesce(old.entity_id, new.entity_id),
              new.block_number DESC,
              new.log_index DESC;
      END;
      $$;


ALTER FUNCTION public.get_entity_history_filter(start_timestamp integer, start_chain_id integer, start_block integer, start_log_index integer, end_timestamp integer, end_chain_id integer, end_block integer, end_log_index integer) OWNER TO postgres;

--
-- Name: insert_entity_history(integer, integer, integer, integer, json, public.entity_type, text, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_entity_history(p_block_timestamp integer, p_chain_id integer, p_block_number integer, p_log_index integer, p_params json, p_entity_type public.entity_type, p_entity_id text, p_previous_block_timestamp integer DEFAULT NULL::integer, p_previous_chain_id integer DEFAULT NULL::integer, p_previous_block_number integer DEFAULT NULL::integer, p_previous_log_index integer DEFAULT NULL::integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
      DECLARE
          v_previous_record RECORD;
      BEGIN
          -- Check if previous values are not provided
          IF p_previous_block_timestamp IS NULL OR p_previous_chain_id IS NULL OR p_previous_block_number IS NULL OR p_previous_log_index IS NULL THEN
              -- Find the most recent record for the same entity_type and entity_id
              SELECT block_timestamp, chain_id, block_number, log_index INTO v_previous_record
              FROM entity_history
              WHERE entity_type = p_entity_type AND entity_id = p_entity_id
              ORDER BY block_timestamp DESC
              LIMIT 1;
              
              -- If a previous record exists, use its values
              IF FOUND THEN
                  p_previous_block_timestamp := v_previous_record.block_timestamp;
                  p_previous_chain_id := v_previous_record.chain_id;
                  p_previous_block_number := v_previous_record.block_number;
                  p_previous_log_index := v_previous_record.log_index;
              END IF;
          END IF;
          
          -- Insert the new record with either provided or looked-up previous values
          INSERT INTO entity_history (block_timestamp, chain_id, block_number, log_index, previous_block_timestamp, previous_chain_id, previous_block_number, previous_log_index, params, entity_type, entity_id)
          VALUES (p_block_timestamp, p_chain_id, p_block_number, p_log_index, p_previous_block_timestamp, p_previous_chain_id, p_previous_block_number, p_previous_log_index, p_params, p_entity_type, p_entity_id);
      END;
      $$;


ALTER FUNCTION public.insert_entity_history(p_block_timestamp integer, p_chain_id integer, p_block_number integer, p_log_index integer, p_params json, p_entity_type public.entity_type, p_entity_id text, p_previous_block_timestamp integer, p_previous_chain_id integer, p_previous_block_number integer, p_previous_log_index integer) OWNER TO postgres;

--
-- Name: lt_entity_history(integer, integer, integer, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.lt_entity_history(block_timestamp integer, chain_id integer, block_number integer, log_index integer, compare_timestamp integer, compare_chain_id integer, compare_block integer, compare_log_index integer) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
    BEGIN
        RETURN (
            block_timestamp < compare_timestamp
            OR (
                block_timestamp = compare_timestamp
                AND (
                    chain_id < compare_chain_id
                    OR (
                        chain_id = compare_chain_id
                        AND (
                            block_number < compare_block
                            OR (
                                block_number = compare_block
                                AND log_index < compare_log_index
                            )
                        )
                    )
                )
            )
        );
    END;
    $$;


ALTER FUNCTION public.lt_entity_history(block_timestamp integer, chain_id integer, block_number integer, log_index integer, compare_timestamp integer, compare_chain_id integer, compare_block integer, compare_log_index integer) OWNER TO postgres;

--
-- Name: lte_entity_history(integer, integer, integer, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.lte_entity_history(block_timestamp integer, chain_id integer, block_number integer, log_index integer, compare_timestamp integer, compare_chain_id integer, compare_block integer, compare_log_index integer) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
    BEGIN
        RETURN (
            block_timestamp < compare_timestamp
            OR (
                block_timestamp = compare_timestamp
                AND (
                    chain_id < compare_chain_id
                    OR (
                        chain_id = compare_chain_id
                        AND (
                            block_number < compare_block
                            OR (
                                block_number = compare_block
                                AND log_index <= compare_log_index
                            )
                        )
                    )
                )
            )
        );
    END;
    $$;


ALTER FUNCTION public.lte_entity_history(block_timestamp integer, chain_id integer, block_number integer, log_index integer, compare_timestamp integer, compare_chain_id integer, compare_block integer, compare_log_index integer) OWNER TO postgres;

--
-- Name: hdb_action_log; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_action_log (
    id uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    action_name text,
    input_payload jsonb NOT NULL,
    request_headers jsonb NOT NULL,
    session_variables jsonb NOT NULL,
    response_payload jsonb,
    errors jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    response_received_at timestamp with time zone,
    status text NOT NULL,
    CONSTRAINT hdb_action_log_status_check CHECK ((status = ANY (ARRAY['created'::text, 'processing'::text, 'completed'::text, 'error'::text])))
);


ALTER TABLE hdb_catalog.hdb_action_log OWNER TO postgres;

--
-- Name: hdb_cron_event_invocation_logs; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_cron_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE hdb_catalog.hdb_cron_event_invocation_logs OWNER TO postgres;

--
-- Name: hdb_cron_events; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_cron_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    trigger_name text NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);


ALTER TABLE hdb_catalog.hdb_cron_events OWNER TO postgres;

--
-- Name: hdb_metadata; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_metadata (
    id integer NOT NULL,
    metadata json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL
);


ALTER TABLE hdb_catalog.hdb_metadata OWNER TO postgres;

--
-- Name: hdb_scheduled_event_invocation_logs; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_scheduled_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE hdb_catalog.hdb_scheduled_event_invocation_logs OWNER TO postgres;

--
-- Name: hdb_scheduled_events; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_scheduled_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    webhook_conf json NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    retry_conf json,
    payload json,
    header_conf json,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    comment text,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);


ALTER TABLE hdb_catalog.hdb_scheduled_events OWNER TO postgres;

--
-- Name: hdb_schema_notifications; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_schema_notifications (
    id integer NOT NULL,
    notification json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL,
    instance_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT hdb_schema_notifications_id_check CHECK ((id = 1))
);


ALTER TABLE hdb_catalog.hdb_schema_notifications OWNER TO postgres;

--
-- Name: hdb_version; Type: TABLE; Schema: hdb_catalog; Owner: postgres
--

CREATE TABLE hdb_catalog.hdb_version (
    hasura_uuid uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    version text NOT NULL,
    upgraded_on timestamp with time zone NOT NULL,
    cli_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    console_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    ee_client_id text,
    ee_client_secret text
);


ALTER TABLE hdb_catalog.hdb_version OWNER TO postgres;

--
-- Name: RFVChanged; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."RFVChanged" (
    "blockNumber" integer NOT NULL,
    "blockTimestamp" integer NOT NULL,
    chain text NOT NULL,
    id text NOT NULL,
    "newRFV" numeric NOT NULL,
    "transactionHash" text NOT NULL,
    "treasuryAddress" text NOT NULL,
    db_write_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public."RFVChanged" OWNER TO postgres;

--
-- Name: chain_metadata; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chain_metadata (
    chain_id integer NOT NULL,
    start_block integer NOT NULL,
    end_block integer,
    block_height integer NOT NULL,
    first_event_block_number integer,
    latest_processed_block integer,
    num_events_processed integer,
    is_hyper_sync boolean NOT NULL,
    num_batches_fetched integer NOT NULL,
    latest_fetched_block_number integer NOT NULL,
    timestamp_caught_up_to_head_or_endblock timestamp with time zone
);


ALTER TABLE public.chain_metadata OWNER TO postgres;

--
-- Name: dynamic_contract_registry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dynamic_contract_registry (
    chain_id integer NOT NULL,
    event_id numeric NOT NULL,
    block_timestamp integer NOT NULL,
    contract_address text NOT NULL,
    contract_type public.contract_type NOT NULL
);


ALTER TABLE public.dynamic_contract_registry OWNER TO postgres;

--
-- Name: end_of_block_range_scanned_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.end_of_block_range_scanned_data (
    chain_id integer NOT NULL,
    block_timestamp integer NOT NULL,
    block_number integer NOT NULL,
    block_hash text NOT NULL
);


ALTER TABLE public.end_of_block_range_scanned_data OWNER TO postgres;

--
-- Name: entity_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entity_history (
    entity_id text NOT NULL,
    block_timestamp integer NOT NULL,
    chain_id integer NOT NULL,
    block_number integer NOT NULL,
    log_index integer NOT NULL,
    entity_type public.entity_type NOT NULL,
    params json,
    previous_block_timestamp integer,
    previous_chain_id integer,
    previous_block_number integer,
    previous_log_index integer
);


ALTER TABLE public.entity_history OWNER TO postgres;

--
-- Name: event_sync_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event_sync_state (
    chain_id integer NOT NULL,
    block_number integer NOT NULL,
    log_index integer NOT NULL,
    block_timestamp integer NOT NULL
);


ALTER TABLE public.event_sync_state OWNER TO postgres;

--
-- Name: persisted_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.persisted_state (
    id integer NOT NULL,
    envio_version text NOT NULL,
    config_hash text NOT NULL,
    schema_hash text NOT NULL,
    handler_files_hash text NOT NULL,
    abi_files_hash text NOT NULL
);


ALTER TABLE public.persisted_state OWNER TO postgres;

--
-- Name: persisted_state_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.persisted_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.persisted_state_id_seq OWNER TO postgres;

--
-- Name: persisted_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.persisted_state_id_seq OWNED BY public.persisted_state.id;


--
-- Name: raw_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.raw_events (
    chain_id integer NOT NULL,
    event_id numeric NOT NULL,
    event_name text NOT NULL,
    contract_name text NOT NULL,
    block_number integer NOT NULL,
    log_index integer NOT NULL,
    src_address text NOT NULL,
    block_hash text NOT NULL,
    block_timestamp integer NOT NULL,
    block_fields json NOT NULL,
    transaction_fields json NOT NULL,
    params json NOT NULL,
    db_write_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.raw_events OWNER TO postgres;

--
-- Name: persisted_state id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.persisted_state ALTER COLUMN id SET DEFAULT nextval('public.persisted_state_id_seq'::regclass);


--
-- Data for Name: hdb_action_log; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_action_log (id, action_name, input_payload, request_headers, session_variables, response_payload, errors, created_at, response_received_at, status) FROM stdin;
\.


--
-- Data for Name: hdb_cron_event_invocation_logs; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_cron_event_invocation_logs (id, event_id, status, request, response, created_at) FROM stdin;
\.


--
-- Data for Name: hdb_cron_events; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_cron_events (id, trigger_name, scheduled_time, status, tries, created_at, next_retry_at) FROM stdin;
\.


--
-- Data for Name: hdb_metadata; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_metadata (id, metadata, resource_version) FROM stdin;
1	{"sources":[{"configuration":{"connection_info":{"database_url":{"from_env":"HASURA_GRAPHQL_DATABASE_URL"},"isolation_level":"read-committed","pool_settings":{"connection_lifetime":600,"idle_timeout":180,"max_connections":50,"retries":10},"use_prepared_statements":true}},"functions":[{"comment":"This function helps search for articles","function":{"name":"get_entity_history_filter","schema":"public"}}],"kind":"postgres","name":"default","tables":[{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"RFVChanged","schema":"public"}},{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"chain_metadata","schema":"public"}},{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"dynamic_contract_registry","schema":"public"}},{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"end_of_block_range_scanned_data","schema":"public"}},{"object_relationships":[{"name":"event","using":{"manual_configuration":{"column_mapping":{"block_number":"block_number","chain_id":"chain_id","log_index":"log_index"},"insertion_order":null,"remote_table":{"name":"raw_events","schema":"public"}}}}],"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"entity_history","schema":"public"}},{"object_relationships":[{"name":"event","using":{"manual_configuration":{"column_mapping":{"block_number":"block_number","chain_id":"chain_id","log_index":"log_index"},"insertion_order":null,"remote_table":{"name":"raw_events","schema":"public"}}}}],"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"entity_history_filter","schema":"public"}},{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"event_sync_state","schema":"public"}},{"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"persisted_state","schema":"public"}},{"array_relationships":[{"name":"event_history","using":{"manual_configuration":{"column_mapping":{"block_number":"block_number","chain_id":"chain_id","log_index":"log_index"},"insertion_order":null,"remote_table":{"name":"entity_history","schema":"public"}}}}],"select_permissions":[{"permission":{"columns":"*","filter":{}},"role":"public"}],"table":{"name":"raw_events","schema":"public"}}]}],"version":3}	3018
\.


--
-- Data for Name: hdb_scheduled_event_invocation_logs; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_scheduled_event_invocation_logs (id, event_id, status, request, response, created_at) FROM stdin;
\.


--
-- Data for Name: hdb_scheduled_events; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_scheduled_events (id, webhook_conf, scheduled_time, retry_conf, payload, header_conf, status, tries, created_at, next_retry_at, comment) FROM stdin;
\.


--
-- Data for Name: hdb_schema_notifications; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_schema_notifications (id, notification, resource_version, instance_id, updated_at) FROM stdin;
1	{"metadata":false,"remote_schemas":[],"sources":[],"data_connectors":[]}	3018	4f165608-af6d-42a3-9b83-f28788d8eefc	2024-08-31 07:34:34.47237+00
\.


--
-- Data for Name: hdb_version; Type: TABLE DATA; Schema: hdb_catalog; Owner: postgres
--

COPY hdb_catalog.hdb_version (hasura_uuid, version, upgraded_on, cli_state, console_state, ee_client_id, ee_client_secret) FROM stdin;
c8735aba-d8e1-4e37-9e36-e7634e0963ff	48	2024-08-31 07:34:32.187652+00	{}	{}	\N	\N
\.


--
-- Data for Name: RFVChanged; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."RFVChanged" ("blockNumber", "blockTimestamp", chain, id, "newRFV", "transactionHash", "treasuryAddress", db_write_timestamp) FROM stdin;
1035181	1720170053	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_75000000000000000_1035181	75000000000000000	0xa9d311097c44db3096d68b60e6dd5f5a0ece8faf42191a5a173ed48dd43d459d	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1542653	1721192466	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656250000000000_1542653	7656250000000000	0x640148bc01a8566a1ad42fc7ec2cc5960c7062df057a5fa406b97e782629e3d7	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1542706	1721192571	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656978334284627_1542706	7656978334284627	0x64a08e55890ad0fbf407edc129968e0544b783b2d69c4d4cf16575b432d969ec	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1546599	1721200134	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_18768089445395738_1546599	18768089445395738	0x867a9a2560572a85bb418bced8bf0f0805b19f5bdddb754eabe10b0a5e9db075	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1546614	1721200177	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19207966541772200_1546614	19207966541772200	0x29eed826f447acac2a7d34f850ff2b343ea83bf89005d075de9056127f43c4be	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1546710	1721200369	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19722465645569670_1546710	19722465645569670	0x4a3d306d4765054df4f641f5c17a924cd8b8dcef9f1d9b8d7316a1cfb8831397	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1546755	1721200459	BERACHAIN_BARTIO	80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_20184710934137709_1546755	20184710934137709	0x5fad38cca040abbb6b581059ad8b8ad858ccce53b1eb76786104dcaae3f713d8	0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536	2024-09-20 09:10:44.324589
1632066	1721364459	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2000000000000000_1632066	2000000000000000	0x08fba5be1e119f2187e64baf326ae0301438c0ca91a2df0556a43cd5f8baeb54	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1632196	1721364708	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2006530612244897_1632196	2006530612244897	0x40b600b34c61dd1f93a233b7f4a3e7a5a6e337f66f4d457e4af3dd2455c162af	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1632236	1721364783	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2013219047619047_1632236	2013219047619047	0xac379eeeca34d737c4ecb3d154aab07bfa4f64f1bfbe5f1e4cca5a50054b84ab	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1632340	1721364983	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019792824101069_1632340	2019792824101069	0xe13a14f7f4c5af1a5734a04d038fbada35299b56fee1ed21c08a071c73c5379d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1632618	1721365512	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019819927834800_1632618	2019819927834800	0xb0d7ea977cae26e6b2d5d26c90b0368a40899320296e817f230c264fe0d8ed62	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1642488	1721384583	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63244309723753167_1642488	63244309723753167	0x735edeb1345d95b3eb93b543cfde7e67dcd9ca1739d583241e2dadc6ab0196a5	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1643662	1721386829	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63455124089499011_1643662	63455124089499011	0x34d0468b88748d0f7006adadb95b7429fa8bf8d1a837ee81170f38b978a88e13	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1643694	1721386936	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63662324494689212_1643694	63662324494689212	0x083dd9d5092f850aab391aeb85146008c2610d4d0f9762214c669341b5328e6c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644163	1721387815	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63874532243004843_1644163	63874532243004843	0xb3b463e78aa69459ad1791e0c66496591a03473aeb7731acf14d61e7f860a9be	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644262	1721388040	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64091977459151242_1644262	64091977459151242	0x108bd3448677a82aa38ca482ce5fccc0a6325b86eac7b31892225536788d667a	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644517	1721388518	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64305617384015080_1644517	64305617384015080	0x064cc4a25553372096aa718eb63ff5999545e74d6459fb36e29c6c37e143b726	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644783	1721389019	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64524530124045769_1644783	64524530124045769	0x83d87e9144a39612c6baceeaacf3c4c4d36805a9531b75e68aa3d3280763c313	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644794	1721389045	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64748963272303320_1644794	64748963272303320	0xc747414393a38ce5af324135697b4d9b95a2fb45c7f252914d8c0af198f9d2c9	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644940	1721389340	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64969385274932437_1644940	64969385274932437	0xcb803ef77bf89b32efb005967a63f88528c1d58acf1ccbd2086c6cd8d7997d22	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1644990	1721389438	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65185949892515546_1644990	65185949892515546	0xa66d7605c2ac487ad1357910e921b9fc3158ef0d4f5c94489e4a20a605bb5959	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1645013	1721389486	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65398801973797229_1645013	65398801973797229	0x313799fbe3a167607afbc82230454f9d56c01ee31f2268fef135bd6cb84c87b6	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1645179	1721389788	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65616797980376553_1645179	65616797980376553	0x66998f0a9230535a26950a054ad05a3c6331bbc7993d4a9665302467be0d17c3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646408	1721392151	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65831056912557374_1646408	65831056912557374	0x89f7c1fb7e741b7f7efcac246eb7711402afc4a9659b4072c8232cf0e63c933b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646528	1721392384	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66050493768932566_1646528	66050493768932566	0x470e1f84a2a493f7528dee321d0d96f059459708bf4a4c63f6a85081d9f53595	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646536	1721392399	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66275346513677868_1646536	66275346513677868	0xd3e142bd20b9f86eeeea125695b02de1c063f8b87b6f0f7e9d226a2d808a1f9b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646542	1721392408	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66505869458073269_1646542	66505869458073269	0x91991e22d66456f84bd9b02f5fb374c4d5089917d69b97dd444c88da2ea59820	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646546	1721392412	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66742334771701974_1646546	66742334771701974	0x468062095fdc3d71c7ffb2de7b8798b6d52d9a5ac1fb1f445c5c4d939cda9c6c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1646698	1721392695	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66974482023081807_1646698	66974482023081807	0xc3aebe69d0f2b2f95d39cfd0cd5ac54fa6f7b1ecb4bec445944f19b6d1e6563f	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1651085	1721401116	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67202480259756128_1651085	67202480259756128	0x0b9f60f6c141e925d01cdf14ad3c18402b3d0f7d063270fd399366ca0281290c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1652060	1721402898	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67426488527288649_1652060	67426488527288649	0x53f8f5d6d6e4d2156e197d54ced4c9b15defcc99836d4a5434e2f2e2eebb39bf	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1652087	1721402947	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67656025509509206_1652087	67656025509509206	0x3fbf0bb1b310f08cdca218e910ce1b85c50c31fcab54b1079201f45ea7a50ce4	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1656270	1721410625	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67891350815629238_1656270	67891350815629238	0x38ea21ec1e7e322d11ff5c4340fa979e498e827ca5ce61654d13f5a49e36e068	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1656307	1721410697	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68132742285195920_1656307	68132742285195920	0x0f8f427f5caf1a041ef82179b41c106d06ff891d885be399dfa5daefc230287c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1656336	1721410745	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68380497711687541_1656336	68380497711687541	0x6a61f4302ed34204326bacbbb13563c2938d43bc38e64f281aacc25daa36333d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
1679116	1721452702	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68623628370217986_1679116	68623628370217986	0xb7a0eae7bef614dd0d0ba3bc79b4e3f331bbbfaacda520ff5472b1302d0227cb	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2074670	1722174122	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68862319251505700_2074670	68862319251505700	0xd6773228fa00aa87aaabb80a404d7608112e0ea53dd228bd2a2bba58c7db9cde	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2076422	1722177267	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68863303584836276_2076422	68863303584836276	0x10d88ee7e33c7a085aeebe9d78c6b7a67df736289e9d3986655cc746661827bc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2102177	1722223355	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864287932237131_2102177	68864287932237131	0xf8bf88550970d08d4d68b886997c49a6c53bce41817a0a470a794815c8b75f2d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2106907	1722231968	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864091065571016_2106907	68864091065571016	0xd0d042de295f0ff0fb5b624a75193a0d06f1f9414d7084ab97ebc24739e221ad	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2109865	1722237301	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68865075424228296_2109865	68865075424228296	0x9e211bedc13407360d7ec5a9f7194cc479bc3a948966d4d98620c4a9d6a4865c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2110031	1722237607	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864878552496840_2110031	68864878552496840	0x8a39e5c8f15cf23e8a32d2d981d64fb589c6e0d02382204dae710f149d628c66	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2111006	1722239407	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69109731454016829_2111006	69109731454016829	0x6fd3c70a06141d3d2c5817951a915fb1fcc522296a5668ac9e507ba5294eff15	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2115280	1722247042	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2115280	69110741276576888	0xb6bf7a19a15f5582b2ace4ec3b72e0a27d77c7b99a1d9f40c65381d0cc55a8a6	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2163600	1722333711	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2163600	69110741276576888	0xae7968a46c0255b63b2ca82a98171896e34c8e7b63721ef7ae8d328154ac73e3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2164169	1722334725	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69114732623000800_2164169	69114732623000800	0x4eaa6fb5deaa823f7869d1691b15c35f6189a78d45cb61a2523c72f831701184	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2167496	1722340700	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69163204105883618_2167496	69163204105883618	0xaa4d026a9bd074e10e89dcd24d69784fb77a5c6c6285328b31724e42e08429a7	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2167966	1722341529	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69414706666268649_2167966	69414706666268649	0x772490d8f634804dd04c78fd066bfbd2fa32b894df1ae7071253284b28411bd3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2179404	1722361899	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69661514512193160_2179404	69661514512193160	0xa1f03e1f2ad50ecf9719d189512a9edfefd6950ba7e50a67a23a4f20fd2045a7	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2180230	1722363392	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69914829110419317_2180230	69914829110419317	0x008b405f2a63df83c81475ba50179deb8160fabfeeab4cebfbc5911e8ae45176	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2180239	1722363407	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69946173243021746_2180239	69946173243021746	0x78183f90a3c954252abce0e28e5df66e5f08125f06778cdc7778d669ef29537b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2203939	1722406388	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69939904416501260_2203939	69939904416501260	0x44f1e736c153995402b840f3c5deea731226b6d5d2ba84b8a18e97ee57c63ab1	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2254144	1722501484	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71529651223560266_2254144	71529651223560266	0x9c789b8eeb93a59b7c801b08822c02e0622592d056544892c897a9e7a228a687	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2259757	1722513306	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71789759046191394_2259757	71789759046191394	0xde15a3472c4c42a9ff5f62c5a99b02522faf220f1e1d62eb8fadd1a205ab2341	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2260402	1722514595	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76335213591645939_2260402	76335213591645939	0x8ba4f21a19fb8cc583dc6fb251f09e3bbfade9ab5498572d2c9471573ee557d2	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2289928	1722571418	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76606627684416236_2289928	76606627684416236	0xf92cb44850932da48443486bae53dd08dfb120527da8af59b3bbf3ed383bcf32	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2289959	1722571464	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76885197239632295_2289959	76885197239632295	0x6a22701557813d4f96478100fa5eb74d8c7575b6374cfaba35bf90cb27adec43	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2289968	1722571482	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76886346208955926_2289968	76886346208955926	0x53625077cae97f0ab502cdc2cf330c4d2bff3ec81f70ca98af83702d62e8714b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2290024	1722571596	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898695471050872_2290024	76898695471050872	0xfdd65536b25e5f86373b3fd095f62c4241e1950930c99095688edbf890dc4d49	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2290138	1722571831	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898465677186146_2290138	76898465677186146	0x4ab9ff3ca885642452ddc0dabae7553c0730c9f3e59057fc770b9a9843695c26	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2290229	1722571993	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76912255688465741_2290229	76912255688465741	0x5435183f7046d3c0f273d536153d0908a296692b89822efefa55ff24ed52b86a	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2290248	1722572048	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77185721486469175_2290248	77185721486469175	0x8903a4b923ba4804aab78bda7a72e65a7e8202c25b8a578d097a513b67771f9f	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2290693	1722572932	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77454193561204720_2290693	77454193561204720	0xd793ce23c266da52355aa4a9350440f1c906b870784edb06987a10fd9984b1fb	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2296184	1722583770	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77729586249422337_2296184	77729586249422337	0x87b8bb602b90a960d32f9bd0ecfecfe5813aee430486a613f47ebcfe38904e41	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2296190	1722583778	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78012239290329327_2296190	78012239290329327	0xe273493349f2a240211d0b25683e9206a6cd1b02698174080244d115243b407c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2296271	1722583952	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78289616141139387_2296271	78289616141139387	0x988fc80aece7d67f997862937af1613a0b61e904d9d6b31d6bcd78dd6a9ce0c1	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2296343	1722584159	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78574305654379894_2296343	78574305654379894	0x623a5dddf3feb51944c0feb95f383a65d31f1f9bb4eebb0a230089a619e359b3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2296372	1722584213	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78853680963373245_2296372	78853680963373245	0xb27ed368feeadb53e7c9236b5bf442753548a1fae035184d791a8ce178cf5834	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2299281	1722590257	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78854833163277732_2299281	78854833163277732	0xaa657da492386dc670b76184cc70d9d04ab47f6076f55acaf3512b7b763e2fea	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2304025	1722599893	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78923726254072218_2304025	78923726254072218	0xe90a6f659f67db1068823ba6751cb88b9542851e444e23e4dc1fb74f3ea791ae	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2313737	1722618288	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78949583734301437_2313737	78949583734301437	0xbd5843888073acb39b67b0655a9e276e0a87a62784f5b02ddb5c59745801273e	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2339726	1722664005	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79018559605813736_2339726	79018559605813736	0x79bf3c5853c6c3b0b97b6583b695c5c71f1154ed3ed6dedce1a0181fffe2d9dc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2346527	1722675634	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79026641869444651_2346527	79026641869444651	0x273b2bfa1f236a3553a229a4d4186b69b19574fffbb4998c18f15514c0665339	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2388526	1722747737	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79314011476242631_2388526	79314011476242631	0x6c6a39a731170b4c72556ed77f09d226dd25d826e06415be1bb06c8aee2a4715	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2388620	1722747890	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79596016850380383_2388620	79596016850380383	0x03a3cbfb50b8e34de0fde58b4d9ec8a539e6e301fecebaf9657a320facda647e	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2388642	1722747941	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79885456911654493_2388642	79885456911654493	0x4e938601cd311eb6c76033192c1130bb0649bb79cb806d66574a04845524109b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2388665	1722747969	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80100341826883850_2388665	80100341826883850	0x487b15e4ea398d6ad80aea20e22230a11bd205a0c5c12dbd48599254632202ad	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2396172	1722761298	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80057364843837979_2396172	80057364843837979	0x96f88a731cabd56bb055377015ad405278d145d80df27607d1122d7ce9bf16d9	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2396649	1722762129	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80342013252171625_2396649	80342013252171625	0xb3c36dc50a53bdea02966866a152aa5b612fc90151dfef5fd2d439709ccfd35c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2413027	1722791504	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80634166027634067_2413027	80634166027634067	0x02d10bab62c36c8d00b7a5a73228e73e221083d834846beb15ebc7f886247266	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2413072	1722791585	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80670315840548075_2413072	80670315840548075	0xf9ddaab720f7df6fe2c4dff0943eb0a2b8842c43677ae953a515c5dfc51ed4cb	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2413087	1722791614	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80663085877965274_2413087	80663085877965274	0x059a93ddad65fca5a89f72814491c9ec2d65f9cb1c3695fb907fee9d9f14c913	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2413119	1722791688	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80712697341931636_2413119	80712697341931636	0x1a6dedeb3b45f9a163de3ec5497934061432931f0fedeea75e7bb81df544a67e	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2418472	1722800949	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81013023657622544_2418472	81013023657622544	0x877036fd77a71c203fe95a67432f835481208f4ef6fcc6cd2f0a4bfd03c28ffc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2418499	1722800997	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81307616470922990_2418499	81307616470922990	0x8298897b80d66052df1aa398adae102f10eff333931ff2430b279205f139f967	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2444255	1722848085	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81596710218375161_2444255	81596710218375161	0xa6977057f4c5768def134322ae66c5934a2ae93d446cafc121e9524c9620257d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2451393	1722861767	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81893425528260161_2451393	81893425528260161	0x7cf605090febd14b4959f2c16a31f1e9d1e10ee12dfc78c0c82b2e5b36dc2b05	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2458544	1722875449	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82184602152360642_2458544	82184602152360642	0xbfac7130d79df6bf6e5f852c4b89c25a88e12bc5b7a5795d2f2410616f5c250d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2474675	1722906600	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82483455251096499_2474675	82483455251096499	0x1effff09ad51550da1f07d57e270052bdef919d9fd686bf65e2aee3991388cfc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2479145	1722915097	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82776729758655953_2479145	82776729758655953	0x0f972c3977786705c0f37ba3fac800ce1c4470db9a06108b64048cd1e7e924c7	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2479160	1722915123	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83077736048687429_2479160	83077736048687429	0xb26d6cab407a6d3460cf4b4b14add111d0c01c14be523a83de0f838417ff72de	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2490025	1722936835	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83373123554638318_2490025	83373123554638318	0x187716a368ce48255be024da7411a750108af9af8daf20f339b581648722a58b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2500576	1722958546	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83385198354167623_2500576	83385198354167623	0x679bb3dc47a806b404733f1557dae508514cd6dc827fa6e897fcda511d9d43b1	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2501547	1722960549	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83438085542211618_2501547	83438085542211618	0x7b59b3f3441ef3a7a8057b27b8228ab7acaa62ac0d46e2cdbf33355ade69d494	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2501699	1722960850	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83741496762365115_2501699	83741496762365115	0x03c639297a618529e20df9e4c3086dadc9855e12d1a4c094827c6a26fc36215a	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2501738	1722960927	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83779039650079252_2501738	83779039650079252	0x06669b2027c545f49f81161eb10e7b7c72b8892600dca8ee30863b0d57d20474	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2501752	1722960971	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83771531072536424_2501752	83771531072536424	0x6aebb7fca8b74708e467f9ee73d9c0aa24cde9323b8e12a4ead35d7e6829fcb3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2544453	1723051439	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83884200130516922_2544453	83884200130516922	0x72d1e07a4466c87e4afb69468b09cefbbfbc7b6324fdf11572541cddeacb3397	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2544475	1723051482	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83861666318920822_2544475	83861666318920822	0xf643174e3de96eb77b11e14e3833bcf073f5ec76813e69f3fb271ab429bfa534	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2544558	1723051718	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84173709728479597_2544558	84173709728479597	0x0e81902b88bf42e1097d6e5632ab4b645927d5823cbcb71ec15c2e54dde2b527	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2546710	1723056375	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84201926645368331_2546710	84201926645368331	0xf2da022adeab2778962ca1219903cea2d85b54d48e1f08bae2298182155320ce	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2549027	1723061573	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84508115469533307_2549027	84508115469533307	0xc1c3e6c38058e0b0699c3ebe205fad706a52a778449d2effc7934187e27175bb	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2574332	1723109270	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84822564271280407_2574332	84822564271280407	0xe42faa31c877350a351ee94733fb0571751385071b9eabd6ad6c5463b5a1bbd1	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2574390	1723109367	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84861476183529736_2574390	84861476183529736	0x00f87a09e02fe52a5b9c1cda4d2c78aaafb4e328ca2ca1acb2150407b71cb5cc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2574744	1723109974	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82986055353812180_2574744	82986055353812180	0xf2734e5ed348658d8d8992bd5d1b65c8ac7686b530946ebfd92beb0073f026bc	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2583991	1723125689	BERACHAIN_BARTIO	80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2583991	0	0x9d7dd8abe812fb562a14f8382874e6e6e9678923de7a15ce90b58b49e3231f1a	0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4	2024-09-20 09:10:44.324589
2593405	1723141581	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83281116883959067_2593405	83281116883959067	0x438eaf3c7484643f232f9c0abde1e2e285d69116201749c441cb63484b0cb089	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2596078	1723146048	BERACHAIN_BARTIO	80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2596078	0	0xc6749e404e8b9c86b746a138d4da16f767ea36931268732c6ed4777818a0e156	0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4	2024-09-20 09:10:44.324589
2597609	1723148590	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_194392227995070179_2597609	194392227995070179	0x36639fceae07956f38dc3ca1bf6401e6f17cc1509d80c239965ddccb1491ba43	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2598063	1723149367	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1305503339106181290_2598063	1305503339106181290	0xc18d9a3a9c901b6a2281e595ab162e8bf45a2ddda2e5edb3d4435a014be6d655	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2600989	1723154293	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_500000000000000_2600989	500000000000000	0xc4c63af1a4ec1c51861443a6d0b98835e205036e0ae455a522b8425905763364	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2601272	1723154779	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7500000000000000_2601272	7500000000000000	0xe0b14054f707617ce85737dfc718efcbcb86d1cfe60fb1135f78bdb2a933425d	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2624430	1723194408	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1749947783550625734_2624430	1749947783550625734	0xea41ec57e8217617999b20642ab5aeeb2287dabd123d78909c1497a62632e965	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2628721	1723201819	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1861058894661736845_2628721	1861058894661736845	0x4a9578b08bd595a5a22e6c05d3856178167f1dc7304a6a56220927e2773f507a	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2633070	1723209241	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1883281116883959067_2633070	1883281116883959067	0xbbdfc4f44fbc2d1ae6b615d6fffcd1d68dbbb28d8442fca4c2307993fa248e49	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2659845	1723254433	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7530000000000000_2659845	7530000000000000	0x6e9fa3f7db71fbae4da49f5834a7454e6d0b8c3c0a4163a364ee299aa0ccf130	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2660363	1723255327	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1994392227995070179_2660363	1994392227995070179	0x7b0ad1953ee037d688265653637cabb8e352aafdb5b496be10fe2445a8bcd4ce	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2666071	1723264979	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7550000000000000_2666071	7550000000000000	0x5c698608a7bca53024ede8060614470a178a7f91b453f7bfebd540192af0cabe	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2666246	1723265279	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7650000000000000_2666246	7650000000000000	0x4feb25476e824de6c77e41ad934acd59a94f13a3290d46cd4526318f5c059d51	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2669719	1723271161	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7652000000000000_2669719	7652000000000000	0x65022c9fccf08c3aa974505f57613e2ce8df5ef5dfcb946f694bdc63406f0500	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2675754	1723281599	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7732000000000000_2675754	7732000000000000	0xa20045d351bfce7e2879afea5d67d04fe97ba79242acf3d3fcfac78d7f10f5ee	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2675953	1723281946	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2216614450217292401_2675953	2216614450217292401	0x57769c8a8d007c7f458e0f68073f786c7e313294a473f502c3ecd428e8cb4f55	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2678656	1723286879	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7772000000000000_2678656	7772000000000000	0x89dd1bd8df165eb41c124d2209104de5154140ee874a2ae5280f04be962625ca	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2679355	1723288181	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2261058894661736845_2679355	2261058894661736845	0x3e5d09615608813dac5f16ee4e970f5171154d0152c77cbfa80fbedabbaa3061	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2680029	1723289435	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2283281116883959067_2680029	2283281116883959067	0x5d3c2b422a1b668e051d64629821cbd65ec42f54025de15d7c3e13eb438f2a79	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2680849	1723291010	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2394392227995070179_2680849	2394392227995070179	0xbb4ca7c200f9ddf1a137b62df7b9f2b0642272ecdd961517516cdbf37dfacffb	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2685757	1723300052	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7774000000000000_2685757	7774000000000000	0x17c11efb3f0abed9942c886f300af1d913958d7e48fc43d8983e4e34da738915	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2685792	1723300104	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7794000000000000_2685792	7794000000000000	0x42337ee2dfad5129533b2ae8de16b1d8d69a98752c405f6af020a81fa6f1d2d1	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2688951	1723305921	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7796000000000000_2688951	7796000000000000	0x25da7d611c68f3c36ad08d92c8615690db8fadb67b0cabd5ee68c02ded04e384	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2688967	1723305949	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6866666666666666666_2688967	6866666666666666666	0x5faf83c7f1d63e26c5846c14172d06ae9c937422df5002726ff25eb992ac0507	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2689966	1723307897	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2403099108824143161_2689966	2403099108824143161	0xa19962719331f1c7b607192f25fa846bf5fec9336275a2f9229c2c034a0a82d3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2690005	1723307963	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406331172382711124_2690005	2406331172382711124	0x0417b25353c5505b307a83fbb5b145424ef7668dd511109f3926f6eb51651072	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2690081	1723308118	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406358777676443360_2690081	2406358777676443360	0x0d9111de70971c9726c14e5268cffd9bf1942cf6fbcfd76ae01b3e16ac98856c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2691504	1723310719	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2354665633472225941_2691504	2354665633472225941	0xd483c5a77314338b92f381a44dca6981b8810d2203dba3d63e5e2ecd188976f8	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2694359	1723315857	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6900000000000000000_2694359	6900000000000000000	0x7a5685f7d75da53fdef0e32b6b17247ffc4ba15c20dc80b0a4703b8b2575515a	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2697422	1723321436	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6966666666666666666_2697422	6966666666666666666	0x7a7d1b2eea5de53d6b5839284ce86dd5bdda8b63b07819bb8922fc4b676c8aff	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2699443	1723325135	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6973333333333333333_2699443	6973333333333333333	0x140bc1a00fbe2ffab5ee59e6cfbc9da109f3b416f6dc9990b010f0b1a8926fb4	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2699529	1723325308	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6976666666666666666_2699529	6976666666666666666	0xf51ca86a40e3c29116329f5a70c18efd0a7d398acc019ec5ade7764ab318df3f	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2699766	1723325742	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7043333333333333333_2699766	7043333333333333333	0x5821ac5be14e58e38fa844b2b264da3281f0ce3de399ac1a6fdb23fb67927fdb	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2711188	1723346982	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7836000000000000_2711188	7836000000000000	0x2b993c0da2f8cb3e51e26d1837bdb852274fe1e3824de76c1f83fadf0dca7ac9	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2715302	1723354657	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399110077916670385_2715302	2399110077916670385	0x8b29f500c3801cfcce7f8e98ba7a3608c4b16f81ec73623f7034f69ceceb628c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2722976	1723368848	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7856000000000000_2722976	7856000000000000	0xe9544da3341c00b51d3dd0d3c41259e4a4a629562d4666dd04bcc39088e112c1	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2733932	1723389216	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7926000000000000_2733932	7926000000000000	0x08388dc71099654e0de11bdf81f8b82c0b1f976e5d49f296269aa49e94281f6c	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2735221	1723391558	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399332300138892608_2735221	2399332300138892608	0x74dd9bede9ec57722b38fd43c623a3b9f4d5b51d8476479cd5bfb08521ec2b14	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2766691	1723448340	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421554522361114830_2766691	2421554522361114830	0x525d6195ffcf88de1bc05b0f7a4f81e6afa0e810f9d506a0296e817ab98ce20a	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2770445	1723455226	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7110000000000000000_2770445	7110000000000000000	0x9623fe7cfda66bce9febdb1475354b88c7814cb008e0904b529fabce73367595	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2773564	1723460935	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421776744583337052_2773564	2421776744583337052	0x7878ea57afbf66540ad3212dcdfefc8b1a13d9889971ba09a4a1621527cbbba8	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2788002	1723487050	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7946000000000000_2788002	7946000000000000	0xa8fbceb143e001d5baae7a9b7603b77094865d788b308ecdc5a0e990b4ab91b7	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2791109	1723492593	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8066000000000000_2791109	8066000000000000	0xdbc100e5c3ba09b75e682e99807d45b1c0790612fb56efdc27d1caf88bfb334e	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2816357	1723538484	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8406000000000000_2816357	8406000000000000	0xb2eb2a837a244469f46827ac45fa06444f56a68757a21b6c9fc07aa43b4b9351	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2823220	1723551452	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3088443411250003719_2823220	3088443411250003719	0x8d9e603993d5ec3be11522386a62c1df390907325e980db7295965927e5a98d5	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2826369	1723557134	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3099674114563640096_2826369	3099674114563640096	0xf8de06584bb77120bde88831f289595e99f5ca81b218ca4671447b3227dd95e8	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2826443	1723557272	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3103843041143626063_2826443	3103843041143626063	0x26765dd2b31c9dc9af28ededaef22bf0ca2ac6ba7c5583514d4c10ba387e22fe	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2826606	1723557571	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3104635148929536719_2826606	3104635148929536719	0xdddd567d726496c0a8265b666f41c5dc5dbd42eef3b1996eef6af55f0b1e4f10	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2829422	1723562728	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7116666666666666666_2829422	7116666666666666666	0x42fbbe175838d5dd70b1bf87f3c7c22cfa41650536dbb185837106df453abae3	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2838014	1723577620	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606000000000000_2838014	8606000000000000	0x6c5216c452bf2a9b8bbdfcb3a639bd8fdd39158b497f1c7d67117afafc5d321a	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2846068	1723591406	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606017556591131_2846068	8606017556591131	0xd6ed67230d0c0763e20983bd7f3f188881ae6b6058a87f2a49929fe413cd43f0	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2846146	1723591538	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606035112866947_2846146	8606035112866947	0xb5ee9c85cac521c32381e9d5827801d90cb3f3e181512101df962a32449207d0	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2852388	1723602298	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3263726058020445810_2852388	3263726058020445810	0xce930acdc25cbde393d943c6573513de081acd587e929244204ca79dab0f3981	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2890454	1723668886	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3275870154980521888_2890454	3275870154980521888	0x2b69fd40e7b9406f443fb3c89197781f4815c876beb439bfe993ee055f043e91	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2890580	1723669093	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3277372943455568703_2890580	3277372943455568703	0x3874200bf0e2773ffbbee847a6e6945e6627843b0357255a58c12efb504fba77	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
2912110	1723706895	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7783333333333333333_2912110	7783333333333333333	0xf34b5b860a7b073ce3d2491434efb0fad1e0cd2195806eaac1d862bef4330126	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
2913325	1723709106	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8608035112866947_2913325	8608035112866947	0x856df3f0b1c06b958718de6c5f3c4807de22c309b11231e0811bc23441a313dc	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2917496	1723716587	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8626035112866947_2917496	8626035112866947	0x0c416d135f111bdf08a3a2712133ae4987e7e81a2a5803f23b710e0e01b91374	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2975602	1723818524	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8926035112866947_2975602	8926035112866947	0x825f93c80b3cacda0bcb081c93bfaedd301a2acb2a8896d48c5111b276e1079d	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2977642	1723822106	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9026035112866947_2977642	9026035112866947	0xecbf58aa599a1fa48b136d4cc72cd3d4b781155328ae9614047461ff92455307	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
2983801	1723832984	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3393652013223010563_2983801	3393652013223010563	0x650024a2d4a05f8370bd48d29c113edf3425cdc3a0dc9846f4faeef45537c59f	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3018720	1723894660	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035112866947_3018720	9246035112866947	0xf06ba6986b13b5fd31f0566d546c7c237c90bb96f391d59eadbb43ccfc639e8e	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3021402	1723899581	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035554851972_3021402	9246035554851972	0x787bc3d631cd91ae7747b712816962d23aac02c5bdec1bb173fabe7a74be18bc	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3022962	1723902452	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3416907827176498935_3022962	3416907827176498935	0xe6d74f6fdddd2e2c8c312b3f028038b8bd0aeea17b88123e93e12b7371680101	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3023282	1723903042	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9256035554851972_3023282	9256035554851972	0x84285cfae9f3640911ae4bae30fade3fd2af4ae34d47e3f8d80f26f14b7893ad	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3025262	1723906628	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9316035554851972_3025262	9316035554851972	0x3cc4c40ee8bdac785ab897280fb8115aed8268c2b90d64238ac9d189f23d4de4	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3027582	1723910779	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9324035554851972_3027582	9324035554851972	0xb2e83373db3f5dfc9eeb12012f92e9acb1e3c6e5e96e50b61f00e0f2497c50c8	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3028697	1723912769	BERACHAIN_BARTIO	80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_20000000000000000_3028697	20000000000000000	0xbe4c4d20016915d07c111e33bca47d0cebf1d2dc63d56a28c8c24e339f765e0b	0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4	2024-09-20 09:10:44.324589
3029058	1723913436	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9344035554851972_3029058	9344035554851972	0x90f3b8e45b3f18af19fa46156e7b6c8595a7816fa66670d3a45deaf0bf8a5498	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3032396	1723919525	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7916666666666666666_3032396	7916666666666666666	0x6edee536b1f110c4becbcefd97b155143fd004f1ac6dd49207d4d064e446081a	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3036846	1723927639	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7983333333333333333_3036846	7983333333333333333	0x889130b636a0f319afdb6ed8a5fb57c897bf2fc8e1533714a79b7e9c9baea572	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3061939	1723972338	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9544035554851972_3061939	9544035554851972	0x65fb6311c4e21b3ece5d1aa021053d1096352e2d2154d4d08a11d25ae05a4c09	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3076136	1723997465	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3419233408571847772_3076136	3419233408571847772	0x63a05c56d7acce154fecf3d94d293823639c4f87bc08ea93e7ba75f6d9f223df	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3101865	1724043088	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9564035554851972_3101865	9564035554851972	0x0ea6c82cb21236dc452c4507362670746f230cd5fca2b13ea5696fa2f2e66e18	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3108017	1724054209	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9644035554851972_3108017	9644035554851972	0xe088fe52b5ba00b7918a4270b2c8ccad538846d519ac43b070ff9521d55c15fd	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3108721	1724055462	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3421558989967196610_3108721	3421558989967196610	0xe3f27d1c16d88fedba77a8eecb187d8c7016315ed35886c24076cfe8246ed5f3	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3109144	1724056208	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9646035554851972_3109144	9646035554851972	0x8202b04f6357a1ba9f821478f8ddc3e85bc0d3e590ae2850f3ee76beb54c013a	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3123354	1724081924	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9666035554851972_3123354	9666035554851972	0x44cedb89fe5f7801d33e0e08cc7357b133be43cd830eb7b5dc629aa85d1c07f4	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3128801	1724091656	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9694035554851972_3128801	9694035554851972	0xade55b3bdd93c0af8773dde9a052c71bde9e759ee64cae2e2429b7bd33143099	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3136530	1724105272	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3654117129502080330_3136530	3654117129502080330	0x81637bbf992d9436072d68ec95d22c152f4761cc03b5affed021345869c70068	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3189030	1724196780	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9714035554851972_3189030	9714035554851972	0xbf59934c76bac25faf7c748bf488635f61c3e4ae1278754163b68d51f2d2d132	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3222943	1724255521	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11314035554851972_3222943	11314035554851972	0xf0562256fc07998c043af82f3e527a18bf7befc4578526209e0d5f44c7a67197	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3259309	1724317417	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259309	0	0x24acda3c1b82bcac0ddc1dabfcac6157ed43c21431e8ee60d5a153a386b73dab	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3259884	1724318414	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259884	0	0x118f8a454eb4261b6538e5cac0e4f35ed7c98e358af49328737c8f34a3905e31	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3259932	1724318512	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259932	0	0xd6531451556911f8f8c782a6370ce0b6076f670d4cbb3c4f250737c62da2add5	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3259995	1724318615	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259995	0	0x7c72eef9a42a2458a1ef50796ccbc65a17a5d76251e9a8291328eb1552280cba	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260027	1724318669	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260027	0	0x43b878f619d43a598ef9f68abf36e94ab8512b66917ceaa20e80bc40eeda59af	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260088	1724318786	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260088	0	0x20cb680cd25158d1c1e77de4620fa02a8897745c803720abc5e4ee45ef05ae14	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260137	1724318858	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260137	0	0x82d679ff3f74dce8ed114ae8615386c43c5eb65b700209c5b3bbbd1fd2e897bc	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260164	1724318913	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260164	0	0x121f738c500e566d3f570f5ca1d242bc27ab161c59acdf2e8fadea763fd09b23	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260176	1724318939	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260176	0	0xa0d0b74c27bce7c33420a7f83193898528b5d4ada14afd544e39e8138881a67c	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260188	1724318961	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260188	0	0xbc71bd6b3b7f183e2bfa3a2b6bf4d1ab9371a9a288f915f77c10467af2d59bf5	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260219	1724319010	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3322259136212624_3260219	3322259136212624	0xcfbb086fdaea64cae6e81f01ea300a6301cc8fd30855d45f0bba8e85a41e52e6	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3260241	1724319041	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3324058693244739_3260241	3324058693244739	0xb473e6fca62be215c3c3e4b3674ccd47a69a1281b571f0215b18d8c6e684af4b	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3263083	1724323889	BERACHAIN_BARTIO	80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_65693430656934306_3263083	65693430656934306	0x26cff8c46a615a557d4c94f052d717be22e96b76eab77b555260554e7d69957a	0x9321f6e31883F20B299aD541a1421D7a06DCCcAC	2024-09-20 09:10:44.324589
3263218	1724324120	BERACHAIN_BARTIO	80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000000000000000000_3263218	1000000000000000000	0xe1b113799a04e110e6494acbdfb82a0afee67a8dcc41a68cfb3bb1a599186b9b	0x9321f6e31883F20B299aD541a1421D7a06DCCcAC	2024-09-20 09:10:44.324589
3263251	1724324184	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2200000000000000000_3263251	2200000000000000000	0x00ce84800b6894e3568be992e4466d170773732ed28cbc079630764f29044012	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3263318	1724324285	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1003003003003003003_3263318	1003003003003003003	0x155e54333ddcdd6c549f2fb7bbc6c5d4c5e348f8c981893cc9e30e7edb80dc30	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3263405	1724324437	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1081081081081081081_3263405	1081081081081081081	0xdfc73144311f7631004798f6c19f7d7fe2cdf41853dc407f03a48eff92c64d81	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3266051	1724328937	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3572884500016996916_3266051	3572884500016996916	0x8bc4d27f8ce4593fc0a813fa1a64729811a7eb87ed8a9e6e7aa4eb3760254c18	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3277966	1724349234	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11334035554851972_3277966	11334035554851972	0x6f613f4e8801278ca9b2a8b8db688ae733232bdb93e8e46c3b89f95aa8ac7fb1	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3284254	1724359910	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1981981981981981981_3284254	1981981981981981981	0x6a7c99c0481ad7b714f8e12b59c526fdebf3adc9529a8bfbaec7131f45674675	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3284733	1724360727	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1033033033033033033_3284733	1033033033033033033	0x21e6cce0e0fed129c60fd8b0fff715f27ae883db1464493e5c77f02c4a22b799	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3305824	1724396443	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3586178953970548532_3305824	3586178953970548532	0x9640d6c02b328ff337d2ec6616901f6bbdc6d0bbd04fc3faa279233ad43b1d44	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3305849	1724396482	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3596049800151595216_3305849	3596049800151595216	0x0afeab5b51c8e18e64ea8d9decaa0ee6e9627097ecf41bd4e62dd2f95c6874d2	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3306185	1724397039	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11338035554851972_3306185	11338035554851972	0xcf30f8645e71c1335c3c367255a6884000877707286262ff4a9763357b3b6b37	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3324876	1724428334	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3325853243203717_3324876	3325853243203717	0x84c994ee9cafe6505614c08f410a76ba85c7105b5ffaf2411643d0135c7b17fe	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3326673	1724431374	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2266666666666666666_3326673	2266666666666666666	0xa87b743a3d3173529c6384a04e5d08febbd38bbd8d76e9ae60a398d2caf5b6ae	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3328231	1724433978	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982069520007650481_3328231	1982069520007650481	0x71fbbf39f5c905b34afa42e138afbbc5833e59fb2ff83686465ca47ac36dd504	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3337406	1724449389	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3619305614105083588_3337406	3619305614105083588	0xae3525004d0cfee8168af6c65b4e4657650c9c2d9dd24079ef8f7df39b8d022f	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3350924	1724472011	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11346035554851972_3350924	11346035554851972	0x70a6244a28c96d785eeda9a3ab1e83a27afea49e2a775bf30b02f5ea7d1daf7f	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3355196	1724479219	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11366035554851972_3355196	11366035554851972	0x2ba2e0f45f76740baed8e23fd36b9e35d74bc2efbddfac88e11eebfb2d1f14d7	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3368942	1724502474	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3327654747043786_3368942	3327654747043786	0x8ed4054874d4a2134f1dd93743e6205ad7af4777ad23769093d7d280342ba739	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3373443	1724510132	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1036036036036036036_3373443	1036036036036036036	0xe34ba761e79ba72d44e4543e437e2066ecac9e5d880539fb31b0c0c98a4966e1	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3374521	1724511970	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3621631195500432425_3374521	3621631195500432425	0xbe18800b238a4db7faddd0a4a4b278cb9fcde83352c8d5af3fcba949b0d6962b	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3374645	1724512186	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11368035554851972_3374645	11368035554851972	0x7590ad35c66fa69e620ee034a81a14bc7bc0e3d0c46de54fbde40768b40f211e	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3375911	1724514363	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3623956776895781262_3375911	3623956776895781262	0x838c4e216ad4ecd383ffbfeb0c5ab9ecaf3c91105e06a60ae900ff4eb85012b5	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3376001	1724514523	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370035554851972_3376001	11370035554851972	0x3d9089da97e98a9d6b4aa6bff5589b1d6585ff961326825201315a70572fa7e8	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3421277	1724590195	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370037469949109_3421277	11370037469949109	0x64c566ed3aaef2de55bbe736943c59dfa5d5c5355e2177ea15e903c4df1010d6	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3435834	1724614464	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3626282358291130099_3435834	3626282358291130099	0x7b518f62dd7ec495cf34039d7dd1ad79bf1e8f876f9464e7c601f11d042abf7c	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3462151	1724658439	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3329463255058483_3462151	3329463255058483	0xde54617c330a06548334020f9efadd86c50b5a1f32929e132faa7d66828d8ab3	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3469700	1724671106	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3331266714321640_3469700	3331266714321640	0x05fe1f8ef22bb0a33b26923a03a1b5776d0d24bbf480c78a939193fc3100758e	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3469733	1724671165	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333077185362032_3469733	3333077185362032	0xbdd2fb1d9c398c88b843c957c16fcf549cd28d76ac4c0c0e5b386964ddbb5bf5	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3469753	1724671197	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333363505961407_3469753	3333363505961407	0x85c33f5fe6c637f732777812bdb2bcca7b89f3c2b52563a01998de440281b375	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3475860	1724681398	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335181195792678_3475860	3335181195792678	0xe19a49285266429e3f105275d73691be293d0ef0e5354cb41886a78bdc17febb	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3475895	1724681460	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335468658546292_3475895	3335468658546292	0xa03b53a53a1b80748aab03c2d4cf4965a39e6e26ccf5db9ec3af4bd1771dc56f	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3479992	1724688341	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3742561428058571960_3479992	3742561428058571960	0x6d397db76c0cb5d9d68d7c8c767c6842ca4146089ffc2221a629b874a23db174	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3482575	1724693227	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982149766741940603_3482575	1982149766741940603	0x407e3d342b1adfd654de6b28774ee2ffc9065fe62bd696f93682e4981483e7d1	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3482606	1724693283	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1039039039039039039_3482606	1039039039039039039	0x835d956266dc02c75e28978011814e0afaba15b3f2e88d5a608a1a6e7dbfbf5e	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3492403	1724711835	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_3266666666666666666_3492403	3266666666666666666	0x0b74895b6ce5ad4775fd8241f9f7ab3b810111829ebb6ea62ff09fa5f6c479fa	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3518204	1724760873	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11770037469949109_3518204	11770037469949109	0xdff681f2ba751c2213d1d6062114a05a72088772cc1b7491875f2fc346248fa5	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3518447	1724761344	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9316666666666666666_3518447	9316666666666666666	0x8625ce80e8235f4cb114523578f0e703447b8ad08ffcef6eb3eac4def121a7c6	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3518753	1724761920	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_4600000000000000000_3518753	4600000000000000000	0xe3f4f577f5ef55b537717fb2d78c462ba7c14360a2804d4711b40bf532669b29	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3525742	1724776129	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1983607229805721441_3525742	1983607229805721441	0x8bca291e37b4cd1083c8e3173609ee5cb37e0dc33547a3e74c6127609126419e	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3526029	1724776647	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46959629732371795_3526029	46959629732371795	0x502879e9b3c0e124cd9bb04f7d4a50166bf3a8cf6928d11bdc2d8a78d1101ee9	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3534342	1724791795	BERACHAIN_BARTIO	80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000016401399243637_3534342	1000016401399243637	0x43adc4bc161c66b0d30916397506d056ccd157d6a0e82abe66ed216e4c69faab	0x9321f6e31883F20B299aD541a1421D7a06DCCcAC	2024-09-20 09:10:44.324589
3540324	1724802893	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5266666666666666666_3540324	5266666666666666666	0x0c7e320c03d63f6139a1c205b961a3a65db4800f8b04b47b96c9f3060f3c895e	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3543881	1724809601	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770037469949109_3543881	14770037469949109	0xd4bf0a4ee8a916f97a924b92baa61d2c52cb2beffc0448897ebc255ddff3e7bc	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3550575	1724822260	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1985072394236827940_3550575	1985072394236827940	0xd3ca62483eab099b346cf84c8354fa7dc1177600da40a3006a92c3b3ad029577	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3550620	1724822336	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1986532006291413843_3550620	1986532006291413843	0x919da6c509e69b681e312892cb2edf9b2908e5e5935341133591920c712f9808	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3550899	1724822894	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1987999331068788183_3550899	1987999331068788183	0x6109ff18dd35840321ed197e5c547ffe1fd94cb0c6d2525d84e7cc6ac219dfc9	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3550960	1724823008	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989461095282809351_3550960	1989461095282809351	0x52426c92380aa7a12bc149e9a54242b4f1a542bce2ad70c074783454a532295a	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3551056	1724823188	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3831644300352515005_3551056	3831644300352515005	0x4e3ac36ee92ce02f992bf24138798221b30ab62df3ce0f72455625ebb756cdae	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3551064	1724823211	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989501550509609062_3551064	1989501550509609062	0xccc1cf512c4208cab438457d4f62bfde39ddd0bddc7cd0008eb7ab7a9a580c51	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3551088	1724823247	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1990971068700326387_3551088	1990971068700326387	0xdfce421639bec0e00118ee908f0f618469d910ecf6fedc50eface0127acf03e1	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3551611	1724824236	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991203513952743144_3551611	1991203513952743144	0x31ce12c0069114fdfe56e844bc398d55ef7d89e96ef815d65aba68b223fad9e9	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3577844	1724873033	BERACHAIN_BARTIO	80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_10000000000000_3577844	10000000000000	0xa082e5b4cc7fce8063c5b86f853a8b0e0eb68700a2749345eb21202eac56b00a	0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf	2024-09-20 09:10:44.324589
3584321	1724885049	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059129129129129129_3584321	1059129129129129129	0x196fc25a3e608e994913a1180bcb2d4b9817327b87df6d79038fc09a8d0a34b8	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3592853	1724900853	BERACHAIN_BARTIO	80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_800000000000000000_3592853	800000000000000000	0xa0b6c3735669c7e7f03a6d7e5b89274b46a97faa730d2dcba8f77467584dfa86	0x8628E8B3142511B1B9D389d4ccb9F9613818e310	2024-09-20 09:10:44.324589
3603936	1724922002	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770040497126853_3603936	14770040497126853	0xb4ed9f60b93297f4b900136ba2a56a72eab4c6d409d77ae32445a024558571a6	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3605445	1724924944	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46985323132477891_3605445	46985323132477891	0xb117461e3dbebc2b03203c1ef234c5ad05cb87d7d621faf0a26eb5b238e21bb2	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3605567	1724925180	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47010944323783352_3605567	47010944323783352	0x707f49ea452cc4c6d99081443663f69967d0772469c72bea389a19085c9bfd46	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3605631	1724925311	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47036665800054783_3605631	47036665800054783	0x38134dd3da527ceff29c5f5d902ecd0f4126a4dab1b233878e1924069b8bcb92	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3607670	1724929181	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47062314988620249_3607670	47062314988620249	0xff305f392378dd59fb68876df4c2436bedbedfefc531ff5f0f17bfce74140792	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3609001	1724931700	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059157173718834037_3609001	1059157173718834037	0xbaf9d1486b8bbefb4d063bd5b2a3b402dd917d8ab2339a79f5e348c78074c398	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3610445	1724934478	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47088064571736918_3610445	47088064571736918	0x5711be62b26459794c8d3a4f9b3293f2561e7b20c96963ed2efc1a80334f553a	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3610621	1724934808	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47113741788156070_3610621	47113741788156070	0xa03cad861b2239565af157d953a44466c5ae2007e8af374574f7b33aca352aca	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3610810	1724935178	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47139519508831408_3610810	47139519508831408	0x378a090e7e832499f224e5357a4f4ab834e3771953810539255028188c2195ae	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3610870	1724935282	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47165224783731358_3610870	47165224783731358	0xb421e74cde6e0fe6b551c4576294a016305068541211b7f0582adfa844ec37f3	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3611156	1724935834	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47191030672712356_3611156	47191030672712356	0xca22ed9483bca01ed58987494a9d6034e5f0a03df39e3badac185af5d3b5de93	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3611228	1724935954	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47216764036753684_3611228	47216764036753684	0x81b0996c78bdd74a8d01c9f2fcc90088451b077b59e0c860e272554d37d53da2	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3611934	1724937300	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47242598124820931_3611934	47242598124820931	0x10ebfa3fd20b0326a74eb3a0d072a3985b3e32ec849d8d85b207ef0e34bc8043	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3611982	1724937376	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47268359608697721_3611982	47268359608697721	0xa5132e53ce5fd6cb77eea7c4050069738e0a2afcbcc7ad6e8af76d8f54d82134	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3613724	1724940678	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47294221926665443_3613724	47294221926665443	0x7112f0f161f2231dce4ce39c60ce4a2c6371c0aaf910b1f9a902b848ebbd1531	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3613770	1724940766	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47320011561105319_3613770	47320011561105319	0x6d7c4ce22590b3f17668acf6b50c471a38a3064f44f145e54d7931f6f4ec9dde	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3616823	1724946566	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47345902139821412_3616823	47345902139821412	0xc07787db3a3601d55d764a8b521d1a54967144759a2e74bf128288d07132342d	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3616856	1724946622	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47371719955585577_3616856	47371719955585577	0x8e5bd5d25c2a5ab9d171c81933931213cdeb15004447d1546814478afd844e58	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3625888	1724963558	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991302889506882725_3625888	1991302889506882725	0x0ff82a73803686eb5bc766e34cbd4accf2fdab14ef5c1fb934f978350b39d35b	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3625951	1724963672	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1992780454436311348_3625951	1992780454436311348	0xcf9e303b7fb61bd72c68932c14a595e611d43d9d5b248edb22f8585d8af93f96	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3625978	1724963715	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993014173292386164_3625978	1993014173292386164	0xd32f5ce96d86d53ac4655fa3d31f0a183522d2df81ed43b31db62f8940b68a1e	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3634646	1724979436	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47397638825931646_3634646	47397638825931646	0x3b47d46edbf24c91891c240f3bc36c73ab5229f4f7de411d8ffa53753c32060e	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3634776	1724979677	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47423484853814914_3634776	47423484853814914	0x1f2cd894bd5509bdf91f976dfb4d83e725149e6ffbbfbab0a2982d3853ca28fc	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3634914	1724979912	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47449432046706311_3634914	47449432046706311	0xe2ed6fc73f70ceecfd7e76838c73ced0afd714b6bd2ee376bdfbca8a74afc0e4	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3634927	1724979936	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47475306317537149_3634927	47475306317537149	0x69457c91f3b13be315198917c94aee1350f64f40e6069963e9d85b3a48ab8536	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3636795	1724983322	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059185056201084004_3636795	1059185056201084004	0xe92e3256d3bbae696ecf70fc1ba1995d23f07b69e3f583c98995892750068251	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3651552	1725011247	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47501281863923007_3651552	47501281863923007	0x28fd08c7a640d064fd2324082908276c2f545ab7efcc50e9b8437e87b32d6036	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3651570	1725011284	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47527184408563569_3651570	47527184408563569	0xa37b376846cfb362e6c74aff2b38f0f65d41a6f4d1b3cb5403b080e830436646	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
3687303	1725082541	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5273333333333333333_3687303	5273333333333333333	0x822f7c7fef99ccd0da134e328b07d92ed54e7235502ee5ed65b5462b27d89e6b	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3712424	1725134428	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3835215728923943577_3712424	3835215728923943577	0xb66a46b53e65ad1466fda1dc3e393b60cdcab7c6d5cf95ec4ea88ff6775fcce2	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3712459	1725134488	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771140497126853_3712459	14771140497126853	0x9acca2c408ef1d6200ca9eaf37a7bac08f40d6018e3017b540a735bbb246faee	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3738889	1725190207	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993095519297009027_3738889	1993095519297009027	0xeb26858c42960c30c0d9f4b7e04bcaf6959ddb7e0aadf873485ac47f47143e21	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3740772	1725194025	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3849486299078079181_3740772	3849486299078079181	0x4f4e5f8284c72651b0af8aa96f5476d40d17419aadabbccf569045f9957bf236	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3742488	1725197618	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1994567692123762499_3742488	1994567692123762499	0x97153358f154567332f05459f44de3093dc68cde30325561cf273029d0195e5c	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3761741	1725238135	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_40909090909090909_3761741	40909090909090909	0x1ebc3725abf177c425908bcba8d5f4207207e35c07990b91dc7ed507b2f133bc	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3763781	1725242458	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41363636363636363_3763781	41363636363636363	0xf6ff92a0a75ca6661487580fe80544b3de4bca1565584a3109e89b29de27ebfb	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3765612	1725246363	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41841818181818181_3765612	41841818181818181	0x4e938333cc3411a290533a9d3a1e6cec30fc66fce1ff0f77578a50abaef1627a	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3765785	1725246722	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_50932727272727272_3765785	50932727272727272	0xd0408d01b1f2dc0b61157c6ff6fedc09f09e1138ee9d8c4e946f87dba1a15172	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3766293	1725247864	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_51340189090909091_3766293	51340189090909091	0x21b231f0b4559ccab7964d9c312f1776fa715033365b56689468c6c6f3554501	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3766452	1725248193	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_92127444628099173_3766452	92127444628099173	0xf94c0b6a0e504b65e820a012e97f0d536485282a7b7d213291dc3569eeecc58f	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3766728	1725248773	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93036535537190082_3766728	93036535537190082	0x4f73aa738ac73a988696dfc8702cce83f2b8d52718824b129e5c90f1237d7dbc	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3766911	1725249151	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93616824242424242_3766911	93616824242424242	0x49a36d9645b3342bb704e32512be2852da26dc37139c38c454cb075292be9467	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3767108	1725249560	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_94877068531468531_3767108	94877068531468531	0x7732eabfb234c2d6f2fdffe6d00d754fe9c7e5d33b3b6f18724a6bfe0e70c90c	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3767487	1725250341	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96671563636363636_3767487	96671563636363636	0xf5a08857ef77f78c37a96b2cb036509de8da2568226fe65e6b6fea833d47da51	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3767670	1725250740	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96893459393939394_3767670	96893459393939394	0xc26718caefcc1c931dcf0571d125b82ef7cec3a695f08e8ebc48176af8a4b04e	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3767878	1725251175	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_97087618181818181_3767878	97087618181818181	0x92faeb2010d19f78ace982739840211cb6aa87fad975d58b133bd8089863751d	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3799882	1725316387	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9320000000000000000_3799882	9320000000000000000	0xfdacb51ce5af20316bdb2c8cc05639989bbce5a9524b2ede635a49123b06a9a1	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3800407	1725317423	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_103141287700534759_3800407	103141287700534759	0x65d234ce8dfc1f261a964dd43f4418909336cdb3ce0641aac6e3f3332f87a932	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3800600	1725317801	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059324468612333837_3800600	1059324468612333837	0x00c61a471009f27dc14b5cdfdc26a73bfaf70170c35f57858127a653614d0a44	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3800976	1725318540	BERACHAIN_BARTIO	80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_108522327272727272_3800976	108522327272727272	0x4c69f5e29d11c04455ffe3452e5ee42fe4c342d188bba3ce187fd59d9d859b36	0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E	2024-09-20 09:10:44.324589
3824805	1725365887	BERACHAIN_BARTIO	80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_1010000000000000_3824805	1010000000000000	0xa988ebd11f7f1f583aded65ca83c13d306ac6cd24e168d59ba2b68dc9c5830b2	0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf	2024-09-20 09:10:44.324589
3826507	1725369304	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771146551934480_3826507	14771146551934480	0xaa4dbdbb564e3864a47f2489426839e6508a8523fd848dfd8f5163f2e3917724	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3833484	1725383199	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14788606551934480_3833484	14788606551934480	0xf7cff4514522f1ab89139ebb96243123b12e4595c924bcdb03602739895a75ec	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3839169	1725394369	BERACHAIN_BARTIO	80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839169	1600000000000000000	0xac8dd139a9ea786f9e77a42f0134fbdaab032fb5b6586a53f8fa1b8b39714e09	0x8628E8B3142511B1B9D389d4ccb9F9613818e310	2024-09-20 09:10:44.324589
3839409	1725394831	BERACHAIN_BARTIO	80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839409	1600000000000000000	0x04952f50ebb279e0aefa44b47eaa7fef0c13b9e9a56a8748b1379646f07b3507	0x8628E8B3142511B1B9D389d4ccb9F9613818e310	2024-09-20 09:10:44.324589
3843581	1725402948	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_15788606551934480_3843581	15788606551934480	0x5ef8a3ff63451b2ce3a0fc35c558ea70e726f8b20e95ee1d7d51977638f4318e	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3852948	1725421061	BERACHAIN_BARTIO	80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1000000000000000000_3852948	1000000000000000000	0x54089a43e5748eedf23cc4270db9601f41fff772ea86ea4a4469203c814ea1b6	0x8628E8B3142511B1B9D389d4ccb9F9613818e310	2024-09-20 09:10:44.324589
3857338	1725429613	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4082044438612962902_3857338	4082044438612962902	0x8819d716fcf8bb91352e9ec800641b99aa28947646fd5d6c350b4e16faf0bebf	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3857398	1725429720	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4547160717682730344_3857398	4547160717682730344	0xb4c334fd900989642f0aa3e9bbe4ab99b6a22525d2fd29720adf5b96783e3ac7	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3857518	1725429955	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7273333333333333333_3857518	7273333333333333333	0x92351d98a13e44c3e2f118f157e3ecfd0d161c0973ec953b8b5773a51fb5c3f6	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3857628	1725430168	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16188606551934480_3857628	16188606551934480	0xf21781d8c216066498949d82d331a3f92ab68fc097966d058184304c02e0b94b	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3871891	1725458338	BERACHAIN_BARTIO	80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_2010000000000000_3871891	2010000000000000	0x3c941771b273cd50d1b69efa24408884880819d3f74216d2475c57c7d875a604	0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf	2024-09-20 09:10:44.324589
3876975	1725468448	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16190606551934480_3876975	16190606551934480	0xcd80cd257c4d4ec0163a47a4618f321e651a98d6198466d7c0cdf5f2ef1b9a29	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3886260	1725486615	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7280000000000000000_3886260	7280000000000000000	0x0932cc50112969ebbe093a7ed180e856a029768737cb655b4d4de7a9faadb916	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3886500	1725487092	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13725490196078431_3886500	13725490196078431	0x2f936d8607118afb1616d60387282b49f22c252c223c849c098c1f0aed7382ba	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3887162	1725488461	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13823529411764705_3887162	13823529411764705	0xb15c952dcfac608cf3489e99cfc198163d98b0b4ab82f557f36438e2a449474e	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3892395	1725499209	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16200606551934480_3892395	16200606551934480	0x2b04d3483f2a4fea62bae14a82cefd7a61d51488ec67e66073c4b7b6b883b302	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3895532	1725505606	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13848411764705882_3895532	13848411764705882	0x155695dee86fb47356455c8a3bda64647d1aaae8091b07a476c52ac707ba180b	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3896765	1725508123	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_11557947050515121_3896765	11557947050515121	0x2e429b58dc84d4a152963ddba3142b45e901f6c52cfc73a018728d8fbb88ac9b	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3897850	1725510292	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9754404791197783_3897850	9754404791197783	0x7e2bfcba64c3370714d9931f1b3b7cd65afba5719f93620e32be8646dafc1cdb	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3898389	1725511392	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9906578704241261_3898389	9906578704241261	0xac64044854b0286fbc03f1531dc5cb1189b8f70e5a2f1b6b536500b0906a4157	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3924648	1725565151	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4593672345589707088_3924648	4593672345589707088	0x4d0a86b3e88b8e890b273d9d2cbfc8d8a2cd15a723f6a547250b36d2cb7fd606	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3932783	1725581279	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9004923622491555_3932783	9004923622491555	0xf87a2e961f892e70532d8d8f84be4d0fbcf4a4f3715395c17b14ceb69cd49f21	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3947210	1725610099	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16202606551934480_3947210	16202606551934480	0x99d82c882d36f66e11170906bcc36b0663e1752651b56ba23f9db56628a95988	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3954766	1725625175	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222606551934480_3954766	16222606551934480	0x53b8dc9fead4f2229a59957e65eb5de4c588ff59a74d96329f368058c6a716c1	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3954794	1725625217	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4616928159543195460_3954794	4616928159543195460	0xd61c41ede7d2cb158807de3bd7e2a40818674db9fb3d14b606ba5f7ff06106c4	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3954821	1725625269	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9353333333333333333_3954821	9353333333333333333	0x10d9e2035c737343b78491e516aac1eca120e5cbb2755531e3fefb8393bb9dbd	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3954842	1725625306	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7313333333333333333_3954842	7313333333333333333	0x3b6646e9da8317bd2281eaad67a77951a556e20a9bdd628d5657b62971017469	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3958498	1725632814	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222608542864585_3958498	16222608542864585	0x002540ae837fba1fbb73939b966c7a9ac3fd92eda45d976cee10065be2009e66	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
3967139	1725650190	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7380000000000000000_3967139	7380000000000000000	0x41daaea741d8cc9515c04b9d3259956e507f372f5b7c8f461745fba9201744e7	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
3972465	1725660683	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4619253740938544297_3972465	4619253740938544297	0xf6c56b98fea46b7298db76f888641121e5af539c501d9eae6ee90301ce42d4e2	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3972475	1725660712	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621579322333893134_3972475	4621579322333893134	0x9703b00fff84ef56ba676a379e657ba1cbd164c34b12508b1c4d4f67c1f8eb95	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
3972500	1725660759	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9360000000000000000_3972500	9360000000000000000	0x68a4c5fc79b595a02a79f3671eb577f3cd083e19b7ab4ec72428bd8c4ebef0c0	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
3972509	1725660775	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995022237578307954_3972509	1995022237578307954	0xe9d69405bd3f3761bb0dc2ff8374a3554ad1ac4ec67db8829fadc15b5bd8c481	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
3972774	1725661301	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9015875556627018_3972774	9015875556627018	0x1d99c9fcc828a7dab9fde3ced914ce4e4afb03e2bd8ad0166d3d263a9a5f207e	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
3979803	1725674956	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059467410355649862_3979803	1059467410355649862	0x57d4b1e74f5e8f2470d7782b4325409b71240b1280b398258f64b174c226f8a3	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
3986050	1725687276	BERACHAIN_BARTIO	80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2982456140350877_3986050	2982456140350877	0x8f5538f9190954286304472933c866b0da4f5b7c988fa55d243f46cc5fa82730	0xB3281C2e3bC254d491d5eEf55835d02396673764	2024-09-20 09:10:44.324589
4000976	1725717807	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059767710655950163_4000976	1059767710655950163	0x22f4366bce2889a6c7e9c99d09f894912967ace0f72ac23e01e21bb0504e9690	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
4009206	1725734673	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621983076994692971_4009206	4621983076994692971	0x6c1b2fdc25d53de939739f44d58fc4beec8b758b714e98cabf32d831a6aaba8d	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
4011739	1725739776	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4622215635134227855_4011739	4622215635134227855	0x4ef086e9306f8dac81035b724ed954930bf7908e0ad0d2aca89cea3776110e70	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
4011873	1725740036	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222808542864585_4011873	16222808542864585	0xb7be32ec918fe9128ba2835dfd9a166a6f8f0f8e95f5c0c7e17b56705de673df	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4011892	1725740068	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16223148542864585_4011892	16223148542864585	0xeb371a0190390d9aebbe6b07230358d3b18553b389e49200a330ef2dc73e43a9	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4014964	1725746176	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8677594690784407_4014964	8677594690784407	0x90c52d327fc2adebab2a32334302597f08318d38cfcedef94da8f1b5ab304045	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
4015002	1725746259	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4626866797924925529_4015002	4626866797924925529	0x3e026d8348ae04abd70506146da47bb0efd58b3ecd8f57257b04855a53253d19	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
4041757	1725799177	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9426666666666666666_4041757	9426666666666666666	0xcca6463991699ad41a8c29d129b4e28b3a291a1b9e754ab277d4d3039d4934b1	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
4041789	1725799243	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7446666666666666666_4041789	7446666666666666666	0x3c66b2c45494bb64e1b91b0b53d05fa5510c9fd4e6495cf31bac255a861167de	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
4074136	1725863753	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16241148542864585_4074136	16241148542864585	0x350413ca6e51b1ba5d03a6c9bace421d6fcc031dbccb8e973e79f7f52e3e54d8	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4089893	1725897528	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059872269964387538_4089893	1059872269964387538	0x250459f80a36f86f7edef6982c87c8bc15a15b48b7858b46430040b66bbc20b4	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
4098893	1725916460	BERACHAIN_BARTIO	80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000746328406542907_4098893	1000746328406542907	0xa3ad12fea4b08ba1a43d9b7f8e0bc265aff5d93322a4c25daa3403b6a4f1f45c	0x9321f6e31883F20B299aD541a1421D7a06DCCcAC	2024-09-20 09:10:44.324589
4100409	1725919580	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16341148542864585_4100409	16341148542864585	0x06bd7a5908f2b9053cc93ed0dbd8b445606ac3e18f33b36f6bfb600e1d399a0f	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4106515	1725931799	BERACHAIN_BARTIO	80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8467667874725460_4106515	8467667874725460	0x3dee443a8109fbd57ceaee0f03d827b73c4a0473e8149ac59e2138d552b56e99	0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794	2024-09-20 09:10:44.324589
4111432	1725941630	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7453333333333333333_4111432	7453333333333333333	0x321179f480c6176c0e936c41c0a763437134caa5af373615236a5d39f91e6eed	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
4118181	1725955314	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15426666666666666666_4118181	15426666666666666666	0xb32842d825c541c8a370efc7ee3490216ef3baf1f02197a016d507196d31e8fc	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
4126941	1725973604	BERACHAIN_BARTIO	80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_12010000000000000_4126941	12010000000000000	0x81e8e1c7f551e616e1a37eac96ce56f48c90d37f08f598901dd6439e4e8d61bc	0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf	2024-09-20 09:10:44.324589
4141574	1726003176	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16342148542864585_4141574	16342148542864585	0xc33dcfbd95d2598cfc4f95104931dac38107fdc066c4bd49bf0de6d57dc0a423	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4141586	1726003208	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629192379320274367_4141586	4629192379320274367	0xb715aa740c79365d6795c83863fef593143ef58cebd787487b07f0138ffce812	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
4146684	1726013594	BERACHAIN_BARTIO	80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2945161290322580_4146684	2945161290322580	0x20bf053b03be7054b9b8b707b75d2a75aac16ee4ad730dfb3e38678bec4c987f	0xB3281C2e3bC254d491d5eEf55835d02396673764	2024-09-20 09:10:44.324589
4152808	1726025522	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15493333333333333333_4152808	15493333333333333333	0x46faf5b7962c1d483ab3e565e53d3e456bfba94a2f88eee3f2a193f73c28597b	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
4195369	1726109810	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059900876861562692_4195369	1059900876861562692	0xabbf3ed3c144c20c4aa1e8d0c92f9c09e4e7d824d4e16abfa9e62147d50e7f87	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
4217694	1726156088	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995042613934680356_4217694	1995042613934680356	0xb12c2c8082d43609756c990f5301460d6d532ac3d550221c435349ce70cd555a	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
4261883	1726251369	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344148542864585_4261883	16344148542864585	0x9829696c92f864a47f6bb55d4e0eb9cb41cda3b9b959b038b4f54967e2c40ae6	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4303538	1726343091	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059929484530863497_4303538	1059929484530863497	0xcb6acbb765ea37a544d4c1ff33e6c59475e8593d88b9fd49f9be07a2bbe63110	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
4349050	1726440530	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344348542864585_4349050	16344348542864585	0xc4f7b0c7849afdf5641a1206a9a9b31c0c60cdb1fac5d3c14f002a55891acbb3	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4349542	1726441531	BERACHAIN_BARTIO	80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_8120000000000000000_4349542	8120000000000000000	0xa93a5a1d45b047724c1d308935e169c6171fbabc43d6b0eeb92e759955c86e3a	0xe0941F720B65d3d924FdEF58597da9cBb28f48a6	2024-09-20 09:10:44.324589
4349568	1726441585	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16444348542864585_4349568	16444348542864585	0xfa523204df4d2177840b906b167ed33703f8c365d41119e0199d72fd501a6f10	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4349584	1726441629	BERACHAIN_BARTIO	80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15826666666666666666_4349584	15826666666666666666	0x9d5c5dd0d3b5feb8ddb19931e024f185ab72c2a907f0f44fb4bd3ad7a651c87b	0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8	2024-09-20 09:10:44.324589
4437743	1726625612	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_0_4437743	0	0xb604a16d781a5876f4c94f61d9e3a20f5f461368dfd4e6a367ab9f2b3ed8a626	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4438319	1726626749	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_16666666666666666_4438319	16666666666666666	0x8b4a93d0afc3a3b06aceaa01bfabe7bd3ce44e0757ff4f4b5bfed3d97f37409e	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4439849	1726629764	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18333333333333333_4439849	18333333333333333	0xd4ac570c2398476aa14b1a9f060fa30c721e8f1e2cd699a37489c865d13213bd	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4455659	1726661438	BERACHAIN_BARTIO	80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629424937459809250_4455659	4629424937459809250	0xf07d01a2d020c2ac82065a3fdeda6315bfbae4356ff0f8d70e1b1c5f47d85358	0xE55A1ff57C48b02a788711f9412Ca316686F9528	2024-09-20 09:10:44.324589
4468576	1726687332	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361299435028248_4468576	18361299435028248	0xfa73db29f076d4950fe5d210e1bcc2823c3c79959989cd25b5e11f5227e69a3c	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4478283	1726705953	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361341227459175_4478283	18361341227459175	0x7be20c57f11f3376363532046e3e8e7ebf568cb94b246a4a9a9692fdedfd4d56	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4480026	1726709283	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361543711787013_4480026	18361543711787013	0xe5bfaa42138e390f7f3bb69979af22860384c446df86d95322341c008c218ac8	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4480669	1726710512	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361611206562959_4480669	18361611206562959	0x706cadc003642c90b742d5726056f79d126a36abdda808d50b475d447111556f	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4481074	1726711271	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362029130872223_4481074	18362029130872223	0x891b9892f00d6d30b9ec328a1a0fe63587ddfe8374508ae4a65128792d9d7845	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4481096	1726711336	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362299527900317_4481096	18362299527900317	0x37225d878a2c976441b12ed33e90a01ea0676a7af824619b4c453fc3b6ab8854	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4497856	1726743485	BERACHAIN_BARTIO	80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47553188339426841_4497856	47553188339426841	0xb095ab7df4d385cbe027e1b066bcd2a5d6f6b24c6ca90576a44c8245e2e88c0a	0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79	2024-09-20 09:10:44.324589
4498940	1726745583	BERACHAIN_BARTIO	80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995108864304106744_4498940	1995108864304106744	0xc0c1450546771b25af51f87668971d7a3d50adf4b719ff7bb5d69599d8b86a27	0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804	2024-09-20 09:10:44.324589
4498959	1726745619	BERACHAIN_BARTIO	80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1060043834915224133_4498959	1060043834915224133	0x853f079484a28dff0e64c07493f6de8d6d0d9e00a95df738d96085d0f8cd2d16	0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e	2024-09-20 09:10:44.324589
4504762	1726756697	BERACHAIN_BARTIO	80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16464348542864585_4504762	16464348542864585	0x71dea112b33f17e980e0552118a0c04b53e2e2229481d4b1ba94294eadaa9506	0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f	2024-09-20 09:10:44.324589
4517102	1726780605	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34722927869101978_4517102	34722927869101978	0x45e92462fde8e15e2220373bfccf60681eedfae79333061f68c5be4849834ae1	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4519221	1726784678	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809437248297028_4519221	34809437248297028	0xb4c4e69a32e1a5b938afedcbb9dbe31f3b89c9edf613ea137cd10b7e40d4b6b1	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4519919	1726786005	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809747286473538_4519919	34809747286473538	0x9d885c410dcf36254a8d0fcdf202a62b0ed8a18f589cefc49037a6626fe6d15c	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4520131	1726786425	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809812568306010_4520131	34809812568306010	0xc3b2ef6db4107a4a08915b45c36ff482c5ad9bc7099ff13e6baec4abd66847c2	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4520570	1726787224	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810246702597499_4520570	34810246702597499	0x0822e68de76bfa7b123a8809715c9f57ca859612b1c114bc3e7affe84f21b2e3	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4520734	1726787515	BERACHAIN_BARTIO	80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810804933003967_4520734	34810804933003967	0x2163ed213accd5b8c261552d3bd3e7d324f15201fb47d631ade77b738b66a93c	0x55E58ea273c0d962E8D56BB7E3F1756842128154	2024-09-20 09:10:44.324589
4540764	1726825718	BERACHAIN_BARTIO	80084_0xD33c9b08BCa676E2d5E496A00bB00FaBbB4F7D55_1000000000000000000_4540764	1000000000000000000	0x18edb2e2d398158cdda968a7faa58a2d68b0fba2503e67d03e76e73d2ce43caf	0xD33c9b08BCa676E2d5E496A00bB00FaBbB4F7D55	2024-09-20 09:55:31.823132
\.


--
-- Data for Name: chain_metadata; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chain_metadata (chain_id, start_block, end_block, block_height, first_event_block_number, latest_processed_block, num_events_processed, is_hyper_sync, num_batches_fetched, latest_fetched_block_number, timestamp_caught_up_to_head_or_endblock) FROM stdin;
80084	0	\N	4540992	1035181	4540992	393	t	11	4540992	2024-09-20 09:55:32.09+00
\.


--
-- Data for Name: dynamic_contract_registry; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dynamic_contract_registry (chain_id, event_id, block_timestamp, contract_address, contract_type) FROM stdin;
\.


--
-- Data for Name: end_of_block_range_scanned_data; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.end_of_block_range_scanned_data (chain_id, block_timestamp, block_number, block_hash) FROM stdin;
80084	1726823437	4539530	0xa758c46f168f6c3ea93a3d892cae235bf3d58e668f83041a1d3c5079a6052641
80084	1726823440	4539531	0xebb87bd23dc3dd8b31514d64282ba0ffaeca3c32f6a2c7fbf5c255e50bb03280
80084	1726823443	4539532	0xb37caae6ec8b60dc39f6215b21c9390a91161b6ee28789cf63774dcc9ef8e2bf
80084	1726823447	4539533	0x68059ba3aa7fffeb5a553aeca124d2d9c50f09d4e7bb1d7f0272a61def15637d
80084	1726823448	4539534	0x21e8370967145a76340aae3a2862fcd2ff39013b192323750b6e017b123f682f
80084	1726823450	4539535	0xc057bd76fb750d7f0b5b462d3836b12e22d894757ad708ac80cc723a4242c43b
80084	1726823451	4539536	0x5d0559ad25b745f977635ed558b5fa37489a0adecdbed6b556dd5e1b715ae6a2
80084	1726823453	4539537	0xd53437c8b333dce59710318f8e6598c08bce4c4aa999f5260b2db6594a4ffe57
80084	1726823458	4539538	0x85ec1934fe19dfbb86bf3548e0ba7601446180eb48b2ca81abf79d42064d8741
80084	1726823460	4539539	0xb16ba9713f5aedb7fe2e75360d859d70610f0731d70d2f8485214de901901d88
80084	1726823461	4539540	0x7a4666b6bdc1a6c349fb9c61828e90434840ed8168644d653e57043b76e580c2
80084	1726823462	4539541	0x7456a0fd37fb9329ea1ae1803c2b4da2154df4fc0b6f1f16b1de6d6999fb5849
80084	1726823463	4539542	0xd7b6727718b6bda586488ba2a4333dbe98400be3c124c7c493caca8695690d00
80084	1726823465	4539543	0x0ced0444abfa02e0b6d31e33c9b9f6e960ddb73654be812405e10236459176a4
80084	1726823466	4539544	0xcccbf983632ae61e52193d67f22400ed2a6f9462f68a560afd90ba5c54e3e623
80084	1726823467	4539545	0x18451a7bc031cc007901bfdbdb788d3f3512721f5a7f766e6d4e5dec74f64ba2
80084	1726823471	4539546	0xfdc1a49c2d000c483bcc2be253f3f41a18e5c27ed883ecd22e63346eb50878d7
80084	1726823474	4539547	0x5dbbcee1e039cd114ad66fc2a7abbe5e8009b4b24a935dd189a1234f162ebb85
80084	1726823476	4539548	0x6b82bed456e68a52c212f16546fa746daa40cc5767c4eb585276c5673f8b8f4b
80084	1726823477	4539549	0xe72baee4e4f085f15e78f26889a70f58ba1d8af43d99fd59a3019f21a351c20d
80084	1726823479	4539550	0x0c4525b34ef2cbcbdef67a49b00ec62026ed8ddb21ef64147c1e0a50fb647355
80084	1726823480	4539551	0xc31dd15ef1c8630d0460ffdc2061737def64fb26997c06d88d6a89868cfcfae3
80084	1726823482	4539552	0x08ae50e034ca23a9cf349bd9c021d8ccb7b28af9ca1a55a27a1a41c6cc448934
80084	1726823483	4539553	0xd87b185416c040c0573c72a055c77de8251a8f9e139d2c5102195bfb483ab971
80084	1726823485	4539554	0x614faaffb0a27c9162feaa39a17a3787ca23d77ff841b683545f2fcb13d0007e
80084	1726823486	4539555	0x3aa44169d502c16e5a36e5d7a1fcf4b6adbb49d3f0b51cd85b61c90025c79c2a
80084	1726823487	4539556	0x9e55a084308965b486c6410354fb8d3d680707ffe2dd050962d9ecc4eab6bdde
80084	1726823488	4539557	0x8c5707672830b655cf72b7e9eafe92e570c99505a880a7236c594863fb699595
80084	1726823490	4539558	0x34d6ed55815212c3efa805d58bad9d4cfff3ec62d2152308e4d7b7a1a5b17624
80084	1726823492	4539559	0xb1b4750ce7eee1400bd2689eec144904dabf7fac2d43b6102b99cfb41651f924
80084	1726823493	4539560	0xe86e2ac50d6f93c7a681e0dc9753404a50a561c77a696a93e44a85a616e252b3
80084	1726823495	4539561	0xbc9b937b5eb50cc631a90d421da579ca72f3f3273c13c6cbc040b4f2d35eb459
80084	1726823496	4539562	0xc8d9745c1c91daa17642d5d9acd09871fc05d394187d0a2f85825d6ea217bb7b
80084	1726823498	4539563	0x4a89671a169b3cc3606592f90bbc79c9221b9d7a4c83e310f07961fc08dd20b8
80084	1726823500	4539564	0xe9425d1a8a7d87bf4be380b35fc5badf3af86521f1cc3f43436dd3ae9b0f1436
80084	1726823501	4539565	0x0b2a510f4cd760e54132a03455b54a179b5d2f0fb70285da967cda5cfc288d52
80084	1726823503	4539566	0xcc2023d34346bf8879912cac4e6d8d42d7d3d1ff82db4761861b1de5fc5621ba
80084	1726823504	4539567	0xb1d6e31c01af07fe7ecf7add4bcf00302b7478e04c24431aee1786d3b8f34671
80084	1726823506	4539568	0x40d0427dd27e8f5d3dcc7af1e2141871c6303a705deb96be2647e74bbc97258f
80084	1726823507	4539569	0xc99160d9a6415caed11a28450f263bfa4a4916ccd56cad4f9cf12d962711de90
80084	1726823509	4539570	0x0b236bbf015aef0ec15edc3ee8e6148087f4564466d661df8db0f874a0b73f17
80084	1726823511	4539571	0xc6336f94c4217ca6321a9bd651330f5000c7bf76969ef175b8396e31e053cc50
80084	1726823514	4539572	0x823636c07556cea67a1fd62229844e9ed7143f80c21fd84cf5da1aa4b6c93920
80084	1726823516	4539573	0x2ba286e2c17763942d6986593cd79732b033fb1a9ead7fbbe10fb2843d70fad9
80084	1726823518	4539574	0x621889eb4fce62015a9535ae29af07d99d168d7f9be679a420a9b11fe2e834ae
80084	1726823521	4539575	0xd1f26a15f729753582ca2d5daea09e28c55738518256502818535f341decdc1e
80084	1726823523	4539576	0x6967c182130b67c77758dce3cb7bc335eee554d9b1efcd001adb6c970410205a
80084	1726823525	4539577	0xc1d6a01789deaaba8fd66039b6e90a2dd76d5a6cba36c7e40cc1bef4fe49a1e2
80084	1726823526	4539578	0x53b876a7434ac008f12f2c5c22945ce3e074af79a342ed1a63a720bec969a8da
80084	1726823527	4539579	0x69c926a0efff2e109fb41b619f87df1689bb3753fd3c7c4cff14b1c672f2781a
80084	1726823529	4539580	0xe517a6012b15c2aa41fda4079cd9f9ec4bf6142a3ed999dc2857847f03a0258a
80084	1726823530	4539581	0xd4c1489c8549acbbc11ea695796a8aed4eb37269b89663cab0a0ea33dd45d5da
80084	1726823533	4539582	0x4f7c1a523ac4a77073e14ecc92fae0cc3f989b6c4533898dcb7a3c67ae54996a
80084	1726823534	4539583	0x7a6f91aee8faa699ef370515bb3fafca12bef5729127eec5a54e576cf042876f
80084	1726823535	4539584	0x0cf482b842862e77e35ac845a8ca6ce6dcd0a7f09735797bc3d7c2ebc5b64fea
80084	1726823536	4539585	0xc941cd2d63185bff5466f5d158801d16702bc51d38edd81989d152a2d5de255f
80084	1726823537	4539586	0x9a893a1c312e2e0aecafa536b706e256a4b7b2c2241c8d148de7b2e9610e7e53
80084	1726823538	4539587	0x1ed4c5b17caf0805682f34d883aad087207947689e6975b2df098d59e820dec7
80084	1726823540	4539588	0xc621d9b08799fee59925d669ccd75a20286926778061e71e2ea35eace347be99
80084	1726823543	4539589	0x750af9dc162281abfa5e9431dea209be6808cfaf9377c1429c455dcaf9c3864a
80084	1726823544	4539590	0xdc2a56ec1b0ea2ff63809f518a4cb37d4f85a2108e46ae813581ea86a10643d9
80084	1726823545	4539591	0x499e7e06d02df5ee9af75e6ee6a73602c9d214fcc616d6f9229c8293127195b2
80084	1726823547	4539592	0x001b70993d292775c36e313dd3d669d9410cef82db45a6bfeb7b3a3b1bb456c0
80084	1726823548	4539593	0x5cf0e082b24bb972d909a6f0f173ea0a83cff17d21a23fbc30f6a55e97682bd4
80084	1726823551	4539594	0x46c73b15463b6004d7f919321f8e96666bb78b30fc4a3a93f30f22fe306f823d
80084	1726823552	4539595	0x588ae80cfc5c838ce49ff021927dd0ecc9f160ad3ee1ecfe2e19f75f4418d29a
80084	1726823553	4539596	0x212ffdef78c71b8ab90eea49acf811adcb815f51588963c98b1bd5f19070748d
80084	1726823554	4539597	0x84251e3f723115c65c67f7d2195e8ee0eb763169a8155bc819d1ef36b7f2c995
80084	1726823555	4539598	0xd1d83b6e3d6f05ebe6ad080fe6c3f481d6b093adea42396f7e011c0bdb682584
80084	1726823557	4539599	0x2a6d2cfec3e75ffab7772c868077cd08a57ac758a0e35cb7918af6806e57eb64
80084	1726823558	4539600	0x8758f986e0a0941640af659df68e89f6348c5df42839d1077e3ad37bf1c1cf78
80084	1726823560	4539601	0x96a6094a8e80720903ad88149d46fdcc708030fd423de1d9ff4651692d7f45a3
80084	1726823561	4539602	0x6e12816d6000be376799a4f77f96ea6ec02ce09bc727b27c50c2c23ca2948c83
80084	1726823562	4539603	0xbaa1874dce63c6ead88ddbbf02f63edc51d244425bb793d9eae8ef6ee9cdfedf
80084	1726823566	4539604	0x90c7cd9a35b8f049d021c76d290eec8bea44826a732243bb1baedaece766579f
80084	1726823569	4539605	0x85f63dc6df930159a4317e040851ace7b266a8c4fb60cec9edfae2e3c050acc9
80084	1726823573	4539607	0xc736963309172fd3454908c50aed1d6e51f28f92fad3088198056c14cd291b94
80084	1726823575	4539609	0x2496e2fa7a6ac57743a2d8cd44d358b3e514e4a02d846aa20ed2131df4b5568a
80084	1726823577	4539610	0x29a971bab1981fbc16ec761a0bc584b378ce2adde14d5d86e9ae6138299dee0d
80084	1726823583	4539615	0x4ea6740b7f9b5145dd2e4a74254e96252c2cdefb2b16de48ea15aaf1b07907a8
80084	1726823584	4539616	0x0478ed6a54b9c12030f41ced02ee430a3310cae623cdc3426732b6b24cdc9f36
80084	1726823586	4539617	0x6e74ea3877db11778524939677f9f13c47a5e2796b8ad72bcafbfe6006a9cd62
80084	1726823587	4539618	0x893750a0b86cc7fcdffd404e2617fb7ce7779e4c2e09b71e3bbf62174c1d5f7e
80084	1726823627	4539636	0xbfbad5570ebb4d5b0180cbc1ef167e60dc2273d08da5f74048be73feaa45fe27
80084	1726823630	4539639	0xfb9c17811fb420aba0c954453de5644b1de8df70cbc34e2c278af1960b58a497
80084	1726823631	4539640	0x281c3569341245956cc0fe4f986d4f97b5f99f6bdea4b1640b0d76f48737b27f
80084	1726823632	4539641	0xe28a1892017113004978d346bca89de6b21a9fab31d0ff1ddc9613b37a7d7151
80084	1726823636	4539645	0xeb914ddd2d231a9496ba6e0c3f0ab9baf0ee0bf68b67f93fdda9e01f779dc2f1
80084	1726823637	4539646	0x2ce5ceb2edaab4763c921e919e56d17c77c0e357121e999236c01678112580ad
80084	1726823640	4539647	0xc525b9380ca0c31cee3b32741d6e4d361290fdaaaafd9da8fec8cb887a54d858
80084	1726823642	4539648	0xe3b7943187aa7b1c8df58fab2c117bc03aaca2a99f08806b3a59f4b98ee9f652
80084	1726823643	4539649	0x6775811af865c37b7802f07ba1d4ffeea5221d0b42f3c97fecd9b59b3087cd6c
80084	1726823644	4539650	0x32560e2753dd34a12dd85233713da826475b1d57e11ab40c4031315ab86f8025
80084	1726823648	4539652	0xae166b1f5dad41ac8b2c341e395fe435f1a255c6e1b19e0ef2896723d5642172
80084	1726823649	4539653	0x8d2793a4a1a912cc8584dc8d908f7b1eabf9b4bb2c14a281b3739c086798b2e0
80084	1726823650	4539654	0x6af943b792bd613108688d9cdaf2c3330612bdd5a3837e6d59bf342dae3e34f0
80084	1726823662	4539659	0x4ee7893bce46dae6c24594c637753ec0fa1b69369ad706f6f26c1456ac8c7892
80084	1726823663	4539660	0x3c8e7e25bffbeb520f61c5c8676d4165b7a1c115035cb937a803a8bae2a700e2
80084	1726823665	4539661	0xf8b92c85e252e51b52ab88e24c304e862fcaf84bcf90964910cc39c5070fdac5
80084	1726823666	4539662	0x65e883c26742f2b3566738fcdf61aba397165742e258d9908ab0a4348168f5ed
80084	1726823668	4539663	0x417e178cc4c66627f818e68624354a65670fbb80d70f5c0d80b48a2561b595af
80084	1726823673	4539664	0x727510f8204d92726eef5b220d80ec91828046cb4f9986852dcfd19308f8c465
80084	1726823675	4539665	0xb0b69c7b02f9d5378a13d3a6f0b7bee2858a081609ca92a01ccbd449320c207b
80084	1726823571	4539606	0x18f60361149e26fdfc00401bf3b13aca8885f9bf557e762560a8272ced148675
80084	1726823574	4539608	0x98668f97ca7726a868457faf1819016a22f7cff2d567f7080d26c291e9465143
80084	1726823578	4539611	0xa7bdbe6afe0818071b2289fbbf966b1e3c815eac4c92d70594d9d081cc9cc1c3
80084	1726823579	4539612	0xcfe725348bbfd0df8ea51adf5b9892cf0866b23347af8a2cf1b9c7abc296f90c
80084	1726823581	4539613	0xd3d0037cbf3d34714b75250b57c701bdaf470d6e9b0cf6b4d2a33bf8f6b4cd3a
80084	1726823582	4539614	0xad1bbb9914a7a3a7a95f0c26594fcaf0b35159eb3861b194afbf9346bc63fce2
80084	1726823588	4539619	0xf5c8f06a44a4603cd2bdb5d551ea928a140ae63b9d24f1a774909816f5611eeb
80084	1726823589	4539620	0xcd04182d9f05d0d69b210b4ebb10ff15fdaa7c741f317f4fe8f752433bcf88b7
80084	1726823591	4539621	0x8f80857cd7fb1d7851ffec72b7cf1668d3a66aec5f0574ed63fbada7f3b68f4a
80084	1726823592	4539622	0x7bb1d41679ee8019ae56495f263ce2b638f64ec7ab3c8fe025a3acbc26f11e6d
80084	1726823594	4539623	0xa4f2c80194197f57594887ebafc2a14f020c8aad13637905e047b443c47c8901
80084	1726823595	4539624	0x5374c14e0d367b21bb7dfddb7f60fc299efa96174ec212149bdfbe8523d473e9
80084	1726823597	4539625	0x4e53660e7858bd6c61ce414cf6fd424bda2f1d18ef6cae7fa9d29397a5312c81
80084	1726823598	4539626	0x7fe6022702ae1bc6b38724d8b508b37423f80d332a9d753cd26081e0404174bd
80084	1726823602	4539627	0x434cbc5d1a65591e682d9f3cf70c767eae55d893952eaaf3154b6f5285e0ed37
80084	1726823603	4539628	0x21ef48fbae77034589a2e126fb3593f29f85491e41a3c8ca002cc2d0a284c69f
80084	1726823604	4539629	0x707c851a174f57f26a653b9beb6fb7b78e5b1d976e741bd6d56b57b68fff614e
80084	1726823606	4539630	0x8935fde132d7e8be78596252f78eabe608abc2649cec97cd58aef042c87650ba
80084	1726823609	4539631	0x96d2d22740ebcadeb80d64b319287b32fd6feee8fdb9ade532e746ffe20ae697
80084	1726823611	4539632	0xa552172c79cd5002c50bd3e3c32217811ed9d71b7fb99493ff5fd914e8993c19
80084	1726823613	4539633	0x2b4a72f56fad213d1088c7b6acdc4a5bc1c081ce5fe9f1ceae803ecfecd73917
80084	1726823614	4539634	0xc5e9bf57a332c646dff1d5948f8fe274685ad8ca316858a827a74edf88d167e0
80084	1726823618	4539635	0x287870485ee3ebfedccd63b36351c69e89b5ecfcc7a985a7feaa13e4957730a2
80084	1726823628	4539637	0x2e86b88759311c0eff279654af0c7ea6fa65bfc5999826c2311c92adccb6a646
80084	1726823629	4539638	0x8716035536661ae0ecc74d208da98bbb0ef63400aefaf7270c16052b23a581e2
80084	1726823633	4539642	0x0138f6fc45a9493c737313cf6e0251b2bbd1c3ef3d9fcdd1001ac80179c5e8d2
80084	1726823634	4539643	0x9ffa8f24e57f898aaf99703c49d31501097d853664c2c83eda4888ac92ad0651
80084	1726823635	4539644	0x51e8f7bfd31e550f911f8e658325354609f21513ec8fa60499c8270807ce1ab0
80084	1726823647	4539651	0x7cb3e5d21a720c67800e2aae99299b9ed50eeff639250ab779abc991ce55f3be
80084	1726823651	4539655	0xffe696baa2dae35d1979eb8205f10563ea3c9406c85aab3755aacb07907d1a3b
80084	1726823653	4539656	0x7a9f4dc0f794b508b2e4e1e151ca9de2cd9686ee6e999a8d801a6ab2622c95ae
80084	1726823654	4539657	0x381e5897762014d227a8d06ceaf1db74a544ad04689a685fb99cc128862aecfd
80084	1726823658	4539658	0x8b5113d39f3fc9419833948a57565a6fb8f1943f97001f193ed7cf68c5cd3c5d
80084	1726823676	4539666	0xd616dd3841e8e7db3b747383074511e338628d8fde8492015d2d047835189bcb
80084	1726823677	4539667	0x4fddbed88d1395b5dbe28d6374067cac61809e5c0296b1bf40adcc4d7b95337b
80084	1726823679	4539668	0x5a356cbbe626ffd0c10c81f7159d73925c1d426fb02fd51bc32f7aafcfdce875
80084	1726823680	4539669	0xd6741e94d3e141cd55e8f5fb7f9e5a40df099739dbfe7962c5e0d65f981a8712
80084	1726823681	4539670	0x542f01154b40519e3de277295e08532cbf1bd60383f585c249891b35ace8a1e5
80084	1726823683	4539671	0xfc8564b0ae91cb069c39fd4036d75c4f5df0699bddad334917d3cacdf7264a57
80084	1726823685	4539672	0xa80cebfd7e10ed7e0b96c71cab0ed7c58ad23391fdac24762cc8dceb6871acc7
80084	1726823690	4539673	0xfd749ce36f74876cac08203867212e5d6aed6a79c81ea2e3e6e8d69d1309badc
80084	1726823692	4539674	0xcb1f30f1d37fe18f43c65536cb68b68938a5962aa34a5de79e8890166ad2338d
80084	1726823693	4539675	0x1a7cba9f0e821443fab333b9ac8e6a25aa4867fe40ace78a1c4edff74b186339
80084	1726823694	4539676	0x294f99a06eb455b23c8ab53f29c29057e6be11aa18af4c27dd7199dad1e4c6b1
80084	1726823695	4539677	0x98165305f0332f8c9af08e5075ddef43eabe54fd03da255ce5799bc47b71dd2f
80084	1726823697	4539678	0xade962e398687737ef351ce2a9078b62bd08192623e15001e474239366301c56
80084	1726823698	4539679	0x63311345951f17821389f1cb09ef0bf573820452381b4adcff2d63cc35ac8fc0
80084	1726823700	4539680	0xcd712f1d76a1d3024367876eea2e51b8678384737661088bc0f3427069fa6834
80084	1726823701	4539681	0xc52eab601f2a7c2c68a68c602f8987dd957dee21339ff073a7cc15667dbaf2b5
80084	1726823702	4539682	0x1a882895e361fbfdf2adb43ad595a084611fab382dbd92d3f3ed97e060fd7ac6
80084	1726823704	4539683	0x909a5b2e4c8c522a395bec8a3c421709045de489431f6a7837e0c3329cdcba40
80084	1726823706	4539684	0xb7604a1561a0189f024d812a3fcb027e0ab0c7eeebb407dd8882bfbbdbe9c211
80084	1726823707	4539685	0xcd7a0dd2e1e0c0f6f35921067efbe574887a73fb2d852b5f92f6303ee8971759
80084	1726823710	4539686	0x09588114ace087b7a163dd7a5e81b9c430f03c9cfaba8dc612d7eecb42bd7745
80084	1726823712	4539687	0xe98ab9c1f2b60b0266ca322f82d39881b76f678158b61798b1d79577d23755c2
80084	1726823714	4539688	0xf39f8bdd5648e2b541f792641943de4a8e3155ca8fb2f5e9f04462681e490ff4
80084	1726823716	4539689	0x773ac3a33fe8de4a26b7c955ead7ed0a6ed7876d5101181c2abaed4e7a64570f
80084	1726823717	4539690	0x951f2bf7eea4fa86f30aae1cc63541638f6883bebe7414b948e3cd403ce0c9ce
80084	1726823718	4539691	0x9d2fa8a4f70c51c4286df1f3308913d571dcbc0bd888ab7aa350bdb4abcea130
80084	1726823720	4539692	0x781c691b36b0c6d3c7f6b3c82683951ae06a7c1a0ad2670509bbc755805cf8b2
80084	1726823721	4539693	0x8edb5cb7b676388ab13dc05911708e45febaf8a0cb2c90b37abdf4b5ab82604c
80084	1726823723	4539694	0x67f71e37f9a02980a58edb2f260de3269b56c196ccc795d5796a921b3933bfc4
80084	1726823724	4539695	0x153bf793dc25973672418c66677bf10843b337cba76b2499d665b32ddb8f14c6
80084	1726823726	4539696	0x3bced5a64595a540559cef9e41fc733c8bcc5c4823f9848b25315dcad8928c51
80084	1726823728	4539697	0x318ade8c7156b571edc3e892934b3c444e20ae032e0c540b69a79ddaa1f5f40d
80084	1726823731	4539698	0x69128684e95ff00a06d9514a766c85fa036b0e537c246e1ff61935c7e0e81d33
80084	1726823733	4539699	0x3fa87e7a5dc86382ac0940c90f7a02da0bc78339d81f02cdea6be4302844a724
80084	1726823734	4539700	0xa4bbf70c1beadae8054fc07976856b37d134a8cf9564c04f7c415281ac508a0b
80084	1726823736	4539701	0x3b19f70539b9777366e3b337dc11c434384c96c402c51326c74d6b79690cd207
80084	1726823737	4539702	0x7c246fa828336ea785906c63756bb1c300c6efa6f9c8c2e049a3690c77407f4a
80084	1726823738	4539703	0xdc29790ed4f58e3fd6bf4d1d024d68521764aeddc2db597919436def5f981bd2
80084	1726823739	4539704	0xe65aa3bed3907f3a5d1c9e909442903a64a7e5ed99c8edef9edc4ba157aa2e90
80084	1726823741	4539705	0x3d6d173914ad24d4b6a9f4de0576768d824e797fd6d359db0aa9f00eb2026f1f
80084	1726823742	4539706	0x6d6cb06da4e8f12d8145d92a1f16103e60a290a5e890353d2c8367532f8201e5
80084	1726823744	4539707	0x5219057f4386ba48b6ce28d6e70a58d14348c7681c9b7f230e930d5805e36cfa
80084	1726823746	4539708	0x1f7946cfd748e5c4c71ac6b7d8162d5bbd266f52eadbb7d1f09c7f8851be0008
80084	1726823747	4539709	0x96d01cb686397ad50c02f6eb2fb46d1e4880c7584987e47f12fdff3a78677dd1
80084	1726823757	4539711	0xb1ec614ba337e076c111e3c0e880b60749874425292d2867274fb83f4ca0c2a6
80084	1726823758	4539712	0x628ed03ee4e3f1ef431e8f35e50b87bdf5ef768f693123db9b6128116c27f03c
80084	1726823760	4539713	0xe67a598eafb275c3eaeadfdd035ff4d9384aacb7ead649685087158727a8fdf6
80084	1726823761	4539714	0x8df4f2027a8a5913e7a9db89e1a1a23e9dc0210a6f3f818089ad0bcf6197fb75
80084	1726823763	4539715	0x8581930fbdc6677a1fcd1345c73653733ddcb6479b30419ec51383cf838a10cc
80084	1726823767	4539717	0xe918ad99a6efb071632b123244493c3f10342092ce8a405bc779a5c2d78cdbf5
80084	1726823771	4539720	0xa4655fef413eb78ddf08dd04ab3f079e0c3c6ee553deabd19280a1a1a7de1b84
80084	1726823776	4539723	0x65c844edfb442ac899e2fd93fa7c6c58b51c0bf47926ade20838dd8bb837cd05
80084	1726823778	4539724	0x26ab40676076b9330878f3767ce4194fe8762026f2d4839b923e3b58ba337f23
80084	1726823779	4539725	0x7156c4c54ad76b98e0d2162d6c86f526fd5b68e5ce52e337f41887e1796c5605
80084	1726823781	4539726	0x95492ef967f7820d442552880122898ecd19b5b863da725d434db46eaa2edc66
80084	1726823783	4539728	0xdaeccd7c61a75e8eb284c0aa5171a208991ead3ecb130398855102ee5bf24225
80084	1726823796	4539734	0x303db0d0870eafe04d79df624a6d4809aae8d8279fad21325b514b879e9ec43f
80084	1726823751	4539710	0x348ae068700258df13f02aa4a8998d409394d482da9e6db03c15073d88005b5f
80084	1726823766	4539716	0xf9aeba8b4dbcb4213872a79497f30808b6ea3f5d1d53571d4ab66ee9d6caaede
80084	1726823768	4539718	0xf4071237b81da780e8fff84925132a50855fde2758f2252da4b94ec88ebd33ca
80084	1726823770	4539719	0x896a6025018480380ce0945dc72b6a10a7fd7a49e849b1334196973adde547ed
80084	1726823773	4539721	0x09b77c14727e9d509cb638f4f2d5082f914f5c286b33eb057ec0d0360ae88c3f
80084	1726823775	4539722	0xca74822f1101e28144af1947f8c70f75588a23ac1de532fd0480ed0c8763b8cd
80084	1726823782	4539727	0x04df34bbda43afb4846daef927620a11491f5883f45a8a83db8dd4aeab2ab63a
80084	1726823784	4539729	0x8d29dcaf225957656acbfafc78ec51e15660f238f72c73894b097257cc67c296
80084	1726823786	4539730	0xd0873a9a58e47be1f555925f6b97845e862bc1697fd004e52fbced90f2694d08
80084	1726823789	4539731	0x25206a77eeafef325abe0c349497b426cab7ebaaf1d321879687533de00c996c
80084	1726823793	4539732	0x4dad05a155ac0070c4d45310160152e1037d4cb374b8fa20e47a5faa8eed6dfd
80084	1726823795	4539733	0x947ce0344faff21397de0b201766bb51f0d3a56d4568696a28fb70fc90cd5497
80084	1726823798	4539735	0x58b8f8328b404006bd235d856ec7e4d17ee46d33fcee370f54e7b54bbfe40dcc
80084	1726823799	4539736	0x3889ee29c15d33944c97074f71715ccc78f9c2651ff763edaad53f9545518236
80084	1726823801	4539737	0xac8a0503431908f0e00d624b75119d0d4318984a64992ebeb75ce665a729f93b
80084	1726823802	4539738	0x47e9fbc5ba1d6782b769d5475ba28a8127940815ca6fef2382e646cb8e937d10
80084	1726823803	4539739	0x1ee90beff765a39a2aa79da7f6b5bd6adc0a3a14d79614dc76c6b825ceea3e10
80084	1726823805	4539740	0x5dee3473889623d3e8beda73bc0fddab181a671853a4fb2e26c4364f2e619f75
80084	1726823806	4539741	0x5eaf6ecb93b89cf55d5bb66bd73f4fa1c1a1f4a5a7c2a8aaa6db779f26112d35
80084	1726823808	4539742	0x35e7bc76deb541dc63cbf86906c888d4af36fbd4dbb772b8e4ef53b6195f137b
80084	1726823809	4539743	0x70cf8006dd6fa964d9505b9b9e7b4997fd4f377d59204d1315aee4c78af974cf
80084	1726823810	4539744	0x8582bba8b7c572fdc07a104ca9b9b3b3f1090287349f8fcfa662b66c8edad326
80084	1726823811	4539745	0x30e837c8f98829bb51bbddb2491ce1afa6d8ba94c15edbaa5a234de4c12c86f8
80084	1726823813	4539746	0x8d2f28edcaf22c731cbfd183dff0819473d8f835c7aec797d272fce265ae5e73
80084	1726823814	4539747	0x7e079289fc1d30aec906227a49756634f249803590d739799b85d43c6b1617b0
80084	1726823815	4539748	0x9f5a007d8813314970879e51eabf307aa5db3e0c20d9964746cd6edd4f504025
80084	1726823817	4539749	0xd49d0b1189457f2d76e3302d3a74dda97c6490d86676300e7f2219c45ae5763f
80084	1726823818	4539750	0xa827e2ed0c67c4ec39520ebdab8faa429f87b55f34273da58e3c47767aa74d30
80084	1726823820	4539751	0x33441a9d48386e787e1b59bb7c29afd24619736494d3c4f130478eb746111f98
80084	1726823825	4539752	0xfc59896b6fd49ca4af78751f596426ee56de953320b10431ebca713b92712fea
80084	1726823828	4539753	0x8310896fc25bd64792a37085eb2e9d67401ecc6042f4c23cf5a53c5795fc8447
80084	1726823830	4539754	0x9cf9681ba15bc1404a59f01d5d511d76e19b05175992a720e5e74aedef2775a6
80084	1726823831	4539755	0xe8e99cc3b3583d5ebd684666b461292bfe97d78d4f1bbf68a6dd9c4a8b5f5d42
80084	1726823833	4539756	0xb38ff5a23cedbb514f4ec4ecde2916e48af931585faf363e00c11ff80e77cfa7
80084	1726823836	4539757	0x409a0855e7ca0205cd9981b27d303240ceffe319e07f8a15c84eeeb21d812063
80084	1726823838	4539758	0x7c2c0b6f64211f07067337f707b9e571b236fac775dfd48fcf73acae81d67529
80084	1726823840	4539759	0x085ed7ec8f2630d064613eea416f65219cb2e98b15b6c47f7919c03492a8fe22
80084	1726823841	4539760	0x2c418115a2125d641b9609e68aad8e108f5f6e2136cd21001475243cf7eeb756
80084	1726823845	4539761	0x04cd791e76a032a8586f92b164803b132269fc90be0aa242c8c702e9b8bf8620
80084	1726823854	4539762	0xfa6e5df7788e27d89d0122471f5facb5a855ff87dfcbcf90211d40f2533dde3d
80084	1726823855	4539763	0xb8b761f7cbc8e31bb68eeb3f4cd8883488caf4cb2f31ba406a2bb3ce246e3495
80084	1726823856	4539764	0xbd45f6cd6370ad75e5031e6129fba8b5465c29b4ea38ea6ce4e69876ea485a97
80084	1726823857	4539765	0xee325f4039853e862afed0ece0402675f1d2e11575f3ac978e304004d17eb26d
80084	1726823858	4539766	0x50e7c5787de005f9897a57e27c22d2f0984dc5a92dc4168851a36a35141ded65
80084	1726823859	4539767	0x616711e606ba4a027d08417bb0a9051a5b18c7bdc7bbab72841e9462ab79f39d
80084	1726823860	4539768	0x555bc9e8d7345a74eeb1d4ccd995b5fcfcf97d8da1f1c6223855b295eb12a13a
80084	1726823861	4539769	0x1fa0d2a20550e96d8c95c91e189985748b947f2abffed5507de6d048819074ac
80084	1726823862	4539770	0xc9f88cbf452275fdddf32d09ac2024990df2a13782076dd17620eba2f8ac645b
80084	1726823863	4539771	0xad417a7957d79502051f7c62d0d59614922fab3b997645110eb7be26e5200c7c
80084	1726823864	4539772	0x79e1360c39e3f32f179f66196552e423be2c6f9a32d5110000db137412e04899
80084	1726823867	4539773	0xc4a860e2b4eb3a7f6c4dc995736906d4f2d98a08c2f6259ca44873c8ce0dc707
80084	1726823869	4539774	0xad4c98db5f7d4a52cebd55919771554c8bbf38b4626ed1ce023c9614f99b41b0
80084	1726823870	4539775	0x9b99ee5682564b9819457a3b2b9f3b48dcc61102620e84d5631a4014f4b27fcb
80084	1726823872	4539776	0x04bfd7cd0bd175f20b714a0f94d3d352d5effa9b44e1b41e38dc101905a0752e
80084	1726823874	4539777	0xa1590d5484c04a1f781c14d04889406614079d58451b26347e1df24a7f9d7539
80084	1726823875	4539778	0xbe1aa040dcfeee4716dfd4527c69829d36cdfa0ce37f9ae7ce076930f7e2cf78
80084	1726823876	4539779	0x67c246548400dc5c86a3ddd98e1dc1a8ba10ade56f626def86a39b2683505af6
80084	1726823877	4539780	0x1c1888ad6d8434804fa5908faa10a66210d9b966054b5f87fbf5180188b9212e
80084	1726823878	4539781	0x1cce9b083ce8508903db3b8b571e73bbe1ec3fdbf79d34fd276032c324367472
80084	1726823880	4539782	0x3c92b7d254798ee9823ace576265f8a1aace8ed6d3efd55b2c210e75cab7b5a7
80084	1726823882	4539783	0xd81717a92d3e3e76bf3e4a12db3b89a85ac0a23c4965026d8dc218bfec5672d0
80084	1726823886	4539784	0xf0ee84e203cca644c1009805f99448f39af8baf3f41483e9ad62727266be76cc
80084	1726823889	4539785	0x4af9f7aed19bbb5bc9e6df0d8b6bd2dc717dd67bd3938f1bde7182ca802cd6eb
80084	1726823891	4539786	0x39ee24eb018b7820945aa0d2a59b3b834807887b1e9b043a9606a32c11c44972
80084	1726823892	4539787	0x120a0362e243a3730c89c6cea543537a0869b81fe74de036db98d0559d62f1b8
80084	1726823894	4539788	0xdd711b1213120df5745eb496912bae2a88fb1dfbf8720ebf0cf5d6145f264f2f
80084	1726823896	4539789	0x2726c17948d8f9b3ae84845b0537a3051cba8b27cdcf6b9e70079d582409fdb8
80084	1726823901	4539790	0xc942772a3ddf9cd73e570a5e4859ab7356b35849a46f15333dc9a4d696041dd8
80084	1726823902	4539791	0xb3eb6f45001c35905d1e0400dc0d5ef0a109959441315fca355429c5d1cf765b
80084	1726823904	4539792	0xcc8780893e6acdf72b2c56ddb530da2b4bed271964dfe0f5b2b0b8d396f18488
80084	1726823905	4539793	0x1e4f2c522af800bbf255e1b539e62b436528d5e19c706618699bb62a390345a0
80084	1726823906	4539794	0x0ad26bfca205987fa193e57d49c629719395e3e0d632abe37e3c365cba616700
80084	1726823907	4539795	0x757f243cacb113f025bbaf76326d7c0b630650384eca797cf042f0aa97c522e3
80084	1726823909	4539796	0x58c0b9aa903ce9c69f7d9759ee9d1d56d743e4c212c4e10e703bfcfbd51122ea
80084	1726823910	4539797	0xd2eb0ad70bbbaa9962214f31e51e6b9f5878c37c60ed8e52fbaed71724a9bc4f
80084	1726823913	4539798	0x344f9559344348b56758220335e1e4d8a3a47ef3996222ddb2f15fe665441dee
80084	1726823917	4539799	0xfbb78b260958db568de81026ffc91b6ef664b9bbedcf34a39b299e66a10e2293
80084	1726823920	4539801	0x5b971fceb3671a6a5d4fe450e58a2ef702add91b1b0508c120b3dcd4fab85c33
80084	1726823921	4539802	0x7f4a287db96773d65153ea444c86729295ae4421f71f7ebf555db7c2c5425f40
80084	1726823924	4539804	0xdf0e39d69665c56368d5fba16d262f423e6a1c11c0be4e852bb8a6a44d6a847a
80084	1726823925	4539805	0x3e6e83a157ec1567471dbedfa2b8ffbae434de075cb10dc6904719561b14183d
80084	1726823931	4539809	0x2a77c6925a99ae8c3aaf4f8165d885d07f93db54febd03b0fae243d06b69bc3d
80084	1726823935	4539811	0x3088bfb7d97169ac7ec41c650348dc4c6e80f9bc064809af69f16907504a63f3
80084	1726823937	4539813	0x3a9f12ebf210049ba40998ee519981ef4239382fe0f3bfff7be1a86a4702a78a
80084	1726823951	4539822	0xb2176f8281acdc6af9d72bd24554faaba910f6ae73802803c7907ea8c5feb1c8
80084	1726823958	4539825	0xbbac1182cc6a2209fd8a78650659862de7d20f2c6504fc9d3193245dd8818b13
80084	1726823960	4539826	0x895237e92ac1a1e268e6c07a89f0bed937d2bdb7f7242f103a6d55e0694e277d
80084	1726823961	4539827	0xaa507cf491c441db2734e3ee5ac6ee24d968b3c5896e243f6ec520e0c29b4574
80084	1726823962	4539828	0x385c7d36f9e1b85da78377260fe69e5d44cc0cbb06f45405969fcd12bf507bb8
80084	1726823964	4539829	0x5cee95126790ec6f2aca00476ac735bec8545c487b8ed0e0ae10ec3a62f190be
80084	1726823968	4539832	0xefe69b1f1f0b9081f4966bf787c286386011325a6268667efa48bc051f9e4682
80084	1726823973	4539835	0x1360bd8995737b5d8a9922f54e668f88e280deb24855fb7d21073a773f06ac4b
80084	1726823919	4539800	0xde8086b03839d90e831d91bdb069cda6a2ca46c82973449d65b1f3764b96d611
80084	1726823922	4539803	0xe375a4e75f4d811a150e6a26e209dd2ef52df2b760f25205ac48705c2d4cb879
80084	1726823927	4539806	0x328b1359a85e3c6880052dbb34acd9d68760f730f239725d5f77e891cfd27c1a
80084	1726823928	4539807	0x5fc84b1f5d26edc0a0c5ab2dba5af3f00bd20388deac953f8b740686fa5f4d92
80084	1726823929	4539808	0x407c72115e030d895bbbd2c3c0b8d88d0847bb25f354944b3ecb43ec077e94ac
80084	1726823933	4539810	0x017ee9ea251440beafaab1607fd07b994e9530090faa715f9fb652f47ea02922
80084	1726823936	4539812	0x0451f438991eb5ad7bbbef742d072af32bd3bed33cb4b2232f03f0f14cd55866
80084	1726823939	4539814	0xb4e91d44cdbcdbabcef2e6ebbebff88c3039dab371135581a582000af339c8c3
80084	1726823941	4539815	0xe7af1f1f34e7aef7ef672c55f4b1e11d1f092e790d3a45d0f82df8f0d8df98d4
80084	1726823942	4539816	0xa799f5a686b35215ab4a23a9ebe6ccdf279fc4938d72be2b3145ef3f427ea679
80084	1726823943	4539817	0x8d6c9acc2aa825996a0bf4a9ff71bf38524208b5fcc8c3ac98fc2e84b8794b28
80084	1726823945	4539818	0x8f5f9e0db14537bdc394726a95624bf0dd62d58e25b06bde40be6214a26ccc19
80084	1726823946	4539819	0x7c8e43c697e3d2ff82a2fd98301628fad62c3d01d9d0263f70462e704fcccf6c
80084	1726823948	4539820	0x67c1a35493fac626cf7934782a3ddd9e42d2389af02d8b50d1eccbb6f87b5d55
80084	1726823949	4539821	0x59c5c4367524eacda310f97859d50ba780d802e6f5b7bc6838c16478711c186f
80084	1726823953	4539823	0xee01833de19c99d127210ed1fba42e67619f99ee8225ff43e51bee4a581e374d
80084	1726823957	4539824	0xccdfdc2ccd39443ea0c43d0ead13ce7fba5243a7a42f1f3a488a1b82fc2ed2e4
80084	1726823965	4539830	0xcc0e748cdff1d14e46e5d8413bece5b4a4f5471bbd9060a8121e4f309e659830
80084	1726823966	4539831	0x428639b1f577ecee0adca06406de5c03ce4d13c52818c8999a4f29c86ba837dd
80084	1726823969	4539833	0xc5351b9e04dad4dbf828e14b39b1f8dff7215b93ff02b10dd9e272175d7d5a2e
80084	1726823970	4539834	0xbbde6485e34539c9991bd48f268eeeb786238175ea60394c30cc5d4b26364561
80084	1726823974	4539836	0xcd22f0ee91254b36373403d21261266278454cfa384054262858df72cbfed536
80084	1726823975	4539837	0x7f44d5d07a3ca9b33c827e3686c5c65a39a4f8db495184deb0f9203469604a7a
80084	1726823976	4539838	0x2265a3402d9f03e18ba7aa029fefdcc7e77303f6bc34dde6c1abc2a0ea0cb77f
80084	1726823977	4539839	0x36eb763dec5a2f0cfea84f0a4e1fedd47582ec5f0aacd87df1535977b5a8df41
80084	1726823978	4539840	0xfdae72b9476a40246eb550f5c0d83f403f42c6b00a6a40f4c8efe6b51cc84d11
80084	1726823980	4539841	0x573033fe6e37fb419ce803c1236a6cf8e548e9320bb617b3a1f9a49f9fd1933d
80084	1726823983	4539842	0x53e5f30aa89549cc243ed74650b19e78db55a7125a9275347ec6e20db073d756
80084	1726823984	4539843	0xa6661ec05beaab99c5b8845da88410cbeab5c2c677d0eed1bb0954e73d549849
80084	1726823986	4539844	0xf774d18df8fc6157b68d73a68c0bb645b7df6e8bd691bb6a374e5274c3f7d42d
80084	1726823987	4539845	0xda6884260984d7ea0510e75129350be5261da73893cb29092fb4698b02b9346f
80084	1726823988	4539846	0x3d7e12791b0f22327ecc0ef81324fd02a4f0eb74f413d27e757f5eaa9de2bb91
80084	1726823991	4539847	0x5ca2c0169f36f81c8333549237f773a6d81dde3cd3c3a89d106b703d98976f8d
80084	1726823993	4539848	0x76a21da32923793bee14b62f46c6c2a0c3ea4d036bd3cdcd3675c0d543cd2969
80084	1726824006	4539849	0x79323e573c00e2fb13e031b583dcdc34e7b2a6cebe4c2a65ed62e88206efae86
80084	1726824007	4539850	0x6cc47014398a296f79a775a892fb4ffcb5657d200ed134c51a722682020e8b58
80084	1726824009	4539851	0x0e8cbcf8ec6c6d9d57a7e4749679883a2a9ec0d87837d5ae4480d9f5150ed36d
80084	1726824010	4539852	0x381e77b55ff17394957da07a0ff84d054e9aba8c05eab4b70b6855c0ebe90dbf
80084	1726824011	4539853	0x7899361fce3981e9050e23ed3a0b82a20e58ee01b9a8f32a1e66a6146b1e3856
80084	1726824013	4539854	0xeb8f78affe099061dd48a743d57214d7310907e0205994e3bf7820b492311039
80084	1726824038	4539855	0x62dcfb1b87338caa9dccf02be6088a228f7210cdac01ffe2c1aea3b8c0b093f9
80084	1726824040	4539856	0x08a219cdf544a7e79f678a1c30d810a4fe087a4e4fce2f9d06e40b103952ecd9
80084	1726824043	4539858	0x3cc1d3abffea4ef41496b902dd287a049572e273e4d0fcb263436cd9617c290c
80084	1726824044	4539859	0x275ebcfb0ac211ae4f394dda7f834d12c8c5c0d950134609083933d2b6d95cef
80084	1726824045	4539860	0x15f8a5ca4180336f3a68f27e26d384d01b5987555a98df2e0c56297ec465922c
80084	1726824047	4539861	0x82fd740313f0aa4e3eeec691b570f168b994e2ef2c2677e22d59be264a5e09c9
80084	1726824048	4539862	0x94994e441beec1b4da081bcb8357f5130072d0efb2a3971197718de9e98c7499
80084	1726824049	4539863	0x0505d2bfc00172bc32d7e7f9bbd90ce8bcb8491205041e2c73b8a368cd72fcf6
80084	1726824050	4539864	0x3a6732dfa47e8228e35ba9dcfcaa9e78028641009e8e8571b0ec148e38757ef1
80084	1726824051	4539865	0x3489e45a0c0faea409ef29ab9451978b60ee2aa607506b522f0d32d056af33d5
80084	1726824053	4539866	0xcd8ef0fe44e7071e76831dc85420f0bb683e6bbe30818764d513e7b8e4e9b8d5
80084	1726824055	4539867	0xa70bbf2512608f2f79f0ac66bb1ef6ebab20dcdc17784d74b9cabac6752f2d97
80084	1726824056	4539868	0xbe6478abc48963b68805f26988bde495509451f891d4c99e66d165585d769247
80084	1726824061	4539869	0xa25a9f46ac2aff05fb60db8782c91b07d60cf70e03cf3ececa8ed078edf86bd0
80084	1726824064	4539870	0xff7fb49ef47a0ed4a5ab0f76268004fbb0f74bca4ce0bc4ccba10c3ca1b35665
80084	1726824066	4539871	0xace50f412539626ade209419f29e24792127b66dab345f046ccd64561d107d9e
80084	1726824067	4539872	0xc14b920d9fb4747e5ef9e6c9eeb30154e3cc0c0ffc0e2a069f85fe3e9c54fff3
80084	1726824069	4539873	0xb3bbca90f1429e10e8654da4a7a0361ce8783c44a8996634f3856ce8592983a1
80084	1726824073	4539874	0x3d949a8a48f3b8ffc8b5ba9f2cef003e851306a14c8a28df65efa5a0b405227b
80084	1726824075	4539875	0xf3cddc7c4f0eb14aa40583c25149a05cef7a6458b4981d6c19065f5ed7cfa5ea
80084	1726824077	4539876	0x303375dd4027bfdfe2347106d575c8d8739f1f3d07edcf0b804616f7761a89d2
80084	1726824079	4539877	0x66fb0dca6c35ee25895a6bff6feda6c2f788c7b9516b2b8f40de990f0f7de09a
80084	1726824082	4539878	0xc53fc0898ebf362feaec27a59a9bf307ae3ab18b621267681d8f2884056f7d49
80084	1726824091	4539879	0x5ff1f753e6924358aece3c71595d58c07e8076276fdccb6562e436af2b34ba6d
80084	1726824092	4539880	0x2c8b48e91120d2c0998704a1f48c14efb78ce2c6e6fda1e1408eff96e7638450
80084	1726824093	4539881	0xeb7fd5b592ad26b2192388bab46a3df7842652f4e463220137854c76911fac5e
80084	1726824094	4539882	0x724b74f002dfdd727da0e92c7eaa9a5392b65d720c0983e00eced949c632ec21
80084	1726824095	4539883	0xedf831594acf6cc987c29312c59e692ac5e4af5fcd79907193ceca8e58ceb84a
80084	1726824096	4539884	0x34c08b441ead996b11f932499ed69fdc3f2f16dd362fbf652ef4919216af4f99
80084	1726824097	4539885	0xf7e8572a1f24ad789ce2845057603a2654bd9c7c1f13a413aba354f73e514582
80084	1726824098	4539886	0x20a515fe6b569f37a92101e4c5e6a9737ef7906f143c7bb63f95816c7e7b1773
80084	1726824099	4539887	0x39214cfe14b004bb67eed336358accfafc40aa87fc6a869c00014a12fd7ab933
80084	1726824100	4539888	0x32acdb945ca905bf8e87c7befaf4ea6e747872c42230068b2ffbc0067c030d7e
80084	1726824101	4539889	0x95282f40579195d8d84188672c6f7fbaadd8061b9bc5f2d57a96c1f0a3be80dd
80084	1726824104	4539890	0x832a9ad5ab48ba12bd91f337b7931b13b3d59bec7f9e5cc5ba827435acd68aa6
80084	1726824106	4539891	0x0a62af057ba2160386d10c4a059f6d8e8f04056cf8c4aa689664d8d85e296664
80084	1726824108	4539892	0xdc6d35ba88c8f2a71d9935170de9a83619aaab8b24db1a75dd9eafad975d970e
80084	1726824109	4539893	0x7e653d21b0a699a7c0c0ce4f55c3d6e176c191829437c3912c10d6f50f5b7377
80084	1726824111	4539894	0x0b229fc9857c0e81c708bb5bda399845b32822f81e97cdf2864c6dd7697c4441
80084	1726824112	4539895	0xfa02eb5b774ad4608c68e5f8350b517864655e7854395f8915a34aea63b4c54b
80084	1726824120	4539900	0x2e8571ee91178bd6dd9907fbdb036bffe5b4160fe65ab9d1164f4f264de5f9d1
80084	1726824127	4539902	0xc2ddf844c9e5caefa36e7df5ac853a0edd0338f3919bac0a748f6277c4ed56cc
80084	1726824128	4539903	0x168131d92439ef0876acf75223ad6c874e4a95cd9e03c583ac02acfe18eef04f
80084	1726824140	4539908	0x4eacda08ecde7d75f2b220d7ea2568f0d924e52e50897905494d8941485218c7
80084	1726824141	4539909	0x93a1c891271817c922461ef94a93b591a99b6ecda9749b9532570607357a5a45
80084	1726824142	4539910	0x194492ef3ad9c81fcc6a7373b717a3abb981cceb8ba7a87a7188b1aa397b4493
80084	1726824144	4539911	0x74415d18f3098e2b965858aac7a9325af3cef521011ce037872b42ededabbe58
80084	1726824145	4539912	0x39620e28cff0c21ad3157dfa93855a075cd5bce39b81a6c377b2b6e04b503e51
80084	1726824146	4539913	0x22071e94c3d59c42e952524f02a29f46652c8fafe441177019183a62ebe3426d
80084	1726824148	4539914	0x4bfa2ae7a3dec94aeb472c4b3a149a0631b47ddf561d25951a71a520438237bd
80084	1726824152	4539915	0x92d0b3535afebb9186eb2848e9d55b5fd83ccf961c574691c516c1b48dcd3748
80084	1726824153	4539916	0x163bf640a77b3d76e71a259aaf894fc93b6e86bf4135460110693b240810567e
80084	1726824162	4539920	0x034aacc4073289c23230e4c536c4ed0c15a17a0f6b6e4e9a351a8d43f329e1b3
80084	1726824164	4539921	0x6fb8657670110448b155fc2484a0b0d741b0fe1f585269907c6f75b724d4301b
80084	1726824165	4539922	0xa4a7d0517996813fb57a81ecf10c8e1c19c11b4e9c2f43bf4ea181ff72551fe0
80084	1726824170	4539926	0x713bf67f51e5a3099f362122f5eb78e3c32ff257aaff8b203c9e1ad2aa954850
80084	1726824174	4539928	0x5edee5d9539cbbd0cb1a32f1d1bdc88f024a34f594dcad7e3058da983ae2a204
80084	1726824176	4539930	0x5c0a2a9936fff2bee2fc09dd89d9156e46bae8fa954d77452bd82cdb66ff64c7
80084	1726824178	4539931	0xb5da7ea79c82655d6e6f2fb9ed359b3a5c420bd3716b33d140e005c4ee4fe234
80084	1726824185	4539935	0x2d96b0d24c92133c4bbfb81466eaa9b0ad0bdbf2ca494be5ff29e040eb417518
80084	1726824186	4539936	0xd53cf5160197e284c0b607bab2483fb79455a07633d98fed3b982e28aebf4831
80084	1726824187	4539937	0x9c2c3c90431ee28daf0dab09acb2dcc5b3544c8ef23d9f21fb0ac562cfc863e6
80084	1726824189	4539938	0xcb8ae49c2f4cd3430f04164a124ecfcd03780c9595d846201f44049da28a7bdb
80084	1726824197	4539942	0x67905a43b0c60b15fd73a8f8eb8a72c1342475992c0adf674c36be8c6c65ce69
80084	1726824200	4539944	0xdf29ccdd4322096cadee39d7295027a706599d943207802a870e594438493556
80084	1726824201	4539945	0x4c6c4177e79401b06997ea8ba2c54af935456fa089c2ee6b4810bcd1f87a4e7e
80084	1726824206	4539947	0x08d2e58c2970af766346d8c5ac476dd1f606967b96e4eb382ebabdd6d06ecbaf
80084	1726824207	4539948	0x1d458a124e61dbf4ffbeb103cd76a1a2c51c0527ecb72e92b9bea64a0eff0daa
80084	1726824209	4539949	0x80308e3aa234be96b775e7eedcd889ce72c557ebf5bec80b8c9cb69b30c8de7b
80084	1726824214	4539952	0x33e6d0f583f4fa3eaa76a127edb03f1cce90ccaec19536652907c44a5cf7f276
80084	1726824215	4539953	0xd8412106c53840e5baeb8ddbbaa53531786cf81d11c78c7c37f08389c4ea0d84
80084	1726824113	4539896	0x817003e364141712752cf3fabc1edeb0bdec2f8978ac2015e4c64fd722f9ab77
80084	1726824114	4539897	0x705036334c067946db5cedb8ab6c27232ac872176b3e32cc90d34bda512c1c7a
80084	1726824116	4539898	0xb96d16914b0d87921847f51edde124fc7916bc2abe310ea3e8b64e9a97224538
80084	1726824117	4539899	0xc9622944f1b6e94adc15150a7db0899a03097a4aecb1909bb9daad39f4555bab
80084	1726824123	4539901	0xd7bd20bb71586c7e38d487305412c30a1f8acba41355815aa90af46c08759263
80084	1726824130	4539904	0x3529383d049cf0465aaaf7fcf31109671251b293e7ab56052fe49b47eee234b3
80084	1726824132	4539905	0xa15a3910b317a664955b98df83c91398a2691b8e8df55c559682ff00bd813512
80084	1726824133	4539906	0xbcd97d705dd6c9b180d98d46753b487daeab4adf11ed0528efba06294717d529
80084	1726824154	4539917	0x06a0910db2f652dda38b6f024e2d2ee322dd132359678a39197b2b56c0f10a30
80084	1726824159	4539918	0xbce3ac8b3926880b57e95edf80227c1648a47158163f2bd6ae1ac271db8cae41
80084	1726824160	4539919	0xf04411f3c3e589cc2ca62f05fa77274c7b093f3d320af0a13a43459f2ed8509d
80084	1726824167	4539923	0x4826fe6a1a3b855b2b580fe43215e8ebb612b9ee2d1636c44eda87d3bafd3953
80084	1726824168	4539924	0x284694664ca89eeeb1e4e3a77e44aabd9a268e39c6beda3e95508584838f8a38
80084	1726824169	4539925	0xc300614b46529c6035906fb05976669145450cd5b916acb67d5a3dc881038c70
80084	1726824172	4539927	0x328cb095dfb42e9d7774538346eeb73ce57bf60dd7df4075f4c9783b324bda61
80084	1726824175	4539929	0x67ffd41a60780db0bdd4c281865c3cbe3d277539c308ea441966d25100f35b53
80084	1726824180	4539932	0x90bed44e6c4e3782fc99ddca402992631aa1059429117b00fc72d5ac95f94f60
80084	1726824182	4539933	0xeb69e19ca84297f7b63d377a0c306aa51237c60348e81bd5d9076cd31e05efe5
80084	1726824183	4539934	0x8bd86389bfcad44da3664175155be1b6dd69b77cae73c4071e751dd2c0282b00
80084	1726824190	4539939	0xe8c6cf3523c5b5c6e755db572d4562b2852b40e271f72d99a550a836b2fd370b
80084	1726824192	4539940	0xa67fafed29583e3c6da43779c8d638c287efa05969faeccb9f715ed379b3827c
80084	1726824196	4539941	0x94d9f40bb886b0fb04fcc77c1a0447f0e268b0a6687a7e953bf0a71e4312cc74
80084	1726824199	4539943	0x7d3fc358114550c258f14cdd26a424e91a45a072838e5b736d0f61a541b30e06
80084	1726824204	4539946	0xcd153d8b601c0c3e80e58ce42d40efec412f20bf4f0ae8c1d527cc3c3fb6d272
80084	1726824210	4539950	0x8ba20d4c64ae8bf723b447ba6875c18229d05fffea288ce3a05866d6a953a591
80084	1726824212	4539951	0x31116970c70aef232f7e4f283a3c86bff6e31b79ada281c5a9e4c0d9dab5e758
80084	1726824216	4539954	0xbb75fee29b49561631d19296575d03ae989635cbb50299256427a3e7f57bef71
80084	1726824217	4539955	0x4d85086de260f64e0c71be63d8db0c6bd641308c8ffa379388522c216817acbc
80084	1726824218	4539956	0xcbe390b08e70780ee7a36787a78e18c1096fc5d63d2b56e151e036f32da2130a
80084	1726824220	4539957	0x081bcbc66e4d2a8649ed578c198209b677f1e102e30807a460d887bd32f3ed1d
80084	1726824221	4539958	0x5b957edd10571f696b9f6cf507050fae00b077622d23005237e88a7bbbe82923
80084	1726824224	4539959	0xed41e402b9ed8ef7a10fff09e886a29e745a3d8d359912cfd457729d931a186c
80084	1726824225	4539960	0x6ec870773221f3906b6173978a4ee3ad0071453501d141d1e7a160c75d5185cb
80084	1726824227	4539961	0x9343eb541b274c8d5a1eb9c0d309f4bb9f69be6c5f834ae1cb4290032372350a
80084	1726824228	4539962	0x5533af236d2069dfaa9fcf0eed3fdc34d6afa2265193c14a3d15c050655eeca9
80084	1726824229	4539963	0xe6b47b4a8831ac6ff730a3630c1719331e4088547e6d9785ac6d0680ccedde53
80084	1726824232	4539964	0x975c87191acdc6ced8fb3d0e006557af8c7b9ba45b55233c5f018b1c33ce8757
80084	1726824233	4539965	0x58728e08547d823a5f72f731dd71c2e529319dce94013e1ae4c6098d5108a0e7
80084	1726824234	4539966	0xb7f52b5dde84a7b55297a784722ed324c5b7e1cc8e7eda253c78382797a7efd1
80084	1726824235	4539967	0xdf41228f3411c9778b1ecf8d0d12f17b0a1c7e371f96b4c24df98698abaa574c
80084	1726824237	4539968	0x1e03918aedd394d697f06b0c302ee32528cebce89c141bee19eb469c1ef18210
80084	1726824238	4539969	0x2a01b4d56e894e93485ab24d1e14cd72d3148e66bede7f11a6437695dde985f3
80084	1726824240	4539970	0x89528abc478cc2b2bde8db8a635d61de5d3ced36c5c70106a06b646a64166c1f
80084	1726824241	4539971	0x21778518234e0ca99f6f1d3d0e3bc4f7d528ba4ca7a38a5277a07da081419ea7
80084	1726824242	4539972	0x4ecbbdd6284d271a7bf42d5d9bd574c6afe38a973e08c774112d4981f115b649
80084	1726824244	4539973	0x0e033ce70e91d7e2472a228c3de2549406692e03ae2e5f4f2b3e081a61a546b3
80084	1726824282	4539974	0x89e9f66eb73d7c18df6fd77c7000adc739dbdbaaffd766260d29fbe039816422
80084	1726824284	4539975	0x0550a542e2cbcfcdfc0614471380d9dfd3edf0c82d01fd1f67cea10847b705c3
80084	1726824285	4539976	0x591c2a05b20a8275c169bc316441e02676f201cc7d40c6433af77dfab7c5286b
80084	1726824287	4539977	0xbccfe4754d28a9b36a12db24fbf90aa02a3f7ec3f54ed15e6571bc7193b04364
80084	1726824289	4539978	0xdb92112a2f86d8800b3ccb4f8fd61cc0611f26f725222b3f926849e5b97d66d6
80084	1726824290	4539979	0xe45cec1f35cb75137719cca2d0dc0eeb63b3442f44899ca4e5597ea80fd99606
80084	1726824292	4539980	0x089954200271183dcc2fad4e5748c85caf64544b0ea03e320dea6112e432a2ff
80084	1726824293	4539981	0x391e3553e8c8aa34259647c67bbc54cea46d23f3402fa0a4a49c01332ff3df1c
80084	1726824297	4539982	0x2508e588ebd43fe6787bb998e1366518fc33494979ef05cc9e86212381bf6690
80084	1726824298	4539983	0xff6d4b5707392dd523fc27b2804d3c43240e72b9909ef9261e3ebd78e2b634f1
80084	1726824300	4539984	0xaaf926a6dcc14a0054589845a650b74a0d76c28da6a8b2f800f93c409f5afece
80084	1726824302	4539985	0xeede1d60686cae34d09fcd7bed4f0226fd71232111907f6dfea90a8dcea239bb
80084	1726824303	4539986	0x30a339394fd2c3763ede1942a2e3ddf73ba7027a8a346cf06f5950b8511db9a6
80084	1726824305	4539987	0x4087db6dd5c8f5213e8f9257bf69dd4c9427f3efefe59bd03dd93a989a300611
80084	1726824307	4539988	0x5f0dcb712042f64e7460e98739a8dbf672d8b045c5ff41b0669df2506e335da5
80084	1726824308	4539989	0x7dddc80a716fd746739cc1938443aca41dde6d07d81993c7e0d39f851d96f455
80084	1726824312	4539990	0x06c052804ebd60bc2d215ddf1c0824d9934b142f808e3e6b4f1858255868b0a3
80084	1726824321	4539991	0x907babce23b45f75d4fb95055e2645a244c3977ec2a4a4d942f07691be0b638a
80084	1726824322	4539992	0x7912249376d44fa0d18b3fa06734e87561e9c32dcf7c4b4beeab087ab3bcce0c
80084	1726824323	4539993	0x46e4d0a5ff31aeabe046afaa4d1b55fddde0fe5731c4014eae080b09029059a0
80084	1726824324	4539994	0x8baded25dd79fc2180e7ee37286dc0ddf9c28e5e67829553d963c97900a21b06
80084	1726824325	4539995	0x62a082158770c2ed995a4f6a8f04287596859e3c49c5459bf75d9a60c457e0c9
80084	1726824326	4539996	0x40ce3748594c4786a9d80f9a56ed741e2ad62b35d682aaa94eb371ccfdb3dac4
80084	1726824327	4539997	0xdf048f8c468bcef2e68d375a672a47cf66db3236a4db6d2d8b566630815dcd1c
80084	1726824328	4539998	0x2e73d3d007b6ce70dfeac11611259e128520112e70977e7f0776ef89fb1e1362
80084	1726824329	4539999	0x2b517e3adfef75bd6e0a4ac16fd21305e8d738f751276565ef4f9484f3b21932
80084	1726824330	4540000	0xfc8bafcca201cc419f69eff4db80dddbc9f74344daa9e02df1c20b50059233ec
80084	1726824331	4540001	0x967ddb7c945eb706811bb6c7ab468eea14090c5228faf1bbc39ce2a12599d223
80084	1726824333	4540002	0xcfe2a77ddd3872af4fdb913464b27bf6d0cafd18a5844122eaf089e194e8bc81
80084	1726824336	4540003	0xe0af6d69ae3e15db6a59800ab52f748b2465b7263e9533c2500e1adad13e676f
80084	1726824345	4540010	0xb409275367ab38a740f2d40bb7fcef001137185ed58c4d9c51f8bc21bc6db204
80084	1726824346	4540011	0xc012a4cc7cc9cf9ed18e5db30c6914c242a283f82639c7f2f790d5277e55b271
80084	1726824348	4540012	0xf4735c1ceef20b22041b4519e41df99d6c2723d04b481cfb8645de643a76bf6f
80084	1726824352	4540013	0x959d1445b2411084f6f9cabb44ccf246539ccbb984f0ca618118f6052ac0d109
80084	1726824355	4540014	0xa482844e30655975bde178a812b7e28e6bc4c6dbda7828bf0d2a8e2a8f5b57f2
80084	1726824356	4540015	0x20af1775a078b1f0ad2cb76741fb2686c8e43677ab720879e890fa9da8b45fe6
80084	1726824358	4540016	0x6b32451dcfc111a6bf3700ff018ad2f9c4581ca5615d18f8c3c6f4fae9613a64
80084	1726824360	4540017	0xe1dbe37add3f7ae9df11a274a7adcfc7882ac9cbe939cfe49151bc3753ceb9a5
80084	1726824361	4540018	0xb130c1bda161a722767430f545679ad10a75f23513c59463a237cd4c99f6eb8b
80084	1726824366	4540019	0x4e297be1241310d377a83b8d4ac53bea7dcf46d062f7ca16f93f6c13d801ff82
80084	1726824368	4540020	0x7584a31012a6785714504bbe2a0838d007175a9347c404ca68a2da82ded46a6c
80084	1726824369	4540021	0x52224d07f55ffab40086e6dc9383293d15737d3a5bd4e946fb91d79953055ca8
80084	1726824372	4540023	0x88d90c41bba2eeac86ab43a5f712c4c9c77f5697227a319b74317bc68bd29b4b
80084	1726824373	4540024	0x823c00137820f2ff507b996e9a78131853f4d72739d6b9d65c8309c7a17d8980
80084	1726824387	4540031	0x395988a119df245e8decc62c73cc191bd64cbda23af180d4454921568e4c0e84
80084	1726824388	4540032	0x01fa9f12c34efc219abd906c9544bf2ba0c3d088fb454c28f8f805f9bb120326
80084	1726824390	4540033	0x9ceabca67be6c2e977cfbfe814a89e038153e5d6aa366b9f760114c8dc22d10b
80084	1726824391	4540034	0x9e9834e9ce426992cf23dfe452b2e85ea8ee775016e1a745de3db6543748da5c
80084	1726824399	4540039	0x1b312a3634a78f68c91126e2fbbf846698f363c2ac88db56ffef005e10569799
80084	1726824401	4540040	0x63a54e1c9c7f0306e9ff8950a8cab7a4470ca55ac7acfa8b52d411796feb03c1
80084	1726824402	4540041	0xfbf35cca4bdca912a66bb59241872c501f11f01ba9a412012e008cdf39ff71b2
80084	1726824404	4540043	0x6dd14deff8a607ad0c0d455bd171d4eb1903b9eef4dc22959604133668e9e545
80084	1726824406	4540044	0x650b37e10d1d55fb14755ce129465e5867db90e00b07438b6201260f4f908791
80084	1726824412	4540048	0xb6e385eb310d5b26b9897b74f9f6df1a1072d060f1803472965f419c73496a71
80084	1726824415	4540050	0xd81021dc03a76900e1487628cab3b05f3fa734805a92be7ddec3dc77daa3e803
80084	1726824422	4540053	0x1a937231c3d40d8f7460d129c0fde0187e5f3238d0379b76fcabc44f6453c009
80084	1726824436	4540063	0xd652a8ca63fa7b7c4162526c99a0d906d04c55e0d6863de702af8cde886aba26
80084	1726824445	4540070	0x57991ba5624640fd647d71eed034dcbd5addd1e100c29e4cb0e6e6ecccda7062
80084	1726824452	4540072	0x904c9bdd7753a822c252bec426e8559086ee2f47483823daf2ab7b8c2bae06ea
80084	1726824454	4540073	0xb394e617747272f65ead57e10fde1e1cb9148574326636143e8b6b3e38d51b9b
80084	1726824455	4540074	0x730f5186c5dc9cd748b6274ea6398a4cd12f44dc542a46be8ade0b39201ec658
80084	1726824456	4540075	0xb148ba60d86ede2c948dbd5d9dbc14cb58e84e3413e77257bd53f062c4d9fd6a
80084	1726824337	4540004	0x5f8113371b19a1559ede4155b267d35568a9519bf8c3d09beaf49918ad6aae6b
80084	1726824338	4540005	0x0567a3f831f69c9eafce4bf41a887f6375f440810efca9a5299cbce001c0400e
80084	1726824340	4540006	0xc0774f3ad2c2480223e9c10ef03b036b63a840d9a09a28c95cbf0a31200ca772
80084	1726824341	4540007	0x9b12973410f75fdbecc72ba25758860cba170d64849e38c3b5c2fc02dc0a07ea
80084	1726824342	4540008	0x24296f13fc9d7fc6b9b9fae221abff567e52e5ede4899d7a34729b94583e8c43
80084	1726824344	4540009	0x7bd703349c3272a3249c82cf5910559c619d3604f06aa373a1628de6c1b5c701
80084	1726824371	4540022	0x31ff89dd487723ad4fcc5d258324bcf79c9f90e163682c22d3b4b6ba852d3e0a
80084	1726824374	4540025	0x2259486456959983fa7c58505bb25264a7ef85f1066f85de160290f0d54492f1
80084	1726824376	4540026	0x0847090c4c722764d4ba630f04c5505a50b5fd9b83bf7d3c45b957817c7bf68e
80084	1726824379	4540027	0xc043c70d9b23fb82d1fc0481260b33723d38c819dd07147a9cbc338a2921239d
80084	1726824383	4540028	0x7e9516760e59f4816fb42f3e4841cdb3bacab6f2bdfe27c9d2c1fd1d5645b874
80084	1726824385	4540029	0xb989057241ff6449a61702d0944dd05e5fb0aba1d1462949966771f8977b264f
80084	1726824386	4540030	0x22cc795a3184d2d817f7f80c741a5da9ca615439ea9c10c1dca06ecd5723a07f
80084	1726824393	4540035	0x79566ab678329c8ec8be5dca159d44fadaff37df31ef5990ed49d5a3f7b3dace
80084	1726824394	4540036	0xe8f15677f08711a3f21a1c249a2b02346d4051c767ab70f114a4e4b4012144fb
80084	1726824395	4540037	0xe4bff8e96838ad79e2b94a1cb1f63a29b92d94a4d8f949d2324edd25ab0a1fb6
80084	1726824397	4540038	0xa2565b61fb65355d9f8ea891343d7cc00b0c5eb54a09140d7b1a5176c94eaac5
80084	1726824403	4540042	0x5f25e61add553f5e662cdca30adf647ce1e9be3dc0e4a6e731fa56c2e4a88101
80084	1726824408	4540045	0x6f8d64b866c5dec138eed1ec568d285637cfbc29ba2ff5865ce713614ec2549d
80084	1726824409	4540046	0x2b0a7214011856d5770d23539b5fc0a083ef675722331a5a521203a7fb9c5f48
80084	1726824411	4540047	0x9725955611bb1030146c3329b7f0b1637755591c8d73c56bedb452a32c141d49
80084	1726824414	4540049	0xb109a142e5973c0d6d97e5b6ec271131325870cd4114be5766fa6abbb72ffe97
80084	1726824417	4540051	0xbf90605e8c6be510a8fde2840b2f11a798d81d35dc61765ce862f3bdd419dff9
80084	1726824418	4540052	0xdc882b8e11cb0ac741ed2d9bd0d1036d209dbadbe22720601e725f2da79517ff
80084	1726824424	4540054	0xfc82d82a50cb0d49de69f3bd7ca1d794519a07054e46f4a3c324728653206cb8
80084	1726824425	4540055	0x973da0d7ea1cc44e31da854c3f4797d3031e08f51d33bd0c58e95147d0043713
80084	1726824427	4540056	0x8c69d397cce718f962fef67a62e390af4bc8b1a0774cd9f52cccb9b67af929e9
80084	1726824428	4540057	0x4388d6a2d27d0747117b596964030f2ef8f5b3569eeb0c6d928a3853fd5c9669
80084	1726824429	4540058	0x9656fb6cac9119eeb0605b754167e2604141acd5de996540f275658d748e4d46
80084	1726824430	4540059	0x0cc77adc09d8e093dba9f2d1f033cac7145e562f841fb73ef703f1bc73271d4c
80084	1726824432	4540060	0x14ea87d3db0655b626d31ca43ef0dfa7cf7c0a5169f9737f8d72d47c62624042
80084	1726824433	4540061	0x88f3c03a5a0d851bb951a2c385b7e4ec5df8730e03f092579ed2a33283c1637e
80084	1726824434	4540062	0x90d1af48c6c2f8dd14bdaa2de900e1f08d9d1705deac0c354197d4cb0eb78d79
80084	1726824438	4540064	0x88606e7c11b4de1946fce7cf49168899eec12fe08470dc4f2aed8ba3237a67f6
80084	1726824439	4540065	0x718108052dc9774cd6fd56b58da51c73b534dc9534956d02633e706fd0ca910f
80084	1726824440	4540066	0x1c7badeca6499ecac382ca9c79eeced6e201b53fe40d4aafc494659ada77f720
80084	1726824441	4540067	0x7e5e048a00414add273da46c175c3e6eb7fa7e6054e63656f4a6eb48bbd2bc5d
80084	1726824443	4540068	0x0b17e1897cac4b8f4ed06d2702f08dec4efee58618d057f8b132da2d2e27eb42
80084	1726824444	4540069	0x53c0a37a3470152af1cf57bf6fbbbe3f5a89bb823cb08796534b5395e0726ce3
80084	1726824451	4540071	0xafaaf7e903591af612dc4e6b4d7ed8ddf24bb53af4e0eac7f6b984a89fa51350
80084	1726824459	4540076	0xb098db2abd5791638f1f44e3413956eb5f429b9d921026cbe6085be0176994a8
80084	1726824460	4540077	0x4e5a71809be67dd857d32b2e58ff03ca6a14ad0fb2388869e539ed03f2684e04
80084	1726824461	4540078	0xc1cd768c2eb2c7e467d97dd4250911ce9646b051ae83b184b2049529d47075d5
80084	1726824462	4540079	0x92c3031df8efeb8cac7c50fe439588803089eabb3b55ab711f4c7ceb93339037
80084	1726824464	4540080	0x28ed9644fa38f709cebd458d3939ce3fee674061c2ee86032012cc946124e80b
80084	1726824465	4540081	0x95934ace81361176f8810b66799e0b921e8ae705e8f54b54a67130d1c3de7903
80084	1726824466	4540082	0x3c8f0009d360f2449a9282636b5b14f17b842da7214eacd2e0145ffacc153b8f
80084	1726824468	4540083	0x7fb05e71139075c624c34953fd95fd96d3f0b2cb380c89d68e5d3ddfc6540aaa
80084	1726824469	4540084	0x475ecae23be3fce5748f9b34fdb7a93d1b875074d00a2a3c7ff99446b8e36041
80084	1726826127	4540981	0x7f73cf2a2a59bff5cde684f0108785d280642451fc26b246c2c2b7e341c7699a
80084	1726826132	4540983	0x4979b6bd254b232822b4cde6bab84d4151ba9269b0664eb5163cf2a0cc65d116
80084	1726826133	4540984	0xb8d3214ccab8b629ff5cf85bea9782f0a12159ef184b5c3a0203988fa32ee74e
80084	1726826135	4540985	0xe211ae5916d8e3d919a660af7e802dbdb83652288d521593cdb723466eca73a9
80084	1726826139	4540986	0x2bc3ab98dd643563c38d4534446c14450ecbdc25e36567d78b084539a5e20110
80084	1726826141	4540987	0x70c6eb814a8f7038ee51bc41604f6508c669902cbddbcd074b0006cbb01fac6d
80084	1726826143	4540988	0xadc24ea0fbd691da50cd446f9a1746ae16e56d7bee839bfa1716a1c4550859c5
80084	1726826144	4540989	0x60c2332a25427fb86076ee06e338f85f2ac55817c8662d4d335b42a55fd21f21
80084	1726826148	4540990	0xee7a54bb98f233d60a85351c39aba95ae4165b4f57ac221ec122347104af5d32
80084	1726826157	4540991	0x7af702425f7999bafe27ef6152259fe8beb171a33d5e7f34ad184b7f0520abc9
80084	1726826158	4540992	0x47d785b7d2cc228faecc36354ca9fe9bf6e4bc527ca8c54f0b70c05c61db7233
\.


--
-- Data for Name: entity_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.entity_history (entity_id, block_timestamp, chain_id, block_number, log_index, entity_type, params, previous_block_timestamp, previous_chain_id, previous_block_number, previous_log_index) FROM stdin;
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_75000000000000000_1035181	1720170053	80084	1035181	319	RFVChanged	{"blockNumber":1035181,"blockTimestamp":1720170053,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_75000000000000000_1035181","newRFV":"75000000000000000","transactionHash":"0xa9d311097c44db3096d68b60e6dd5f5a0ece8faf42191a5a173ed48dd43d459d","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656250000000000_1542653	1721192466	80084	1542653	176	RFVChanged	{"blockNumber":1542653,"blockTimestamp":1721192466,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656250000000000_1542653","newRFV":"7656250000000000","transactionHash":"0x640148bc01a8566a1ad42fc7ec2cc5960c7062df057a5fa406b97e782629e3d7","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656978334284627_1542706	1721192571	80084	1542706	609	RFVChanged	{"blockNumber":1542706,"blockTimestamp":1721192571,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_7656978334284627_1542706","newRFV":"7656978334284627","transactionHash":"0x64a08e55890ad0fbf407edc129968e0544b783b2d69c4d4cf16575b432d969ec","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_18768089445395738_1546599	1721200134	80084	1546599	488	RFVChanged	{"blockNumber":1546599,"blockTimestamp":1721200134,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_18768089445395738_1546599","newRFV":"18768089445395738","transactionHash":"0x867a9a2560572a85bb418bced8bf0f0805b19f5bdddb754eabe10b0a5e9db075","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19207966541772200_1546614	1721200177	80084	1546614	401	RFVChanged	{"blockNumber":1546614,"blockTimestamp":1721200177,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19207966541772200_1546614","newRFV":"19207966541772200","transactionHash":"0x29eed826f447acac2a7d34f850ff2b343ea83bf89005d075de9056127f43c4be","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19722465645569670_1546710	1721200369	80084	1546710	492	RFVChanged	{"blockNumber":1546710,"blockTimestamp":1721200369,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_19722465645569670_1546710","newRFV":"19722465645569670","transactionHash":"0x4a3d306d4765054df4f641f5c17a924cd8b8dcef9f1d9b8d7316a1cfb8831397","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_20184710934137709_1546755	1721200459	80084	1546755	61	RFVChanged	{"blockNumber":1546755,"blockTimestamp":1721200459,"chain":"BERACHAIN_BARTIO","id":"80084_0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536_20184710934137709_1546755","newRFV":"20184710934137709","transactionHash":"0x5fad38cca040abbb6b581059ad8b8ad858ccce53b1eb76786104dcaae3f713d8","treasuryAddress":"0x180F8071Db1c8fb8A050F83e06d32f09bB0dc536"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2000000000000000_1632066	1721364459	80084	1632066	212	RFVChanged	{"blockNumber":1632066,"blockTimestamp":1721364459,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2000000000000000_1632066","newRFV":"2000000000000000","transactionHash":"0x08fba5be1e119f2187e64baf326ae0301438c0ca91a2df0556a43cd5f8baeb54","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2006530612244897_1632196	1721364708	80084	1632196	408	RFVChanged	{"blockNumber":1632196,"blockTimestamp":1721364708,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2006530612244897_1632196","newRFV":"2006530612244897","transactionHash":"0x40b600b34c61dd1f93a233b7f4a3e7a5a6e337f66f4d457e4af3dd2455c162af","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2013219047619047_1632236	1721364783	80084	1632236	344	RFVChanged	{"blockNumber":1632236,"blockTimestamp":1721364783,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2013219047619047_1632236","newRFV":"2013219047619047","transactionHash":"0xac379eeeca34d737c4ecb3d154aab07bfa4f64f1bfbe5f1e4cca5a50054b84ab","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019792824101069_1632340	1721364983	80084	1632340	86	RFVChanged	{"blockNumber":1632340,"blockTimestamp":1721364983,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019792824101069_1632340","newRFV":"2019792824101069","transactionHash":"0xe13a14f7f4c5af1a5734a04d038fbada35299b56fee1ed21c08a071c73c5379d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019819927834800_1632618	1721365512	80084	1632618	227	RFVChanged	{"blockNumber":1632618,"blockTimestamp":1721365512,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2019819927834800_1632618","newRFV":"2019819927834800","transactionHash":"0xb0d7ea977cae26e6b2d5d26c90b0368a40899320296e817f230c264fe0d8ed62","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63244309723753167_1642488	1721384583	80084	1642488	241	RFVChanged	{"blockNumber":1642488,"blockTimestamp":1721384583,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63244309723753167_1642488","newRFV":"63244309723753167","transactionHash":"0x735edeb1345d95b3eb93b543cfde7e67dcd9ca1739d583241e2dadc6ab0196a5","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63455124089499011_1643662	1721386829	80084	1643662	292	RFVChanged	{"blockNumber":1643662,"blockTimestamp":1721386829,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63455124089499011_1643662","newRFV":"63455124089499011","transactionHash":"0x34d0468b88748d0f7006adadb95b7429fa8bf8d1a837ee81170f38b978a88e13","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63662324494689212_1643694	1721386936	80084	1643694	273	RFVChanged	{"blockNumber":1643694,"blockTimestamp":1721386936,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63662324494689212_1643694","newRFV":"63662324494689212","transactionHash":"0x083dd9d5092f850aab391aeb85146008c2610d4d0f9762214c669341b5328e6c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63874532243004843_1644163	1721387815	80084	1644163	257	RFVChanged	{"blockNumber":1644163,"blockTimestamp":1721387815,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_63874532243004843_1644163","newRFV":"63874532243004843","transactionHash":"0xb3b463e78aa69459ad1791e0c66496591a03473aeb7731acf14d61e7f860a9be","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64091977459151242_1644262	1721388040	80084	1644262	315	RFVChanged	{"blockNumber":1644262,"blockTimestamp":1721388040,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64091977459151242_1644262","newRFV":"64091977459151242","transactionHash":"0x108bd3448677a82aa38ca482ce5fccc0a6325b86eac7b31892225536788d667a","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64305617384015080_1644517	1721388518	80084	1644517	215	RFVChanged	{"blockNumber":1644517,"blockTimestamp":1721388518,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64305617384015080_1644517","newRFV":"64305617384015080","transactionHash":"0x064cc4a25553372096aa718eb63ff5999545e74d6459fb36e29c6c37e143b726","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64524530124045769_1644783	1721389019	80084	1644783	199	RFVChanged	{"blockNumber":1644783,"blockTimestamp":1721389019,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64524530124045769_1644783","newRFV":"64524530124045769","transactionHash":"0x83d87e9144a39612c6baceeaacf3c4c4d36805a9531b75e68aa3d3280763c313","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64748963272303320_1644794	1721389045	80084	1644794	198	RFVChanged	{"blockNumber":1644794,"blockTimestamp":1721389045,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64748963272303320_1644794","newRFV":"64748963272303320","transactionHash":"0xc747414393a38ce5af324135697b4d9b95a2fb45c7f252914d8c0af198f9d2c9","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64969385274932437_1644940	1721389340	80084	1644940	645	RFVChanged	{"blockNumber":1644940,"blockTimestamp":1721389340,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_64969385274932437_1644940","newRFV":"64969385274932437","transactionHash":"0xcb803ef77bf89b32efb005967a63f88528c1d58acf1ccbd2086c6cd8d7997d22","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65185949892515546_1644990	1721389438	80084	1644990	198	RFVChanged	{"blockNumber":1644990,"blockTimestamp":1721389438,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65185949892515546_1644990","newRFV":"65185949892515546","transactionHash":"0xa66d7605c2ac487ad1357910e921b9fc3158ef0d4f5c94489e4a20a605bb5959","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65398801973797229_1645013	1721389486	80084	1645013	514	RFVChanged	{"blockNumber":1645013,"blockTimestamp":1721389486,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65398801973797229_1645013","newRFV":"65398801973797229","transactionHash":"0x313799fbe3a167607afbc82230454f9d56c01ee31f2268fef135bd6cb84c87b6","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65616797980376553_1645179	1721389788	80084	1645179	250	RFVChanged	{"blockNumber":1645179,"blockTimestamp":1721389788,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65616797980376553_1645179","newRFV":"65616797980376553","transactionHash":"0x66998f0a9230535a26950a054ad05a3c6331bbc7993d4a9665302467be0d17c3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65831056912557374_1646408	1721392151	80084	1646408	555	RFVChanged	{"blockNumber":1646408,"blockTimestamp":1721392151,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_65831056912557374_1646408","newRFV":"65831056912557374","transactionHash":"0x89f7c1fb7e741b7f7efcac246eb7711402afc4a9659b4072c8232cf0e63c933b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66050493768932566_1646528	1721392384	80084	1646528	183	RFVChanged	{"blockNumber":1646528,"blockTimestamp":1721392384,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66050493768932566_1646528","newRFV":"66050493768932566","transactionHash":"0x470e1f84a2a493f7528dee321d0d96f059459708bf4a4c63f6a85081d9f53595","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66275346513677868_1646536	1721392399	80084	1646536	285	RFVChanged	{"blockNumber":1646536,"blockTimestamp":1721392399,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66275346513677868_1646536","newRFV":"66275346513677868","transactionHash":"0xd3e142bd20b9f86eeeea125695b02de1c063f8b87b6f0f7e9d226a2d808a1f9b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66505869458073269_1646542	1721392408	80084	1646542	94	RFVChanged	{"blockNumber":1646542,"blockTimestamp":1721392408,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66505869458073269_1646542","newRFV":"66505869458073269","transactionHash":"0x91991e22d66456f84bd9b02f5fb374c4d5089917d69b97dd444c88da2ea59820","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66742334771701974_1646546	1721392412	80084	1646546	386	RFVChanged	{"blockNumber":1646546,"blockTimestamp":1721392412,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66742334771701974_1646546","newRFV":"66742334771701974","transactionHash":"0x468062095fdc3d71c7ffb2de7b8798b6d52d9a5ac1fb1f445c5c4d939cda9c6c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66974482023081807_1646698	1721392695	80084	1646698	208	RFVChanged	{"blockNumber":1646698,"blockTimestamp":1721392695,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_66974482023081807_1646698","newRFV":"66974482023081807","transactionHash":"0xc3aebe69d0f2b2f95d39cfd0cd5ac54fa6f7b1ecb4bec445944f19b6d1e6563f","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67202480259756128_1651085	1721401116	80084	1651085	108	RFVChanged	{"blockNumber":1651085,"blockTimestamp":1721401116,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67202480259756128_1651085","newRFV":"67202480259756128","transactionHash":"0x0b9f60f6c141e925d01cdf14ad3c18402b3d0f7d063270fd399366ca0281290c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67426488527288649_1652060	1721402898	80084	1652060	37	RFVChanged	{"blockNumber":1652060,"blockTimestamp":1721402898,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67426488527288649_1652060","newRFV":"67426488527288649","transactionHash":"0x53f8f5d6d6e4d2156e197d54ced4c9b15defcc99836d4a5434e2f2e2eebb39bf","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67656025509509206_1652087	1721402947	80084	1652087	104	RFVChanged	{"blockNumber":1652087,"blockTimestamp":1721402947,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67656025509509206_1652087","newRFV":"67656025509509206","transactionHash":"0x3fbf0bb1b310f08cdca218e910ce1b85c50c31fcab54b1079201f45ea7a50ce4","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67891350815629238_1656270	1721410625	80084	1656270	111	RFVChanged	{"blockNumber":1656270,"blockTimestamp":1721410625,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_67891350815629238_1656270","newRFV":"67891350815629238","transactionHash":"0x38ea21ec1e7e322d11ff5c4340fa979e498e827ca5ce61654d13f5a49e36e068","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68132742285195920_1656307	1721410697	80084	1656307	252	RFVChanged	{"blockNumber":1656307,"blockTimestamp":1721410697,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68132742285195920_1656307","newRFV":"68132742285195920","transactionHash":"0x0f8f427f5caf1a041ef82179b41c106d06ff891d885be399dfa5daefc230287c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68380497711687541_1656336	1721410745	80084	1656336	271	RFVChanged	{"blockNumber":1656336,"blockTimestamp":1721410745,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68380497711687541_1656336","newRFV":"68380497711687541","transactionHash":"0x6a61f4302ed34204326bacbbb13563c2938d43bc38e64f281aacc25daa36333d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68623628370217986_1679116	1721452702	80084	1679116	596	RFVChanged	{"blockNumber":1679116,"blockTimestamp":1721452702,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68623628370217986_1679116","newRFV":"68623628370217986","transactionHash":"0xb7a0eae7bef614dd0d0ba3bc79b4e3f331bbbfaacda520ff5472b1302d0227cb","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68862319251505700_2074670	1722174122	80084	2074670	104	RFVChanged	{"blockNumber":2074670,"blockTimestamp":1722174122,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68862319251505700_2074670","newRFV":"68862319251505700","transactionHash":"0xd6773228fa00aa87aaabb80a404d7608112e0ea53dd228bd2a2bba58c7db9cde","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68863303584836276_2076422	1722177267	80084	2076422	44	RFVChanged	{"blockNumber":2076422,"blockTimestamp":1722177267,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68863303584836276_2076422","newRFV":"68863303584836276","transactionHash":"0x10d88ee7e33c7a085aeebe9d78c6b7a67df736289e9d3986655cc746661827bc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864287932237131_2102177	1722223355	80084	2102177	201	RFVChanged	{"blockNumber":2102177,"blockTimestamp":1722223355,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864287932237131_2102177","newRFV":"68864287932237131","transactionHash":"0xf8bf88550970d08d4d68b886997c49a6c53bce41817a0a470a794815c8b75f2d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864091065571016_2106907	1722231968	80084	2106907	258	RFVChanged	{"blockNumber":2106907,"blockTimestamp":1722231968,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864091065571016_2106907","newRFV":"68864091065571016","transactionHash":"0xd0d042de295f0ff0fb5b624a75193a0d06f1f9414d7084ab97ebc24739e221ad","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68865075424228296_2109865	1722237301	80084	2109865	56	RFVChanged	{"blockNumber":2109865,"blockTimestamp":1722237301,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68865075424228296_2109865","newRFV":"68865075424228296","transactionHash":"0x9e211bedc13407360d7ec5a9f7194cc479bc3a948966d4d98620c4a9d6a4865c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864878552496840_2110031	1722237607	80084	2110031	75	RFVChanged	{"blockNumber":2110031,"blockTimestamp":1722237607,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_68864878552496840_2110031","newRFV":"68864878552496840","transactionHash":"0x8a39e5c8f15cf23e8a32d2d981d64fb589c6e0d02382204dae710f149d628c66","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69109731454016829_2111006	1722239407	80084	2111006	59	RFVChanged	{"blockNumber":2111006,"blockTimestamp":1722239407,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69109731454016829_2111006","newRFV":"69109731454016829","transactionHash":"0x6fd3c70a06141d3d2c5817951a915fb1fcc522296a5668ac9e507ba5294eff15","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2115280	1722247042	80084	2115280	50	RFVChanged	{"blockNumber":2115280,"blockTimestamp":1722247042,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2115280","newRFV":"69110741276576888","transactionHash":"0xb6bf7a19a15f5582b2ace4ec3b72e0a27d77c7b99a1d9f40c65381d0cc55a8a6","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2163600	1722333711	80084	2163600	230	RFVChanged	{"blockNumber":2163600,"blockTimestamp":1722333711,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69110741276576888_2163600","newRFV":"69110741276576888","transactionHash":"0xae7968a46c0255b63b2ca82a98171896e34c8e7b63721ef7ae8d328154ac73e3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69114732623000800_2164169	1722334725	80084	2164169	440	RFVChanged	{"blockNumber":2164169,"blockTimestamp":1722334725,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69114732623000800_2164169","newRFV":"69114732623000800","transactionHash":"0x4eaa6fb5deaa823f7869d1691b15c35f6189a78d45cb61a2523c72f831701184","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69163204105883618_2167496	1722340700	80084	2167496	73	RFVChanged	{"blockNumber":2167496,"blockTimestamp":1722340700,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69163204105883618_2167496","newRFV":"69163204105883618","transactionHash":"0xaa4d026a9bd074e10e89dcd24d69784fb77a5c6c6285328b31724e42e08429a7","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69414706666268649_2167966	1722341529	80084	2167966	125	RFVChanged	{"blockNumber":2167966,"blockTimestamp":1722341529,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69414706666268649_2167966","newRFV":"69414706666268649","transactionHash":"0x772490d8f634804dd04c78fd066bfbd2fa32b894df1ae7071253284b28411bd3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69661514512193160_2179404	1722361899	80084	2179404	42	RFVChanged	{"blockNumber":2179404,"blockTimestamp":1722361899,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69661514512193160_2179404","newRFV":"69661514512193160","transactionHash":"0xa1f03e1f2ad50ecf9719d189512a9edfefd6950ba7e50a67a23a4f20fd2045a7","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69914829110419317_2180230	1722363392	80084	2180230	133	RFVChanged	{"blockNumber":2180230,"blockTimestamp":1722363392,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69914829110419317_2180230","newRFV":"69914829110419317","transactionHash":"0x008b405f2a63df83c81475ba50179deb8160fabfeeab4cebfbc5911e8ae45176","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69946173243021746_2180239	1722363407	80084	2180239	128	RFVChanged	{"blockNumber":2180239,"blockTimestamp":1722363407,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69946173243021746_2180239","newRFV":"69946173243021746","transactionHash":"0x78183f90a3c954252abce0e28e5df66e5f08125f06778cdc7778d669ef29537b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69939904416501260_2203939	1722406388	80084	2203939	99	RFVChanged	{"blockNumber":2203939,"blockTimestamp":1722406388,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_69939904416501260_2203939","newRFV":"69939904416501260","transactionHash":"0x44f1e736c153995402b840f3c5deea731226b6d5d2ba84b8a18e97ee57c63ab1","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71529651223560266_2254144	1722501484	80084	2254144	248	RFVChanged	{"blockNumber":2254144,"blockTimestamp":1722501484,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71529651223560266_2254144","newRFV":"71529651223560266","transactionHash":"0x9c789b8eeb93a59b7c801b08822c02e0622592d056544892c897a9e7a228a687","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71789759046191394_2259757	1722513306	80084	2259757	15	RFVChanged	{"blockNumber":2259757,"blockTimestamp":1722513306,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_71789759046191394_2259757","newRFV":"71789759046191394","transactionHash":"0xde15a3472c4c42a9ff5f62c5a99b02522faf220f1e1d62eb8fadd1a205ab2341","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76335213591645939_2260402	1722514595	80084	2260402	307	RFVChanged	{"blockNumber":2260402,"blockTimestamp":1722514595,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76335213591645939_2260402","newRFV":"76335213591645939","transactionHash":"0x8ba4f21a19fb8cc583dc6fb251f09e3bbfade9ab5498572d2c9471573ee557d2","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76606627684416236_2289928	1722571418	80084	2289928	75	RFVChanged	{"blockNumber":2289928,"blockTimestamp":1722571418,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76606627684416236_2289928","newRFV":"76606627684416236","transactionHash":"0xf92cb44850932da48443486bae53dd08dfb120527da8af59b3bbf3ed383bcf32","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76885197239632295_2289959	1722571464	80084	2289959	59	RFVChanged	{"blockNumber":2289959,"blockTimestamp":1722571464,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76885197239632295_2289959","newRFV":"76885197239632295","transactionHash":"0x6a22701557813d4f96478100fa5eb74d8c7575b6374cfaba35bf90cb27adec43","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76886346208955926_2289968	1722571482	80084	2289968	27	RFVChanged	{"blockNumber":2289968,"blockTimestamp":1722571482,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76886346208955926_2289968","newRFV":"76886346208955926","transactionHash":"0x53625077cae97f0ab502cdc2cf330c4d2bff3ec81f70ca98af83702d62e8714b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898695471050872_2290024	1722571596	80084	2290024	6	RFVChanged	{"blockNumber":2290024,"blockTimestamp":1722571596,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898695471050872_2290024","newRFV":"76898695471050872","transactionHash":"0xfdd65536b25e5f86373b3fd095f62c4241e1950930c99095688edbf890dc4d49","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898465677186146_2290138	1722571831	80084	2290138	77	RFVChanged	{"blockNumber":2290138,"blockTimestamp":1722571831,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76898465677186146_2290138","newRFV":"76898465677186146","transactionHash":"0x4ab9ff3ca885642452ddc0dabae7553c0730c9f3e59057fc770b9a9843695c26","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76912255688465741_2290229	1722571993	80084	2290229	23	RFVChanged	{"blockNumber":2290229,"blockTimestamp":1722571993,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_76912255688465741_2290229","newRFV":"76912255688465741","transactionHash":"0x5435183f7046d3c0f273d536153d0908a296692b89822efefa55ff24ed52b86a","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77185721486469175_2290248	1722572048	80084	2290248	291	RFVChanged	{"blockNumber":2290248,"blockTimestamp":1722572048,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77185721486469175_2290248","newRFV":"77185721486469175","transactionHash":"0x8903a4b923ba4804aab78bda7a72e65a7e8202c25b8a578d097a513b67771f9f","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77454193561204720_2290693	1722572932	80084	2290693	534	RFVChanged	{"blockNumber":2290693,"blockTimestamp":1722572932,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77454193561204720_2290693","newRFV":"77454193561204720","transactionHash":"0xd793ce23c266da52355aa4a9350440f1c906b870784edb06987a10fd9984b1fb","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77729586249422337_2296184	1722583770	80084	2296184	35	RFVChanged	{"blockNumber":2296184,"blockTimestamp":1722583770,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_77729586249422337_2296184","newRFV":"77729586249422337","transactionHash":"0x87b8bb602b90a960d32f9bd0ecfecfe5813aee430486a613f47ebcfe38904e41","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78012239290329327_2296190	1722583778	80084	2296190	32	RFVChanged	{"blockNumber":2296190,"blockTimestamp":1722583778,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78012239290329327_2296190","newRFV":"78012239290329327","transactionHash":"0xe273493349f2a240211d0b25683e9206a6cd1b02698174080244d115243b407c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78289616141139387_2296271	1722583952	80084	2296271	28	RFVChanged	{"blockNumber":2296271,"blockTimestamp":1722583952,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78289616141139387_2296271","newRFV":"78289616141139387","transactionHash":"0x988fc80aece7d67f997862937af1613a0b61e904d9d6b31d6bcd78dd6a9ce0c1","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78574305654379894_2296343	1722584159	80084	2296343	643	RFVChanged	{"blockNumber":2296343,"blockTimestamp":1722584159,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78574305654379894_2296343","newRFV":"78574305654379894","transactionHash":"0x623a5dddf3feb51944c0feb95f383a65d31f1f9bb4eebb0a230089a619e359b3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78853680963373245_2296372	1722584213	80084	2296372	245	RFVChanged	{"blockNumber":2296372,"blockTimestamp":1722584213,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78853680963373245_2296372","newRFV":"78853680963373245","transactionHash":"0xb27ed368feeadb53e7c9236b5bf442753548a1fae035184d791a8ce178cf5834","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78854833163277732_2299281	1722590257	80084	2299281	203	RFVChanged	{"blockNumber":2299281,"blockTimestamp":1722590257,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78854833163277732_2299281","newRFV":"78854833163277732","transactionHash":"0xaa657da492386dc670b76184cc70d9d04ab47f6076f55acaf3512b7b763e2fea","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78923726254072218_2304025	1722599893	80084	2304025	70	RFVChanged	{"blockNumber":2304025,"blockTimestamp":1722599893,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78923726254072218_2304025","newRFV":"78923726254072218","transactionHash":"0xe90a6f659f67db1068823ba6751cb88b9542851e444e23e4dc1fb74f3ea791ae","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78949583734301437_2313737	1722618288	80084	2313737	42	RFVChanged	{"blockNumber":2313737,"blockTimestamp":1722618288,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_78949583734301437_2313737","newRFV":"78949583734301437","transactionHash":"0xbd5843888073acb39b67b0655a9e276e0a87a62784f5b02ddb5c59745801273e","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79018559605813736_2339726	1722664005	80084	2339726	86	RFVChanged	{"blockNumber":2339726,"blockTimestamp":1722664005,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79018559605813736_2339726","newRFV":"79018559605813736","transactionHash":"0x79bf3c5853c6c3b0b97b6583b695c5c71f1154ed3ed6dedce1a0181fffe2d9dc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79026641869444651_2346527	1722675634	80084	2346527	44	RFVChanged	{"blockNumber":2346527,"blockTimestamp":1722675634,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79026641869444651_2346527","newRFV":"79026641869444651","transactionHash":"0x273b2bfa1f236a3553a229a4d4186b69b19574fffbb4998c18f15514c0665339","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79314011476242631_2388526	1722747737	80084	2388526	69	RFVChanged	{"blockNumber":2388526,"blockTimestamp":1722747737,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79314011476242631_2388526","newRFV":"79314011476242631","transactionHash":"0x6c6a39a731170b4c72556ed77f09d226dd25d826e06415be1bb06c8aee2a4715","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79596016850380383_2388620	1722747890	80084	2388620	41	RFVChanged	{"blockNumber":2388620,"blockTimestamp":1722747890,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79596016850380383_2388620","newRFV":"79596016850380383","transactionHash":"0x03a3cbfb50b8e34de0fde58b4d9ec8a539e6e301fecebaf9657a320facda647e","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79885456911654493_2388642	1722747941	80084	2388642	14	RFVChanged	{"blockNumber":2388642,"blockTimestamp":1722747941,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_79885456911654493_2388642","newRFV":"79885456911654493","transactionHash":"0x4e938601cd311eb6c76033192c1130bb0649bb79cb806d66574a04845524109b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80100341826883850_2388665	1722747969	80084	2388665	64	RFVChanged	{"blockNumber":2388665,"blockTimestamp":1722747969,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80100341826883850_2388665","newRFV":"80100341826883850","transactionHash":"0x487b15e4ea398d6ad80aea20e22230a11bd205a0c5c12dbd48599254632202ad","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80057364843837979_2396172	1722761298	80084	2396172	92	RFVChanged	{"blockNumber":2396172,"blockTimestamp":1722761298,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80057364843837979_2396172","newRFV":"80057364843837979","transactionHash":"0x96f88a731cabd56bb055377015ad405278d145d80df27607d1122d7ce9bf16d9","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80342013252171625_2396649	1722762129	80084	2396649	61	RFVChanged	{"blockNumber":2396649,"blockTimestamp":1722762129,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80342013252171625_2396649","newRFV":"80342013252171625","transactionHash":"0xb3c36dc50a53bdea02966866a152aa5b612fc90151dfef5fd2d439709ccfd35c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80634166027634067_2413027	1722791504	80084	2413027	490	RFVChanged	{"blockNumber":2413027,"blockTimestamp":1722791504,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80634166027634067_2413027","newRFV":"80634166027634067","transactionHash":"0x02d10bab62c36c8d00b7a5a73228e73e221083d834846beb15ebc7f886247266","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80670315840548075_2413072	1722791585	80084	2413072	26	RFVChanged	{"blockNumber":2413072,"blockTimestamp":1722791585,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80670315840548075_2413072","newRFV":"80670315840548075","transactionHash":"0xf9ddaab720f7df6fe2c4dff0943eb0a2b8842c43677ae953a515c5dfc51ed4cb","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80663085877965274_2413087	1722791614	80084	2413087	44	RFVChanged	{"blockNumber":2413087,"blockTimestamp":1722791614,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80663085877965274_2413087","newRFV":"80663085877965274","transactionHash":"0x059a93ddad65fca5a89f72814491c9ec2d65f9cb1c3695fb907fee9d9f14c913","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80712697341931636_2413119	1722791688	80084	2413119	235	RFVChanged	{"blockNumber":2413119,"blockTimestamp":1722791688,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_80712697341931636_2413119","newRFV":"80712697341931636","transactionHash":"0x1a6dedeb3b45f9a163de3ec5497934061432931f0fedeea75e7bb81df544a67e","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81013023657622544_2418472	1722800949	80084	2418472	55	RFVChanged	{"blockNumber":2418472,"blockTimestamp":1722800949,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81013023657622544_2418472","newRFV":"81013023657622544","transactionHash":"0x877036fd77a71c203fe95a67432f835481208f4ef6fcc6cd2f0a4bfd03c28ffc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81307616470922990_2418499	1722800997	80084	2418499	128	RFVChanged	{"blockNumber":2418499,"blockTimestamp":1722800997,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81307616470922990_2418499","newRFV":"81307616470922990","transactionHash":"0x8298897b80d66052df1aa398adae102f10eff333931ff2430b279205f139f967","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81596710218375161_2444255	1722848085	80084	2444255	157	RFVChanged	{"blockNumber":2444255,"blockTimestamp":1722848085,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81596710218375161_2444255","newRFV":"81596710218375161","transactionHash":"0xa6977057f4c5768def134322ae66c5934a2ae93d446cafc121e9524c9620257d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81893425528260161_2451393	1722861767	80084	2451393	350	RFVChanged	{"blockNumber":2451393,"blockTimestamp":1722861767,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_81893425528260161_2451393","newRFV":"81893425528260161","transactionHash":"0x7cf605090febd14b4959f2c16a31f1e9d1e10ee12dfc78c0c82b2e5b36dc2b05","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82184602152360642_2458544	1722875449	80084	2458544	61	RFVChanged	{"blockNumber":2458544,"blockTimestamp":1722875449,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82184602152360642_2458544","newRFV":"82184602152360642","transactionHash":"0xbfac7130d79df6bf6e5f852c4b89c25a88e12bc5b7a5795d2f2410616f5c250d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82483455251096499_2474675	1722906600	80084	2474675	313	RFVChanged	{"blockNumber":2474675,"blockTimestamp":1722906600,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82483455251096499_2474675","newRFV":"82483455251096499","transactionHash":"0x1effff09ad51550da1f07d57e270052bdef919d9fd686bf65e2aee3991388cfc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82776729758655953_2479145	1722915097	80084	2479145	65	RFVChanged	{"blockNumber":2479145,"blockTimestamp":1722915097,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82776729758655953_2479145","newRFV":"82776729758655953","transactionHash":"0x0f972c3977786705c0f37ba3fac800ce1c4470db9a06108b64048cd1e7e924c7","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83077736048687429_2479160	1722915123	80084	2479160	199	RFVChanged	{"blockNumber":2479160,"blockTimestamp":1722915123,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83077736048687429_2479160","newRFV":"83077736048687429","transactionHash":"0xb26d6cab407a6d3460cf4b4b14add111d0c01c14be523a83de0f838417ff72de","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83373123554638318_2490025	1722936835	80084	2490025	127	RFVChanged	{"blockNumber":2490025,"blockTimestamp":1722936835,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83373123554638318_2490025","newRFV":"83373123554638318","transactionHash":"0x187716a368ce48255be024da7411a750108af9af8daf20f339b581648722a58b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83385198354167623_2500576	1722958546	80084	2500576	276	RFVChanged	{"blockNumber":2500576,"blockTimestamp":1722958546,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83385198354167623_2500576","newRFV":"83385198354167623","transactionHash":"0x679bb3dc47a806b404733f1557dae508514cd6dc827fa6e897fcda511d9d43b1","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83438085542211618_2501547	1722960549	80084	2501547	110	RFVChanged	{"blockNumber":2501547,"blockTimestamp":1722960549,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83438085542211618_2501547","newRFV":"83438085542211618","transactionHash":"0x7b59b3f3441ef3a7a8057b27b8228ab7acaa62ac0d46e2cdbf33355ade69d494","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83741496762365115_2501699	1722960850	80084	2501699	63	RFVChanged	{"blockNumber":2501699,"blockTimestamp":1722960850,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83741496762365115_2501699","newRFV":"83741496762365115","transactionHash":"0x03c639297a618529e20df9e4c3086dadc9855e12d1a4c094827c6a26fc36215a","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83779039650079252_2501738	1722960927	80084	2501738	150	RFVChanged	{"blockNumber":2501738,"blockTimestamp":1722960927,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83779039650079252_2501738","newRFV":"83779039650079252","transactionHash":"0x06669b2027c545f49f81161eb10e7b7c72b8892600dca8ee30863b0d57d20474","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83771531072536424_2501752	1722960971	80084	2501752	15	RFVChanged	{"blockNumber":2501752,"blockTimestamp":1722960971,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83771531072536424_2501752","newRFV":"83771531072536424","transactionHash":"0x6aebb7fca8b74708e467f9ee73d9c0aa24cde9323b8e12a4ead35d7e6829fcb3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83884200130516922_2544453	1723051439	80084	2544453	39	RFVChanged	{"blockNumber":2544453,"blockTimestamp":1723051439,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83884200130516922_2544453","newRFV":"83884200130516922","transactionHash":"0x72d1e07a4466c87e4afb69468b09cefbbfbc7b6324fdf11572541cddeacb3397","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83861666318920822_2544475	1723051482	80084	2544475	155	RFVChanged	{"blockNumber":2544475,"blockTimestamp":1723051482,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83861666318920822_2544475","newRFV":"83861666318920822","transactionHash":"0xf643174e3de96eb77b11e14e3833bcf073f5ec76813e69f3fb271ab429bfa534","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84173709728479597_2544558	1723051718	80084	2544558	39	RFVChanged	{"blockNumber":2544558,"blockTimestamp":1723051718,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84173709728479597_2544558","newRFV":"84173709728479597","transactionHash":"0x0e81902b88bf42e1097d6e5632ab4b645927d5823cbcb71ec15c2e54dde2b527","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84201926645368331_2546710	1723056375	80084	2546710	63	RFVChanged	{"blockNumber":2546710,"blockTimestamp":1723056375,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84201926645368331_2546710","newRFV":"84201926645368331","transactionHash":"0xf2da022adeab2778962ca1219903cea2d85b54d48e1f08bae2298182155320ce","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84508115469533307_2549027	1723061573	80084	2549027	41	RFVChanged	{"blockNumber":2549027,"blockTimestamp":1723061573,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84508115469533307_2549027","newRFV":"84508115469533307","transactionHash":"0xc1c3e6c38058e0b0699c3ebe205fad706a52a778449d2effc7934187e27175bb","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84822564271280407_2574332	1723109270	80084	2574332	57	RFVChanged	{"blockNumber":2574332,"blockTimestamp":1723109270,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84822564271280407_2574332","newRFV":"84822564271280407","transactionHash":"0xe42faa31c877350a351ee94733fb0571751385071b9eabd6ad6c5463b5a1bbd1","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84861476183529736_2574390	1723109367	80084	2574390	59	RFVChanged	{"blockNumber":2574390,"blockTimestamp":1723109367,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_84861476183529736_2574390","newRFV":"84861476183529736","transactionHash":"0x00f87a09e02fe52a5b9c1cda4d2c78aaafb4e328ca2ca1acb2150407b71cb5cc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82986055353812180_2574744	1723109974	80084	2574744	112	RFVChanged	{"blockNumber":2574744,"blockTimestamp":1723109974,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_82986055353812180_2574744","newRFV":"82986055353812180","transactionHash":"0xf2734e5ed348658d8d8992bd5d1b65c8ac7686b530946ebfd92beb0073f026bc","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2583991	1723125689	80084	2583991	29	RFVChanged	{"blockNumber":2583991,"blockTimestamp":1723125689,"chain":"BERACHAIN_BARTIO","id":"80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2583991","newRFV":"0","transactionHash":"0x9d7dd8abe812fb562a14f8382874e6e6e9678923de7a15ce90b58b49e3231f1a","treasuryAddress":"0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83281116883959067_2593405	1723141581	80084	2593405	41	RFVChanged	{"blockNumber":2593405,"blockTimestamp":1723141581,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_83281116883959067_2593405","newRFV":"83281116883959067","transactionHash":"0x438eaf3c7484643f232f9c0abde1e2e285d69116201749c441cb63484b0cb089","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2596078	1723146048	80084	2596078	76	RFVChanged	{"blockNumber":2596078,"blockTimestamp":1723146048,"chain":"BERACHAIN_BARTIO","id":"80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_0_2596078","newRFV":"0","transactionHash":"0xc6749e404e8b9c86b746a138d4da16f767ea36931268732c6ed4777818a0e156","treasuryAddress":"0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_194392227995070179_2597609	1723148590	80084	2597609	78	RFVChanged	{"blockNumber":2597609,"blockTimestamp":1723148590,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_194392227995070179_2597609","newRFV":"194392227995070179","transactionHash":"0x36639fceae07956f38dc3ca1bf6401e6f17cc1509d80c239965ddccb1491ba43","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1305503339106181290_2598063	1723149367	80084	2598063	59	RFVChanged	{"blockNumber":2598063,"blockTimestamp":1723149367,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1305503339106181290_2598063","newRFV":"1305503339106181290","transactionHash":"0xc18d9a3a9c901b6a2281e595ab162e8bf45a2ddda2e5edb3d4435a014be6d655","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_500000000000000_2600989	1723154293	80084	2600989	90	RFVChanged	{"blockNumber":2600989,"blockTimestamp":1723154293,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_500000000000000_2600989","newRFV":"500000000000000","transactionHash":"0xc4c63af1a4ec1c51861443a6d0b98835e205036e0ae455a522b8425905763364","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7500000000000000_2601272	1723154779	80084	2601272	241	RFVChanged	{"blockNumber":2601272,"blockTimestamp":1723154779,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7500000000000000_2601272","newRFV":"7500000000000000","transactionHash":"0xe0b14054f707617ce85737dfc718efcbcb86d1cfe60fb1135f78bdb2a933425d","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1749947783550625734_2624430	1723194408	80084	2624430	162	RFVChanged	{"blockNumber":2624430,"blockTimestamp":1723194408,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1749947783550625734_2624430","newRFV":"1749947783550625734","transactionHash":"0xea41ec57e8217617999b20642ab5aeeb2287dabd123d78909c1497a62632e965","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1861058894661736845_2628721	1723201819	80084	2628721	121	RFVChanged	{"blockNumber":2628721,"blockTimestamp":1723201819,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1861058894661736845_2628721","newRFV":"1861058894661736845","transactionHash":"0x4a9578b08bd595a5a22e6c05d3856178167f1dc7304a6a56220927e2773f507a","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1883281116883959067_2633070	1723209241	80084	2633070	116	RFVChanged	{"blockNumber":2633070,"blockTimestamp":1723209241,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1883281116883959067_2633070","newRFV":"1883281116883959067","transactionHash":"0xbbdfc4f44fbc2d1ae6b615d6fffcd1d68dbbb28d8442fca4c2307993fa248e49","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7530000000000000_2659845	1723254433	80084	2659845	25	RFVChanged	{"blockNumber":2659845,"blockTimestamp":1723254433,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7530000000000000_2659845","newRFV":"7530000000000000","transactionHash":"0x6e9fa3f7db71fbae4da49f5834a7454e6d0b8c3c0a4163a364ee299aa0ccf130","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1994392227995070179_2660363	1723255327	80084	2660363	122	RFVChanged	{"blockNumber":2660363,"blockTimestamp":1723255327,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_1994392227995070179_2660363","newRFV":"1994392227995070179","transactionHash":"0x7b0ad1953ee037d688265653637cabb8e352aafdb5b496be10fe2445a8bcd4ce","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7550000000000000_2666071	1723264979	80084	2666071	32	RFVChanged	{"blockNumber":2666071,"blockTimestamp":1723264979,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7550000000000000_2666071","newRFV":"7550000000000000","transactionHash":"0x5c698608a7bca53024ede8060614470a178a7f91b453f7bfebd540192af0cabe","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7650000000000000_2666246	1723265279	80084	2666246	20	RFVChanged	{"blockNumber":2666246,"blockTimestamp":1723265279,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7650000000000000_2666246","newRFV":"7650000000000000","transactionHash":"0x4feb25476e824de6c77e41ad934acd59a94f13a3290d46cd4526318f5c059d51","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7652000000000000_2669719	1723271161	80084	2669719	58	RFVChanged	{"blockNumber":2669719,"blockTimestamp":1723271161,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7652000000000000_2669719","newRFV":"7652000000000000","transactionHash":"0x65022c9fccf08c3aa974505f57613e2ce8df5ef5dfcb946f694bdc63406f0500","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7732000000000000_2675754	1723281599	80084	2675754	182	RFVChanged	{"blockNumber":2675754,"blockTimestamp":1723281599,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7732000000000000_2675754","newRFV":"7732000000000000","transactionHash":"0xa20045d351bfce7e2879afea5d67d04fe97ba79242acf3d3fcfac78d7f10f5ee","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2216614450217292401_2675953	1723281946	80084	2675953	46	RFVChanged	{"blockNumber":2675953,"blockTimestamp":1723281946,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2216614450217292401_2675953","newRFV":"2216614450217292401","transactionHash":"0x57769c8a8d007c7f458e0f68073f786c7e313294a473f502c3ecd428e8cb4f55","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7772000000000000_2678656	1723286879	80084	2678656	44	RFVChanged	{"blockNumber":2678656,"blockTimestamp":1723286879,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7772000000000000_2678656","newRFV":"7772000000000000","transactionHash":"0x89dd1bd8df165eb41c124d2209104de5154140ee874a2ae5280f04be962625ca","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2261058894661736845_2679355	1723288181	80084	2679355	546	RFVChanged	{"blockNumber":2679355,"blockTimestamp":1723288181,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2261058894661736845_2679355","newRFV":"2261058894661736845","transactionHash":"0x3e5d09615608813dac5f16ee4e970f5171154d0152c77cbfa80fbedabbaa3061","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2283281116883959067_2680029	1723289435	80084	2680029	156	RFVChanged	{"blockNumber":2680029,"blockTimestamp":1723289435,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2283281116883959067_2680029","newRFV":"2283281116883959067","transactionHash":"0x5d3c2b422a1b668e051d64629821cbd65ec42f54025de15d7c3e13eb438f2a79","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2394392227995070179_2680849	1723291010	80084	2680849	24	RFVChanged	{"blockNumber":2680849,"blockTimestamp":1723291010,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2394392227995070179_2680849","newRFV":"2394392227995070179","transactionHash":"0xbb4ca7c200f9ddf1a137b62df7b9f2b0642272ecdd961517516cdbf37dfacffb","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7774000000000000_2685757	1723300052	80084	2685757	43	RFVChanged	{"blockNumber":2685757,"blockTimestamp":1723300052,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7774000000000000_2685757","newRFV":"7774000000000000","transactionHash":"0x17c11efb3f0abed9942c886f300af1d913958d7e48fc43d8983e4e34da738915","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7794000000000000_2685792	1723300104	80084	2685792	138	RFVChanged	{"blockNumber":2685792,"blockTimestamp":1723300104,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7794000000000000_2685792","newRFV":"7794000000000000","transactionHash":"0x42337ee2dfad5129533b2ae8de16b1d8d69a98752c405f6af020a81fa6f1d2d1","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7796000000000000_2688951	1723305921	80084	2688951	2	RFVChanged	{"blockNumber":2688951,"blockTimestamp":1723305921,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7796000000000000_2688951","newRFV":"7796000000000000","transactionHash":"0x25da7d611c68f3c36ad08d92c8615690db8fadb67b0cabd5ee68c02ded04e384","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6866666666666666666_2688967	1723305949	80084	2688967	254	RFVChanged	{"blockNumber":2688967,"blockTimestamp":1723305949,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6866666666666666666_2688967","newRFV":"6866666666666666666","transactionHash":"0x5faf83c7f1d63e26c5846c14172d06ae9c937422df5002726ff25eb992ac0507","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2403099108824143161_2689966	1723307897	80084	2689966	79	RFVChanged	{"blockNumber":2689966,"blockTimestamp":1723307897,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2403099108824143161_2689966","newRFV":"2403099108824143161","transactionHash":"0xa19962719331f1c7b607192f25fa846bf5fec9336275a2f9229c2c034a0a82d3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406331172382711124_2690005	1723307963	80084	2690005	83	RFVChanged	{"blockNumber":2690005,"blockTimestamp":1723307963,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406331172382711124_2690005","newRFV":"2406331172382711124","transactionHash":"0x0417b25353c5505b307a83fbb5b145424ef7668dd511109f3926f6eb51651072","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406358777676443360_2690081	1723308118	80084	2690081	34	RFVChanged	{"blockNumber":2690081,"blockTimestamp":1723308118,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2406358777676443360_2690081","newRFV":"2406358777676443360","transactionHash":"0x0d9111de70971c9726c14e5268cffd9bf1942cf6fbcfd76ae01b3e16ac98856c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2354665633472225941_2691504	1723310719	80084	2691504	71	RFVChanged	{"blockNumber":2691504,"blockTimestamp":1723310719,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2354665633472225941_2691504","newRFV":"2354665633472225941","transactionHash":"0xd483c5a77314338b92f381a44dca6981b8810d2203dba3d63e5e2ecd188976f8","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6900000000000000000_2694359	1723315857	80084	2694359	178	RFVChanged	{"blockNumber":2694359,"blockTimestamp":1723315857,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6900000000000000000_2694359","newRFV":"6900000000000000000","transactionHash":"0x7a5685f7d75da53fdef0e32b6b17247ffc4ba15c20dc80b0a4703b8b2575515a","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6966666666666666666_2697422	1723321436	80084	2697422	34	RFVChanged	{"blockNumber":2697422,"blockTimestamp":1723321436,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6966666666666666666_2697422","newRFV":"6966666666666666666","transactionHash":"0x7a7d1b2eea5de53d6b5839284ce86dd5bdda8b63b07819bb8922fc4b676c8aff","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6973333333333333333_2699443	1723325135	80084	2699443	95	RFVChanged	{"blockNumber":2699443,"blockTimestamp":1723325135,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6973333333333333333_2699443","newRFV":"6973333333333333333","transactionHash":"0x140bc1a00fbe2ffab5ee59e6cfbc9da109f3b416f6dc9990b010f0b1a8926fb4","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6976666666666666666_2699529	1723325308	80084	2699529	31	RFVChanged	{"blockNumber":2699529,"blockTimestamp":1723325308,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_6976666666666666666_2699529","newRFV":"6976666666666666666","transactionHash":"0xf51ca86a40e3c29116329f5a70c18efd0a7d398acc019ec5ade7764ab318df3f","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7043333333333333333_2699766	1723325742	80084	2699766	32	RFVChanged	{"blockNumber":2699766,"blockTimestamp":1723325742,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7043333333333333333_2699766","newRFV":"7043333333333333333","transactionHash":"0x5821ac5be14e58e38fa844b2b264da3281f0ce3de399ac1a6fdb23fb67927fdb","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7836000000000000_2711188	1723346982	80084	2711188	40	RFVChanged	{"blockNumber":2711188,"blockTimestamp":1723346982,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7836000000000000_2711188","newRFV":"7836000000000000","transactionHash":"0x2b993c0da2f8cb3e51e26d1837bdb852274fe1e3824de76c1f83fadf0dca7ac9","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399110077916670385_2715302	1723354657	80084	2715302	51	RFVChanged	{"blockNumber":2715302,"blockTimestamp":1723354657,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399110077916670385_2715302","newRFV":"2399110077916670385","transactionHash":"0x8b29f500c3801cfcce7f8e98ba7a3608c4b16f81ec73623f7034f69ceceb628c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7856000000000000_2722976	1723368848	80084	2722976	7	RFVChanged	{"blockNumber":2722976,"blockTimestamp":1723368848,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7856000000000000_2722976","newRFV":"7856000000000000","transactionHash":"0xe9544da3341c00b51d3dd0d3c41259e4a4a629562d4666dd04bcc39088e112c1","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7926000000000000_2733932	1723389216	80084	2733932	131	RFVChanged	{"blockNumber":2733932,"blockTimestamp":1723389216,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7926000000000000_2733932","newRFV":"7926000000000000","transactionHash":"0x08388dc71099654e0de11bdf81f8b82c0b1f976e5d49f296269aa49e94281f6c","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399332300138892608_2735221	1723391558	80084	2735221	86	RFVChanged	{"blockNumber":2735221,"blockTimestamp":1723391558,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2399332300138892608_2735221","newRFV":"2399332300138892608","transactionHash":"0x74dd9bede9ec57722b38fd43c623a3b9f4d5b51d8476479cd5bfb08521ec2b14","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421554522361114830_2766691	1723448340	80084	2766691	45	RFVChanged	{"blockNumber":2766691,"blockTimestamp":1723448340,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421554522361114830_2766691","newRFV":"2421554522361114830","transactionHash":"0x525d6195ffcf88de1bc05b0f7a4f81e6afa0e810f9d506a0296e817ab98ce20a","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7110000000000000000_2770445	1723455226	80084	2770445	119	RFVChanged	{"blockNumber":2770445,"blockTimestamp":1723455226,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7110000000000000000_2770445","newRFV":"7110000000000000000","transactionHash":"0x9623fe7cfda66bce9febdb1475354b88c7814cb008e0904b529fabce73367595","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421776744583337052_2773564	1723460935	80084	2773564	118	RFVChanged	{"blockNumber":2773564,"blockTimestamp":1723460935,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_2421776744583337052_2773564","newRFV":"2421776744583337052","transactionHash":"0x7878ea57afbf66540ad3212dcdfefc8b1a13d9889971ba09a4a1621527cbbba8","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7946000000000000_2788002	1723487050	80084	2788002	280	RFVChanged	{"blockNumber":2788002,"blockTimestamp":1723487050,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_7946000000000000_2788002","newRFV":"7946000000000000","transactionHash":"0xa8fbceb143e001d5baae7a9b7603b77094865d788b308ecdc5a0e990b4ab91b7","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8066000000000000_2791109	1723492593	80084	2791109	19	RFVChanged	{"blockNumber":2791109,"blockTimestamp":1723492593,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8066000000000000_2791109","newRFV":"8066000000000000","transactionHash":"0xdbc100e5c3ba09b75e682e99807d45b1c0790612fb56efdc27d1caf88bfb334e","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8406000000000000_2816357	1723538484	80084	2816357	354	RFVChanged	{"blockNumber":2816357,"blockTimestamp":1723538484,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8406000000000000_2816357","newRFV":"8406000000000000","transactionHash":"0xb2eb2a837a244469f46827ac45fa06444f56a68757a21b6c9fc07aa43b4b9351","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3088443411250003719_2823220	1723551452	80084	2823220	140	RFVChanged	{"blockNumber":2823220,"blockTimestamp":1723551452,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3088443411250003719_2823220","newRFV":"3088443411250003719","transactionHash":"0x8d9e603993d5ec3be11522386a62c1df390907325e980db7295965927e5a98d5","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3099674114563640096_2826369	1723557134	80084	2826369	27	RFVChanged	{"blockNumber":2826369,"blockTimestamp":1723557134,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3099674114563640096_2826369","newRFV":"3099674114563640096","transactionHash":"0xf8de06584bb77120bde88831f289595e99f5ca81b218ca4671447b3227dd95e8","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3103843041143626063_2826443	1723557272	80084	2826443	17	RFVChanged	{"blockNumber":2826443,"blockTimestamp":1723557272,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3103843041143626063_2826443","newRFV":"3103843041143626063","transactionHash":"0x26765dd2b31c9dc9af28ededaef22bf0ca2ac6ba7c5583514d4c10ba387e22fe","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3104635148929536719_2826606	1723557571	80084	2826606	50	RFVChanged	{"blockNumber":2826606,"blockTimestamp":1723557571,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3104635148929536719_2826606","newRFV":"3104635148929536719","transactionHash":"0xdddd567d726496c0a8265b666f41c5dc5dbd42eef3b1996eef6af55f0b1e4f10","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7116666666666666666_2829422	1723562728	80084	2829422	2	RFVChanged	{"blockNumber":2829422,"blockTimestamp":1723562728,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7116666666666666666_2829422","newRFV":"7116666666666666666","transactionHash":"0x42fbbe175838d5dd70b1bf87f3c7c22cfa41650536dbb185837106df453abae3","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606000000000000_2838014	1723577620	80084	2838014	52	RFVChanged	{"blockNumber":2838014,"blockTimestamp":1723577620,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606000000000000_2838014","newRFV":"8606000000000000","transactionHash":"0x6c5216c452bf2a9b8bbdfcb3a639bd8fdd39158b497f1c7d67117afafc5d321a","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606017556591131_2846068	1723591406	80084	2846068	39	RFVChanged	{"blockNumber":2846068,"blockTimestamp":1723591406,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606017556591131_2846068","newRFV":"8606017556591131","transactionHash":"0xd6ed67230d0c0763e20983bd7f3f188881ae6b6058a87f2a49929fe413cd43f0","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606035112866947_2846146	1723591538	80084	2846146	53	RFVChanged	{"blockNumber":2846146,"blockTimestamp":1723591538,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8606035112866947_2846146","newRFV":"8606035112866947","transactionHash":"0xb5ee9c85cac521c32381e9d5827801d90cb3f3e181512101df962a32449207d0","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3263726058020445810_2852388	1723602298	80084	2852388	217	RFVChanged	{"blockNumber":2852388,"blockTimestamp":1723602298,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3263726058020445810_2852388","newRFV":"3263726058020445810","transactionHash":"0xce930acdc25cbde393d943c6573513de081acd587e929244204ca79dab0f3981","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3275870154980521888_2890454	1723668886	80084	2890454	12	RFVChanged	{"blockNumber":2890454,"blockTimestamp":1723668886,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3275870154980521888_2890454","newRFV":"3275870154980521888","transactionHash":"0x2b69fd40e7b9406f443fb3c89197781f4815c876beb439bfe993ee055f043e91","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3277372943455568703_2890580	1723669093	80084	2890580	35	RFVChanged	{"blockNumber":2890580,"blockTimestamp":1723669093,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3277372943455568703_2890580","newRFV":"3277372943455568703","transactionHash":"0x3874200bf0e2773ffbbee847a6e6945e6627843b0357255a58c12efb504fba77","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7783333333333333333_2912110	1723706895	80084	2912110	37	RFVChanged	{"blockNumber":2912110,"blockTimestamp":1723706895,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7783333333333333333_2912110","newRFV":"7783333333333333333","transactionHash":"0xf34b5b860a7b073ce3d2491434efb0fad1e0cd2195806eaac1d862bef4330126","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8608035112866947_2913325	1723709106	80084	2913325	33	RFVChanged	{"blockNumber":2913325,"blockTimestamp":1723709106,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8608035112866947_2913325","newRFV":"8608035112866947","transactionHash":"0x856df3f0b1c06b958718de6c5f3c4807de22c309b11231e0811bc23441a313dc","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8626035112866947_2917496	1723716587	80084	2917496	53	RFVChanged	{"blockNumber":2917496,"blockTimestamp":1723716587,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8626035112866947_2917496","newRFV":"8626035112866947","transactionHash":"0x0c416d135f111bdf08a3a2712133ae4987e7e81a2a5803f23b710e0e01b91374","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8926035112866947_2975602	1723818524	80084	2975602	53	RFVChanged	{"blockNumber":2975602,"blockTimestamp":1723818524,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_8926035112866947_2975602","newRFV":"8926035112866947","transactionHash":"0x825f93c80b3cacda0bcb081c93bfaedd301a2acb2a8896d48c5111b276e1079d","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9026035112866947_2977642	1723822106	80084	2977642	45	RFVChanged	{"blockNumber":2977642,"blockTimestamp":1723822106,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9026035112866947_2977642","newRFV":"9026035112866947","transactionHash":"0xecbf58aa599a1fa48b136d4cc72cd3d4b781155328ae9614047461ff92455307","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3393652013223010563_2983801	1723832984	80084	2983801	63	RFVChanged	{"blockNumber":2983801,"blockTimestamp":1723832984,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3393652013223010563_2983801","newRFV":"3393652013223010563","transactionHash":"0x650024a2d4a05f8370bd48d29c113edf3425cdc3a0dc9846f4faeef45537c59f","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035112866947_3018720	1723894660	80084	3018720	44	RFVChanged	{"blockNumber":3018720,"blockTimestamp":1723894660,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035112866947_3018720","newRFV":"9246035112866947","transactionHash":"0xf06ba6986b13b5fd31f0566d546c7c237c90bb96f391d59eadbb43ccfc639e8e","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035554851972_3021402	1723899581	80084	3021402	31	RFVChanged	{"blockNumber":3021402,"blockTimestamp":1723899581,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9246035554851972_3021402","newRFV":"9246035554851972","transactionHash":"0x787bc3d631cd91ae7747b712816962d23aac02c5bdec1bb173fabe7a74be18bc","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3416907827176498935_3022962	1723902452	80084	3022962	25	RFVChanged	{"blockNumber":3022962,"blockTimestamp":1723902452,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3416907827176498935_3022962","newRFV":"3416907827176498935","transactionHash":"0xe6d74f6fdddd2e2c8c312b3f028038b8bd0aeea17b88123e93e12b7371680101","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9256035554851972_3023282	1723903042	80084	3023282	19	RFVChanged	{"blockNumber":3023282,"blockTimestamp":1723903042,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9256035554851972_3023282","newRFV":"9256035554851972","transactionHash":"0x84285cfae9f3640911ae4bae30fade3fd2af4ae34d47e3f8d80f26f14b7893ad","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9316035554851972_3025262	1723906628	80084	3025262	109	RFVChanged	{"blockNumber":3025262,"blockTimestamp":1723906628,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9316035554851972_3025262","newRFV":"9316035554851972","transactionHash":"0x3cc4c40ee8bdac785ab897280fb8115aed8268c2b90d64238ac9d189f23d4de4","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9324035554851972_3027582	1723910779	80084	3027582	28	RFVChanged	{"blockNumber":3027582,"blockTimestamp":1723910779,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9324035554851972_3027582","newRFV":"9324035554851972","transactionHash":"0xb2e83373db3f5dfc9eeb12012f92e9acb1e3c6e5e96e50b61f00e0f2497c50c8","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_20000000000000000_3028697	1723912769	80084	3028697	168	RFVChanged	{"blockNumber":3028697,"blockTimestamp":1723912769,"chain":"BERACHAIN_BARTIO","id":"80084_0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4_20000000000000000_3028697","newRFV":"20000000000000000","transactionHash":"0xbe4c4d20016915d07c111e33bca47d0cebf1d2dc63d56a28c8c24e339f765e0b","treasuryAddress":"0x58aD31A6784ff1fB96df72eEb9EBA50772d151F4"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9344035554851972_3029058	1723913436	80084	3029058	50	RFVChanged	{"blockNumber":3029058,"blockTimestamp":1723913436,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9344035554851972_3029058","newRFV":"9344035554851972","transactionHash":"0x90f3b8e45b3f18af19fa46156e7b6c8595a7816fa66670d3a45deaf0bf8a5498","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7916666666666666666_3032396	1723919525	80084	3032396	144	RFVChanged	{"blockNumber":3032396,"blockTimestamp":1723919525,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7916666666666666666_3032396","newRFV":"7916666666666666666","transactionHash":"0x6edee536b1f110c4becbcefd97b155143fd004f1ac6dd49207d4d064e446081a","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7983333333333333333_3036846	1723927639	80084	3036846	47	RFVChanged	{"blockNumber":3036846,"blockTimestamp":1723927639,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_7983333333333333333_3036846","newRFV":"7983333333333333333","transactionHash":"0x889130b636a0f319afdb6ed8a5fb57c897bf2fc8e1533714a79b7e9c9baea572","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9544035554851972_3061939	1723972338	80084	3061939	43	RFVChanged	{"blockNumber":3061939,"blockTimestamp":1723972338,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9544035554851972_3061939","newRFV":"9544035554851972","transactionHash":"0x65fb6311c4e21b3ece5d1aa021053d1096352e2d2154d4d08a11d25ae05a4c09","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3419233408571847772_3076136	1723997465	80084	3076136	101	RFVChanged	{"blockNumber":3076136,"blockTimestamp":1723997465,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3419233408571847772_3076136","newRFV":"3419233408571847772","transactionHash":"0x63a05c56d7acce154fecf3d94d293823639c4f87bc08ea93e7ba75f6d9f223df","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9564035554851972_3101865	1724043088	80084	3101865	65	RFVChanged	{"blockNumber":3101865,"blockTimestamp":1724043088,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9564035554851972_3101865","newRFV":"9564035554851972","transactionHash":"0x0ea6c82cb21236dc452c4507362670746f230cd5fca2b13ea5696fa2f2e66e18","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9644035554851972_3108017	1724054209	80084	3108017	14	RFVChanged	{"blockNumber":3108017,"blockTimestamp":1724054209,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9644035554851972_3108017","newRFV":"9644035554851972","transactionHash":"0xe088fe52b5ba00b7918a4270b2c8ccad538846d519ac43b070ff9521d55c15fd","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3421558989967196610_3108721	1724055462	80084	3108721	245	RFVChanged	{"blockNumber":3108721,"blockTimestamp":1724055462,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3421558989967196610_3108721","newRFV":"3421558989967196610","transactionHash":"0xe3f27d1c16d88fedba77a8eecb187d8c7016315ed35886c24076cfe8246ed5f3","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9646035554851972_3109144	1724056208	80084	3109144	460	RFVChanged	{"blockNumber":3109144,"blockTimestamp":1724056208,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9646035554851972_3109144","newRFV":"9646035554851972","transactionHash":"0x8202b04f6357a1ba9f821478f8ddc3e85bc0d3e590ae2850f3ee76beb54c013a","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9666035554851972_3123354	1724081924	80084	3123354	224	RFVChanged	{"blockNumber":3123354,"blockTimestamp":1724081924,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9666035554851972_3123354","newRFV":"9666035554851972","transactionHash":"0x44cedb89fe5f7801d33e0e08cc7357b133be43cd830eb7b5dc629aa85d1c07f4","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9694035554851972_3128801	1724091656	80084	3128801	50	RFVChanged	{"blockNumber":3128801,"blockTimestamp":1724091656,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9694035554851972_3128801","newRFV":"9694035554851972","transactionHash":"0xade55b3bdd93c0af8773dde9a052c71bde9e759ee64cae2e2429b7bd33143099","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3654117129502080330_3136530	1724105272	80084	3136530	94	RFVChanged	{"blockNumber":3136530,"blockTimestamp":1724105272,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3654117129502080330_3136530","newRFV":"3654117129502080330","transactionHash":"0x81637bbf992d9436072d68ec95d22c152f4761cc03b5affed021345869c70068","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9714035554851972_3189030	1724196780	80084	3189030	88	RFVChanged	{"blockNumber":3189030,"blockTimestamp":1724196780,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_9714035554851972_3189030","newRFV":"9714035554851972","transactionHash":"0xbf59934c76bac25faf7c748bf488635f61c3e4ae1278754163b68d51f2d2d132","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11314035554851972_3222943	1724255521	80084	3222943	88	RFVChanged	{"blockNumber":3222943,"blockTimestamp":1724255521,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11314035554851972_3222943","newRFV":"11314035554851972","transactionHash":"0xf0562256fc07998c043af82f3e527a18bf7befc4578526209e0d5f44c7a67197","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259309	1724317417	80084	3259309	193	RFVChanged	{"blockNumber":3259309,"blockTimestamp":1724317417,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259309","newRFV":"0","transactionHash":"0x24acda3c1b82bcac0ddc1dabfcac6157ed43c21431e8ee60d5a153a386b73dab","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259884	1724318414	80084	3259884	143	RFVChanged	{"blockNumber":3259884,"blockTimestamp":1724318414,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259884","newRFV":"0","transactionHash":"0x118f8a454eb4261b6538e5cac0e4f35ed7c98e358af49328737c8f34a3905e31","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259932	1724318512	80084	3259932	217	RFVChanged	{"blockNumber":3259932,"blockTimestamp":1724318512,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259932","newRFV":"0","transactionHash":"0xd6531451556911f8f8c782a6370ce0b6076f670d4cbb3c4f250737c62da2add5","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259995	1724318615	80084	3259995	264	RFVChanged	{"blockNumber":3259995,"blockTimestamp":1724318615,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3259995","newRFV":"0","transactionHash":"0x7c72eef9a42a2458a1ef50796ccbc65a17a5d76251e9a8291328eb1552280cba","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260027	1724318669	80084	3260027	28	RFVChanged	{"blockNumber":3260027,"blockTimestamp":1724318669,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260027","newRFV":"0","transactionHash":"0x43b878f619d43a598ef9f68abf36e94ab8512b66917ceaa20e80bc40eeda59af","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260088	1724318786	80084	3260088	148	RFVChanged	{"blockNumber":3260088,"blockTimestamp":1724318786,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260088","newRFV":"0","transactionHash":"0x20cb680cd25158d1c1e77de4620fa02a8897745c803720abc5e4ee45ef05ae14","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260137	1724318858	80084	3260137	501	RFVChanged	{"blockNumber":3260137,"blockTimestamp":1724318858,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260137","newRFV":"0","transactionHash":"0x82d679ff3f74dce8ed114ae8615386c43c5eb65b700209c5b3bbbd1fd2e897bc","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260164	1724318913	80084	3260164	700	RFVChanged	{"blockNumber":3260164,"blockTimestamp":1724318913,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260164","newRFV":"0","transactionHash":"0x121f738c500e566d3f570f5ca1d242bc27ab161c59acdf2e8fadea763fd09b23","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260176	1724318939	80084	3260176	586	RFVChanged	{"blockNumber":3260176,"blockTimestamp":1724318939,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260176","newRFV":"0","transactionHash":"0xa0d0b74c27bce7c33420a7f83193898528b5d4ada14afd544e39e8138881a67c","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260188	1724318961	80084	3260188	99	RFVChanged	{"blockNumber":3260188,"blockTimestamp":1724318961,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_0_3260188","newRFV":"0","transactionHash":"0xbc71bd6b3b7f183e2bfa3a2b6bf4d1ab9371a9a288f915f77c10467af2d59bf5","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3322259136212624_3260219	1724319010	80084	3260219	124	RFVChanged	{"blockNumber":3260219,"blockTimestamp":1724319010,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3322259136212624_3260219","newRFV":"3322259136212624","transactionHash":"0xcfbb086fdaea64cae6e81f01ea300a6301cc8fd30855d45f0bba8e85a41e52e6","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3324058693244739_3260241	1724319041	80084	3260241	83	RFVChanged	{"blockNumber":3260241,"blockTimestamp":1724319041,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3324058693244739_3260241","newRFV":"3324058693244739","transactionHash":"0xb473e6fca62be215c3c3e4b3674ccd47a69a1281b571f0215b18d8c6e684af4b","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_65693430656934306_3263083	1724323889	80084	3263083	419	RFVChanged	{"blockNumber":3263083,"blockTimestamp":1724323889,"chain":"BERACHAIN_BARTIO","id":"80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_65693430656934306_3263083","newRFV":"65693430656934306","transactionHash":"0x26cff8c46a615a557d4c94f052d717be22e96b76eab77b555260554e7d69957a","treasuryAddress":"0x9321f6e31883F20B299aD541a1421D7a06DCCcAC"}	\N	\N	\N	\N
80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000000000000000000_3263218	1724324120	80084	3263218	158	RFVChanged	{"blockNumber":3263218,"blockTimestamp":1724324120,"chain":"BERACHAIN_BARTIO","id":"80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000000000000000000_3263218","newRFV":"1000000000000000000","transactionHash":"0xe1b113799a04e110e6494acbdfb82a0afee67a8dcc41a68cfb3bb1a599186b9b","treasuryAddress":"0x9321f6e31883F20B299aD541a1421D7a06DCCcAC"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2200000000000000000_3263251	1724324184	80084	3263251	60	RFVChanged	{"blockNumber":3263251,"blockTimestamp":1724324184,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2200000000000000000_3263251","newRFV":"2200000000000000000","transactionHash":"0x00ce84800b6894e3568be992e4466d170773732ed28cbc079630764f29044012","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1003003003003003003_3263318	1724324285	80084	3263318	366	RFVChanged	{"blockNumber":3263318,"blockTimestamp":1724324285,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1003003003003003003_3263318","newRFV":"1003003003003003003","transactionHash":"0x155e54333ddcdd6c549f2fb7bbc6c5d4c5e348f8c981893cc9e30e7edb80dc30","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1081081081081081081_3263405	1724324437	80084	3263405	132	RFVChanged	{"blockNumber":3263405,"blockTimestamp":1724324437,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1081081081081081081_3263405","newRFV":"1081081081081081081","transactionHash":"0xdfc73144311f7631004798f6c19f7d7fe2cdf41853dc407f03a48eff92c64d81","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3572884500016996916_3266051	1724328937	80084	3266051	34	RFVChanged	{"blockNumber":3266051,"blockTimestamp":1724328937,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3572884500016996916_3266051","newRFV":"3572884500016996916","transactionHash":"0x8bc4d27f8ce4593fc0a813fa1a64729811a7eb87ed8a9e6e7aa4eb3760254c18","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11334035554851972_3277966	1724349234	80084	3277966	120	RFVChanged	{"blockNumber":3277966,"blockTimestamp":1724349234,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11334035554851972_3277966","newRFV":"11334035554851972","transactionHash":"0x6f613f4e8801278ca9b2a8b8db688ae733232bdb93e8e46c3b89f95aa8ac7fb1","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1981981981981981981_3284254	1724359910	80084	3284254	16	RFVChanged	{"blockNumber":3284254,"blockTimestamp":1724359910,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1981981981981981981_3284254","newRFV":"1981981981981981981","transactionHash":"0x6a7c99c0481ad7b714f8e12b59c526fdebf3adc9529a8bfbaec7131f45674675","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1033033033033033033_3284733	1724360727	80084	3284733	23	RFVChanged	{"blockNumber":3284733,"blockTimestamp":1724360727,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1033033033033033033_3284733","newRFV":"1033033033033033033","transactionHash":"0x21e6cce0e0fed129c60fd8b0fff715f27ae883db1464493e5c77f02c4a22b799","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3586178953970548532_3305824	1724396443	80084	3305824	99	RFVChanged	{"blockNumber":3305824,"blockTimestamp":1724396443,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3586178953970548532_3305824","newRFV":"3586178953970548532","transactionHash":"0x9640d6c02b328ff337d2ec6616901f6bbdc6d0bbd04fc3faa279233ad43b1d44","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3596049800151595216_3305849	1724396482	80084	3305849	39	RFVChanged	{"blockNumber":3305849,"blockTimestamp":1724396482,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3596049800151595216_3305849","newRFV":"3596049800151595216","transactionHash":"0x0afeab5b51c8e18e64ea8d9decaa0ee6e9627097ecf41bd4e62dd2f95c6874d2","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11338035554851972_3306185	1724397039	80084	3306185	69	RFVChanged	{"blockNumber":3306185,"blockTimestamp":1724397039,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11338035554851972_3306185","newRFV":"11338035554851972","transactionHash":"0xcf30f8645e71c1335c3c367255a6884000877707286262ff4a9763357b3b6b37","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3325853243203717_3324876	1724428334	80084	3324876	18	RFVChanged	{"blockNumber":3324876,"blockTimestamp":1724428334,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3325853243203717_3324876","newRFV":"3325853243203717","transactionHash":"0x84c994ee9cafe6505614c08f410a76ba85c7105b5ffaf2411643d0135c7b17fe","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2266666666666666666_3326673	1724431374	80084	3326673	352	RFVChanged	{"blockNumber":3326673,"blockTimestamp":1724431374,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_2266666666666666666_3326673","newRFV":"2266666666666666666","transactionHash":"0xa87b743a3d3173529c6384a04e5d08febbd38bbd8d76e9ae60a398d2caf5b6ae","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982069520007650481_3328231	1724433978	80084	3328231	79	RFVChanged	{"blockNumber":3328231,"blockTimestamp":1724433978,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982069520007650481_3328231","newRFV":"1982069520007650481","transactionHash":"0x71fbbf39f5c905b34afa42e138afbbc5833e59fb2ff83686465ca47ac36dd504","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3619305614105083588_3337406	1724449389	80084	3337406	27	RFVChanged	{"blockNumber":3337406,"blockTimestamp":1724449389,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3619305614105083588_3337406","newRFV":"3619305614105083588","transactionHash":"0xae3525004d0cfee8168af6c65b4e4657650c9c2d9dd24079ef8f7df39b8d022f","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11346035554851972_3350924	1724472011	80084	3350924	46	RFVChanged	{"blockNumber":3350924,"blockTimestamp":1724472011,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11346035554851972_3350924","newRFV":"11346035554851972","transactionHash":"0x70a6244a28c96d785eeda9a3ab1e83a27afea49e2a775bf30b02f5ea7d1daf7f","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11366035554851972_3355196	1724479219	80084	3355196	2	RFVChanged	{"blockNumber":3355196,"blockTimestamp":1724479219,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11366035554851972_3355196","newRFV":"11366035554851972","transactionHash":"0x2ba2e0f45f76740baed8e23fd36b9e35d74bc2efbddfac88e11eebfb2d1f14d7","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3327654747043786_3368942	1724502474	80084	3368942	68	RFVChanged	{"blockNumber":3368942,"blockTimestamp":1724502474,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3327654747043786_3368942","newRFV":"3327654747043786","transactionHash":"0x8ed4054874d4a2134f1dd93743e6205ad7af4777ad23769093d7d280342ba739","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1036036036036036036_3373443	1724510132	80084	3373443	28	RFVChanged	{"blockNumber":3373443,"blockTimestamp":1724510132,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1036036036036036036_3373443","newRFV":"1036036036036036036","transactionHash":"0xe34ba761e79ba72d44e4543e437e2066ecac9e5d880539fb31b0c0c98a4966e1","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3621631195500432425_3374521	1724511970	80084	3374521	109	RFVChanged	{"blockNumber":3374521,"blockTimestamp":1724511970,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3621631195500432425_3374521","newRFV":"3621631195500432425","transactionHash":"0xbe18800b238a4db7faddd0a4a4b278cb9fcde83352c8d5af3fcba949b0d6962b","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11368035554851972_3374645	1724512186	80084	3374645	48	RFVChanged	{"blockNumber":3374645,"blockTimestamp":1724512186,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11368035554851972_3374645","newRFV":"11368035554851972","transactionHash":"0x7590ad35c66fa69e620ee034a81a14bc7bc0e3d0c46de54fbde40768b40f211e","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3623956776895781262_3375911	1724514363	80084	3375911	366	RFVChanged	{"blockNumber":3375911,"blockTimestamp":1724514363,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3623956776895781262_3375911","newRFV":"3623956776895781262","transactionHash":"0x838c4e216ad4ecd383ffbfeb0c5ab9ecaf3c91105e06a60ae900ff4eb85012b5","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370035554851972_3376001	1724514523	80084	3376001	42	RFVChanged	{"blockNumber":3376001,"blockTimestamp":1724514523,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370035554851972_3376001","newRFV":"11370035554851972","transactionHash":"0x3d9089da97e98a9d6b4aa6bff5589b1d6585ff961326825201315a70572fa7e8","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370037469949109_3421277	1724590195	80084	3421277	200	RFVChanged	{"blockNumber":3421277,"blockTimestamp":1724590195,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11370037469949109_3421277","newRFV":"11370037469949109","transactionHash":"0x64c566ed3aaef2de55bbe736943c59dfa5d5c5355e2177ea15e903c4df1010d6","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3626282358291130099_3435834	1724614464	80084	3435834	2	RFVChanged	{"blockNumber":3435834,"blockTimestamp":1724614464,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3626282358291130099_3435834","newRFV":"3626282358291130099","transactionHash":"0x7b518f62dd7ec495cf34039d7dd1ad79bf1e8f876f9464e7c601f11d042abf7c","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3329463255058483_3462151	1724658439	80084	3462151	204	RFVChanged	{"blockNumber":3462151,"blockTimestamp":1724658439,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3329463255058483_3462151","newRFV":"3329463255058483","transactionHash":"0xde54617c330a06548334020f9efadd86c50b5a1f32929e132faa7d66828d8ab3","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3331266714321640_3469700	1724671106	80084	3469700	60	RFVChanged	{"blockNumber":3469700,"blockTimestamp":1724671106,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3331266714321640_3469700","newRFV":"3331266714321640","transactionHash":"0x05fe1f8ef22bb0a33b26923a03a1b5776d0d24bbf480c78a939193fc3100758e","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333077185362032_3469733	1724671165	80084	3469733	74	RFVChanged	{"blockNumber":3469733,"blockTimestamp":1724671165,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333077185362032_3469733","newRFV":"3333077185362032","transactionHash":"0xbdd2fb1d9c398c88b843c957c16fcf549cd28d76ac4c0c0e5b386964ddbb5bf5","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333363505961407_3469753	1724671197	80084	3469753	103	RFVChanged	{"blockNumber":3469753,"blockTimestamp":1724671197,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3333363505961407_3469753","newRFV":"3333363505961407","transactionHash":"0x85c33f5fe6c637f732777812bdb2bcca7b89f3c2b52563a01998de440281b375","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335181195792678_3475860	1724681398	80084	3475860	206	RFVChanged	{"blockNumber":3475860,"blockTimestamp":1724681398,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335181195792678_3475860","newRFV":"3335181195792678","transactionHash":"0xe19a49285266429e3f105275d73691be293d0ef0e5354cb41886a78bdc17febb","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335468658546292_3475895	1724681460	80084	3475895	29	RFVChanged	{"blockNumber":3475895,"blockTimestamp":1724681460,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_3335468658546292_3475895","newRFV":"3335468658546292","transactionHash":"0xa03b53a53a1b80748aab03c2d4cf4965a39e6e26ccf5db9ec3af4bd1771dc56f","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3742561428058571960_3479992	1724688341	80084	3479992	280	RFVChanged	{"blockNumber":3479992,"blockTimestamp":1724688341,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3742561428058571960_3479992","newRFV":"3742561428058571960","transactionHash":"0x6d397db76c0cb5d9d68d7c8c767c6842ca4146089ffc2221a629b874a23db174","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982149766741940603_3482575	1724693227	80084	3482575	106	RFVChanged	{"blockNumber":3482575,"blockTimestamp":1724693227,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1982149766741940603_3482575","newRFV":"1982149766741940603","transactionHash":"0x407e3d342b1adfd654de6b28774ee2ffc9065fe62bd696f93682e4981483e7d1","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1039039039039039039_3482606	1724693283	80084	3482606	8	RFVChanged	{"blockNumber":3482606,"blockTimestamp":1724693283,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1039039039039039039_3482606","newRFV":"1039039039039039039","transactionHash":"0x835d956266dc02c75e28978011814e0afaba15b3f2e88d5a608a1a6e7dbfbf5e","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_3266666666666666666_3492403	1724711835	80084	3492403	125	RFVChanged	{"blockNumber":3492403,"blockTimestamp":1724711835,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_3266666666666666666_3492403","newRFV":"3266666666666666666","transactionHash":"0x0b74895b6ce5ad4775fd8241f9f7ab3b810111829ebb6ea62ff09fa5f6c479fa","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11770037469949109_3518204	1724760873	80084	3518204	218	RFVChanged	{"blockNumber":3518204,"blockTimestamp":1724760873,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_11770037469949109_3518204","newRFV":"11770037469949109","transactionHash":"0xdff681f2ba751c2213d1d6062114a05a72088772cc1b7491875f2fc346248fa5","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9316666666666666666_3518447	1724761344	80084	3518447	64	RFVChanged	{"blockNumber":3518447,"blockTimestamp":1724761344,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9316666666666666666_3518447","newRFV":"9316666666666666666","transactionHash":"0x8625ce80e8235f4cb114523578f0e703447b8ad08ffcef6eb3eac4def121a7c6","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_4600000000000000000_3518753	1724761920	80084	3518753	99	RFVChanged	{"blockNumber":3518753,"blockTimestamp":1724761920,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_4600000000000000000_3518753","newRFV":"4600000000000000000","transactionHash":"0xe3f4f577f5ef55b537717fb2d78c462ba7c14360a2804d4711b40bf532669b29","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1983607229805721441_3525742	1724776129	80084	3525742	122	RFVChanged	{"blockNumber":3525742,"blockTimestamp":1724776129,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1983607229805721441_3525742","newRFV":"1983607229805721441","transactionHash":"0x8bca291e37b4cd1083c8e3173609ee5cb37e0dc33547a3e74c6127609126419e","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46959629732371795_3526029	1724776647	80084	3526029	36	RFVChanged	{"blockNumber":3526029,"blockTimestamp":1724776647,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46959629732371795_3526029","newRFV":"46959629732371795","transactionHash":"0x502879e9b3c0e124cd9bb04f7d4a50166bf3a8cf6928d11bdc2d8a78d1101ee9","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000016401399243637_3534342	1724791795	80084	3534342	68	RFVChanged	{"blockNumber":3534342,"blockTimestamp":1724791795,"chain":"BERACHAIN_BARTIO","id":"80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000016401399243637_3534342","newRFV":"1000016401399243637","transactionHash":"0x43adc4bc161c66b0d30916397506d056ccd157d6a0e82abe66ed216e4c69faab","treasuryAddress":"0x9321f6e31883F20B299aD541a1421D7a06DCCcAC"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5266666666666666666_3540324	1724802893	80084	3540324	56	RFVChanged	{"blockNumber":3540324,"blockTimestamp":1724802893,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5266666666666666666_3540324","newRFV":"5266666666666666666","transactionHash":"0x0c7e320c03d63f6139a1c205b961a3a65db4800f8b04b47b96c9f3060f3c895e","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770037469949109_3543881	1724809601	80084	3543881	99	RFVChanged	{"blockNumber":3543881,"blockTimestamp":1724809601,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770037469949109_3543881","newRFV":"14770037469949109","transactionHash":"0xd4bf0a4ee8a916f97a924b92baa61d2c52cb2beffc0448897ebc255ddff3e7bc","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1985072394236827940_3550575	1724822260	80084	3550575	229	RFVChanged	{"blockNumber":3550575,"blockTimestamp":1724822260,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1985072394236827940_3550575","newRFV":"1985072394236827940","transactionHash":"0xd3ca62483eab099b346cf84c8354fa7dc1177600da40a3006a92c3b3ad029577","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1986532006291413843_3550620	1724822336	80084	3550620	225	RFVChanged	{"blockNumber":3550620,"blockTimestamp":1724822336,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1986532006291413843_3550620","newRFV":"1986532006291413843","transactionHash":"0x919da6c509e69b681e312892cb2edf9b2908e5e5935341133591920c712f9808","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1987999331068788183_3550899	1724822894	80084	3550899	384	RFVChanged	{"blockNumber":3550899,"blockTimestamp":1724822894,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1987999331068788183_3550899","newRFV":"1987999331068788183","transactionHash":"0x6109ff18dd35840321ed197e5c547ffe1fd94cb0c6d2525d84e7cc6ac219dfc9","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989461095282809351_3550960	1724823008	80084	3550960	95	RFVChanged	{"blockNumber":3550960,"blockTimestamp":1724823008,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989461095282809351_3550960","newRFV":"1989461095282809351","transactionHash":"0x52426c92380aa7a12bc149e9a54242b4f1a542bce2ad70c074783454a532295a","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3831644300352515005_3551056	1724823188	80084	3551056	71	RFVChanged	{"blockNumber":3551056,"blockTimestamp":1724823188,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3831644300352515005_3551056","newRFV":"3831644300352515005","transactionHash":"0x4e3ac36ee92ce02f992bf24138798221b30ab62df3ce0f72455625ebb756cdae","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989501550509609062_3551064	1724823211	80084	3551064	143	RFVChanged	{"blockNumber":3551064,"blockTimestamp":1724823211,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1989501550509609062_3551064","newRFV":"1989501550509609062","transactionHash":"0xccc1cf512c4208cab438457d4f62bfde39ddd0bddc7cd0008eb7ab7a9a580c51","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1990971068700326387_3551088	1724823247	80084	3551088	181	RFVChanged	{"blockNumber":3551088,"blockTimestamp":1724823247,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1990971068700326387_3551088","newRFV":"1990971068700326387","transactionHash":"0xdfce421639bec0e00118ee908f0f618469d910ecf6fedc50eface0127acf03e1","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991203513952743144_3551611	1724824236	80084	3551611	147	RFVChanged	{"blockNumber":3551611,"blockTimestamp":1724824236,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991203513952743144_3551611","newRFV":"1991203513952743144","transactionHash":"0x31ce12c0069114fdfe56e844bc398d55ef7d89e96ef815d65aba68b223fad9e9","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_10000000000000_3577844	1724873033	80084	3577844	67	RFVChanged	{"blockNumber":3577844,"blockTimestamp":1724873033,"chain":"BERACHAIN_BARTIO","id":"80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_10000000000000_3577844","newRFV":"10000000000000","transactionHash":"0xa082e5b4cc7fce8063c5b86f853a8b0e0eb68700a2749345eb21202eac56b00a","treasuryAddress":"0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059129129129129129_3584321	1724885049	80084	3584321	69	RFVChanged	{"blockNumber":3584321,"blockTimestamp":1724885049,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059129129129129129_3584321","newRFV":"1059129129129129129","transactionHash":"0x196fc25a3e608e994913a1180bcb2d4b9817327b87df6d79038fc09a8d0a34b8","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_800000000000000000_3592853	1724900853	80084	3592853	147	RFVChanged	{"blockNumber":3592853,"blockTimestamp":1724900853,"chain":"BERACHAIN_BARTIO","id":"80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_800000000000000000_3592853","newRFV":"800000000000000000","transactionHash":"0xa0b6c3735669c7e7f03a6d7e5b89274b46a97faa730d2dcba8f77467584dfa86","treasuryAddress":"0x8628E8B3142511B1B9D389d4ccb9F9613818e310"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770040497126853_3603936	1724922002	80084	3603936	241	RFVChanged	{"blockNumber":3603936,"blockTimestamp":1724922002,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14770040497126853_3603936","newRFV":"14770040497126853","transactionHash":"0xb4ed9f60b93297f4b900136ba2a56a72eab4c6d409d77ae32445a024558571a6","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46985323132477891_3605445	1724924944	80084	3605445	59	RFVChanged	{"blockNumber":3605445,"blockTimestamp":1724924944,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_46985323132477891_3605445","newRFV":"46985323132477891","transactionHash":"0xb117461e3dbebc2b03203c1ef234c5ad05cb87d7d621faf0a26eb5b238e21bb2","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47010944323783352_3605567	1724925180	80084	3605567	62	RFVChanged	{"blockNumber":3605567,"blockTimestamp":1724925180,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47010944323783352_3605567","newRFV":"47010944323783352","transactionHash":"0x707f49ea452cc4c6d99081443663f69967d0772469c72bea389a19085c9bfd46","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47036665800054783_3605631	1724925311	80084	3605631	129	RFVChanged	{"blockNumber":3605631,"blockTimestamp":1724925311,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47036665800054783_3605631","newRFV":"47036665800054783","transactionHash":"0x38134dd3da527ceff29c5f5d902ecd0f4126a4dab1b233878e1924069b8bcb92","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47062314988620249_3607670	1724929181	80084	3607670	23	RFVChanged	{"blockNumber":3607670,"blockTimestamp":1724929181,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47062314988620249_3607670","newRFV":"47062314988620249","transactionHash":"0xff305f392378dd59fb68876df4c2436bedbedfefc531ff5f0f17bfce74140792","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059157173718834037_3609001	1724931700	80084	3609001	493	RFVChanged	{"blockNumber":3609001,"blockTimestamp":1724931700,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059157173718834037_3609001","newRFV":"1059157173718834037","transactionHash":"0xbaf9d1486b8bbefb4d063bd5b2a3b402dd917d8ab2339a79f5e348c78074c398","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47088064571736918_3610445	1724934478	80084	3610445	62	RFVChanged	{"blockNumber":3610445,"blockTimestamp":1724934478,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47088064571736918_3610445","newRFV":"47088064571736918","transactionHash":"0x5711be62b26459794c8d3a4f9b3293f2561e7b20c96963ed2efc1a80334f553a","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47113741788156070_3610621	1724934808	80084	3610621	38	RFVChanged	{"blockNumber":3610621,"blockTimestamp":1724934808,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47113741788156070_3610621","newRFV":"47113741788156070","transactionHash":"0xa03cad861b2239565af157d953a44466c5ae2007e8af374574f7b33aca352aca","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47139519508831408_3610810	1724935178	80084	3610810	71	RFVChanged	{"blockNumber":3610810,"blockTimestamp":1724935178,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47139519508831408_3610810","newRFV":"47139519508831408","transactionHash":"0x378a090e7e832499f224e5357a4f4ab834e3771953810539255028188c2195ae","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47165224783731358_3610870	1724935282	80084	3610870	165	RFVChanged	{"blockNumber":3610870,"blockTimestamp":1724935282,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47165224783731358_3610870","newRFV":"47165224783731358","transactionHash":"0xb421e74cde6e0fe6b551c4576294a016305068541211b7f0582adfa844ec37f3","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47191030672712356_3611156	1724935834	80084	3611156	427	RFVChanged	{"blockNumber":3611156,"blockTimestamp":1724935834,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47191030672712356_3611156","newRFV":"47191030672712356","transactionHash":"0xca22ed9483bca01ed58987494a9d6034e5f0a03df39e3badac185af5d3b5de93","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47216764036753684_3611228	1724935954	80084	3611228	78	RFVChanged	{"blockNumber":3611228,"blockTimestamp":1724935954,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47216764036753684_3611228","newRFV":"47216764036753684","transactionHash":"0x81b0996c78bdd74a8d01c9f2fcc90088451b077b59e0c860e272554d37d53da2","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47242598124820931_3611934	1724937300	80084	3611934	163	RFVChanged	{"blockNumber":3611934,"blockTimestamp":1724937300,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47242598124820931_3611934","newRFV":"47242598124820931","transactionHash":"0x10ebfa3fd20b0326a74eb3a0d072a3985b3e32ec849d8d85b207ef0e34bc8043","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47268359608697721_3611982	1724937376	80084	3611982	181	RFVChanged	{"blockNumber":3611982,"blockTimestamp":1724937376,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47268359608697721_3611982","newRFV":"47268359608697721","transactionHash":"0xa5132e53ce5fd6cb77eea7c4050069738e0a2afcbcc7ad6e8af76d8f54d82134","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47294221926665443_3613724	1724940678	80084	3613724	460	RFVChanged	{"blockNumber":3613724,"blockTimestamp":1724940678,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47294221926665443_3613724","newRFV":"47294221926665443","transactionHash":"0x7112f0f161f2231dce4ce39c60ce4a2c6371c0aaf910b1f9a902b848ebbd1531","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47320011561105319_3613770	1724940766	80084	3613770	45	RFVChanged	{"blockNumber":3613770,"blockTimestamp":1724940766,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47320011561105319_3613770","newRFV":"47320011561105319","transactionHash":"0x6d7c4ce22590b3f17668acf6b50c471a38a3064f44f145e54d7931f6f4ec9dde","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47345902139821412_3616823	1724946566	80084	3616823	80	RFVChanged	{"blockNumber":3616823,"blockTimestamp":1724946566,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47345902139821412_3616823","newRFV":"47345902139821412","transactionHash":"0xc07787db3a3601d55d764a8b521d1a54967144759a2e74bf128288d07132342d","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47371719955585577_3616856	1724946622	80084	3616856	197	RFVChanged	{"blockNumber":3616856,"blockTimestamp":1724946622,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47371719955585577_3616856","newRFV":"47371719955585577","transactionHash":"0x8e5bd5d25c2a5ab9d171c81933931213cdeb15004447d1546814478afd844e58","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991302889506882725_3625888	1724963558	80084	3625888	125	RFVChanged	{"blockNumber":3625888,"blockTimestamp":1724963558,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1991302889506882725_3625888","newRFV":"1991302889506882725","transactionHash":"0x0ff82a73803686eb5bc766e34cbd4accf2fdab14ef5c1fb934f978350b39d35b","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1992780454436311348_3625951	1724963672	80084	3625951	49	RFVChanged	{"blockNumber":3625951,"blockTimestamp":1724963672,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1992780454436311348_3625951","newRFV":"1992780454436311348","transactionHash":"0xcf9e303b7fb61bd72c68932c14a595e611d43d9d5b248edb22f8585d8af93f96","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993014173292386164_3625978	1724963715	80084	3625978	29	RFVChanged	{"blockNumber":3625978,"blockTimestamp":1724963715,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993014173292386164_3625978","newRFV":"1993014173292386164","transactionHash":"0xd32f5ce96d86d53ac4655fa3d31f0a183522d2df81ed43b31db62f8940b68a1e","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47397638825931646_3634646	1724979436	80084	3634646	73	RFVChanged	{"blockNumber":3634646,"blockTimestamp":1724979436,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47397638825931646_3634646","newRFV":"47397638825931646","transactionHash":"0x3b47d46edbf24c91891c240f3bc36c73ab5229f4f7de411d8ffa53753c32060e","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47423484853814914_3634776	1724979677	80084	3634776	23	RFVChanged	{"blockNumber":3634776,"blockTimestamp":1724979677,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47423484853814914_3634776","newRFV":"47423484853814914","transactionHash":"0x1f2cd894bd5509bdf91f976dfb4d83e725149e6ffbbfbab0a2982d3853ca28fc","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47449432046706311_3634914	1724979912	80084	3634914	188	RFVChanged	{"blockNumber":3634914,"blockTimestamp":1724979912,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47449432046706311_3634914","newRFV":"47449432046706311","transactionHash":"0xe2ed6fc73f70ceecfd7e76838c73ced0afd714b6bd2ee376bdfbca8a74afc0e4","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47475306317537149_3634927	1724979936	80084	3634927	207	RFVChanged	{"blockNumber":3634927,"blockTimestamp":1724979936,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47475306317537149_3634927","newRFV":"47475306317537149","transactionHash":"0x69457c91f3b13be315198917c94aee1350f64f40e6069963e9d85b3a48ab8536","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059185056201084004_3636795	1724983322	80084	3636795	160	RFVChanged	{"blockNumber":3636795,"blockTimestamp":1724983322,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059185056201084004_3636795","newRFV":"1059185056201084004","transactionHash":"0xe92e3256d3bbae696ecf70fc1ba1995d23f07b69e3f583c98995892750068251","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47501281863923007_3651552	1725011247	80084	3651552	170	RFVChanged	{"blockNumber":3651552,"blockTimestamp":1725011247,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47501281863923007_3651552","newRFV":"47501281863923007","transactionHash":"0x28fd08c7a640d064fd2324082908276c2f545ab7efcc50e9b8437e87b32d6036","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47527184408563569_3651570	1725011284	80084	3651570	215	RFVChanged	{"blockNumber":3651570,"blockTimestamp":1725011284,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47527184408563569_3651570","newRFV":"47527184408563569","transactionHash":"0xa37b376846cfb362e6c74aff2b38f0f65d41a6f4d1b3cb5403b080e830436646","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5273333333333333333_3687303	1725082541	80084	3687303	2	RFVChanged	{"blockNumber":3687303,"blockTimestamp":1725082541,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_5273333333333333333_3687303","newRFV":"5273333333333333333","transactionHash":"0x822f7c7fef99ccd0da134e328b07d92ed54e7235502ee5ed65b5462b27d89e6b","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3835215728923943577_3712424	1725134428	80084	3712424	38	RFVChanged	{"blockNumber":3712424,"blockTimestamp":1725134428,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3835215728923943577_3712424","newRFV":"3835215728923943577","transactionHash":"0xb66a46b53e65ad1466fda1dc3e393b60cdcab7c6d5cf95ec4ea88ff6775fcce2","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771140497126853_3712459	1725134488	80084	3712459	86	RFVChanged	{"blockNumber":3712459,"blockTimestamp":1725134488,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771140497126853_3712459","newRFV":"14771140497126853","transactionHash":"0x9acca2c408ef1d6200ca9eaf37a7bac08f40d6018e3017b540a735bbb246faee","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993095519297009027_3738889	1725190207	80084	3738889	334	RFVChanged	{"blockNumber":3738889,"blockTimestamp":1725190207,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1993095519297009027_3738889","newRFV":"1993095519297009027","transactionHash":"0xeb26858c42960c30c0d9f4b7e04bcaf6959ddb7e0aadf873485ac47f47143e21","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3849486299078079181_3740772	1725194025	80084	3740772	167	RFVChanged	{"blockNumber":3740772,"blockTimestamp":1725194025,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_3849486299078079181_3740772","newRFV":"3849486299078079181","transactionHash":"0x4f4e5f8284c72651b0af8aa96f5476d40d17419aadabbccf569045f9957bf236","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1994567692123762499_3742488	1725197618	80084	3742488	184	RFVChanged	{"blockNumber":3742488,"blockTimestamp":1725197618,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1994567692123762499_3742488","newRFV":"1994567692123762499","transactionHash":"0x97153358f154567332f05459f44de3093dc68cde30325561cf273029d0195e5c","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_40909090909090909_3761741	1725238135	80084	3761741	248	RFVChanged	{"blockNumber":3761741,"blockTimestamp":1725238135,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_40909090909090909_3761741","newRFV":"40909090909090909","transactionHash":"0x1ebc3725abf177c425908bcba8d5f4207207e35c07990b91dc7ed507b2f133bc","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41363636363636363_3763781	1725242458	80084	3763781	208	RFVChanged	{"blockNumber":3763781,"blockTimestamp":1725242458,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41363636363636363_3763781","newRFV":"41363636363636363","transactionHash":"0xf6ff92a0a75ca6661487580fe80544b3de4bca1565584a3109e89b29de27ebfb","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41841818181818181_3765612	1725246363	80084	3765612	63	RFVChanged	{"blockNumber":3765612,"blockTimestamp":1725246363,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_41841818181818181_3765612","newRFV":"41841818181818181","transactionHash":"0x4e938333cc3411a290533a9d3a1e6cec30fc66fce1ff0f77578a50abaef1627a","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_50932727272727272_3765785	1725246722	80084	3765785	523	RFVChanged	{"blockNumber":3765785,"blockTimestamp":1725246722,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_50932727272727272_3765785","newRFV":"50932727272727272","transactionHash":"0xd0408d01b1f2dc0b61157c6ff6fedc09f09e1138ee9d8c4e946f87dba1a15172","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_51340189090909091_3766293	1725247864	80084	3766293	490	RFVChanged	{"blockNumber":3766293,"blockTimestamp":1725247864,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_51340189090909091_3766293","newRFV":"51340189090909091","transactionHash":"0x21b231f0b4559ccab7964d9c312f1776fa715033365b56689468c6c6f3554501","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_92127444628099173_3766452	1725248193	80084	3766452	121	RFVChanged	{"blockNumber":3766452,"blockTimestamp":1725248193,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_92127444628099173_3766452","newRFV":"92127444628099173","transactionHash":"0xf94c0b6a0e504b65e820a012e97f0d536485282a7b7d213291dc3569eeecc58f","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93036535537190082_3766728	1725248773	80084	3766728	190	RFVChanged	{"blockNumber":3766728,"blockTimestamp":1725248773,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93036535537190082_3766728","newRFV":"93036535537190082","transactionHash":"0x4f73aa738ac73a988696dfc8702cce83f2b8d52718824b129e5c90f1237d7dbc","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93616824242424242_3766911	1725249151	80084	3766911	193	RFVChanged	{"blockNumber":3766911,"blockTimestamp":1725249151,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_93616824242424242_3766911","newRFV":"93616824242424242","transactionHash":"0x49a36d9645b3342bb704e32512be2852da26dc37139c38c454cb075292be9467","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_94877068531468531_3767108	1725249560	80084	3767108	149	RFVChanged	{"blockNumber":3767108,"blockTimestamp":1725249560,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_94877068531468531_3767108","newRFV":"94877068531468531","transactionHash":"0x7732eabfb234c2d6f2fdffe6d00d754fe9c7e5d33b3b6f18724a6bfe0e70c90c","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96671563636363636_3767487	1725250341	80084	3767487	76	RFVChanged	{"blockNumber":3767487,"blockTimestamp":1725250341,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96671563636363636_3767487","newRFV":"96671563636363636","transactionHash":"0xf5a08857ef77f78c37a96b2cb036509de8da2568226fe65e6b6fea833d47da51","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96893459393939394_3767670	1725250740	80084	3767670	637	RFVChanged	{"blockNumber":3767670,"blockTimestamp":1725250740,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_96893459393939394_3767670","newRFV":"96893459393939394","transactionHash":"0xc26718caefcc1c931dcf0571d125b82ef7cec3a695f08e8ebc48176af8a4b04e","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_97087618181818181_3767878	1725251175	80084	3767878	222	RFVChanged	{"blockNumber":3767878,"blockTimestamp":1725251175,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_97087618181818181_3767878","newRFV":"97087618181818181","transactionHash":"0x92faeb2010d19f78ace982739840211cb6aa87fad975d58b133bd8089863751d","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9320000000000000000_3799882	1725316387	80084	3799882	134	RFVChanged	{"blockNumber":3799882,"blockTimestamp":1725316387,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9320000000000000000_3799882","newRFV":"9320000000000000000","transactionHash":"0xfdacb51ce5af20316bdb2c8cc05639989bbce5a9524b2ede635a49123b06a9a1","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_103141287700534759_3800407	1725317423	80084	3800407	180	RFVChanged	{"blockNumber":3800407,"blockTimestamp":1725317423,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_103141287700534759_3800407","newRFV":"103141287700534759","transactionHash":"0x65d234ce8dfc1f261a964dd43f4418909336cdb3ce0641aac6e3f3332f87a932","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059324468612333837_3800600	1725317801	80084	3800600	48	RFVChanged	{"blockNumber":3800600,"blockTimestamp":1725317801,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059324468612333837_3800600","newRFV":"1059324468612333837","transactionHash":"0x00c61a471009f27dc14b5cdfdc26a73bfaf70170c35f57858127a653614d0a44","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_108522327272727272_3800976	1725318540	80084	3800976	160	RFVChanged	{"blockNumber":3800976,"blockTimestamp":1725318540,"chain":"BERACHAIN_BARTIO","id":"80084_0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E_108522327272727272_3800976","newRFV":"108522327272727272","transactionHash":"0x4c69f5e29d11c04455ffe3452e5ee42fe4c342d188bba3ce187fd59d9d859b36","treasuryAddress":"0xBe53Db514eBe5506C7E5780cd50e92Fa6399433E"}	\N	\N	\N	\N
80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_1010000000000000_3824805	1725365887	80084	3824805	116	RFVChanged	{"blockNumber":3824805,"blockTimestamp":1725365887,"chain":"BERACHAIN_BARTIO","id":"80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_1010000000000000_3824805","newRFV":"1010000000000000","transactionHash":"0xa988ebd11f7f1f583aded65ca83c13d306ac6cd24e168d59ba2b68dc9c5830b2","treasuryAddress":"0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771146551934480_3826507	1725369304	80084	3826507	22	RFVChanged	{"blockNumber":3826507,"blockTimestamp":1725369304,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14771146551934480_3826507","newRFV":"14771146551934480","transactionHash":"0xaa4dbdbb564e3864a47f2489426839e6508a8523fd848dfd8f5163f2e3917724","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14788606551934480_3833484	1725383199	80084	3833484	19	RFVChanged	{"blockNumber":3833484,"blockTimestamp":1725383199,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_14788606551934480_3833484","newRFV":"14788606551934480","transactionHash":"0xf7cff4514522f1ab89139ebb96243123b12e4595c924bcdb03602739895a75ec","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839169	1725394369	80084	3839169	90	RFVChanged	{"blockNumber":3839169,"blockTimestamp":1725394369,"chain":"BERACHAIN_BARTIO","id":"80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839169","newRFV":"1600000000000000000","transactionHash":"0xac8dd139a9ea786f9e77a42f0134fbdaab032fb5b6586a53f8fa1b8b39714e09","treasuryAddress":"0x8628E8B3142511B1B9D389d4ccb9F9613818e310"}	\N	\N	\N	\N
80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839409	1725394831	80084	3839409	82	RFVChanged	{"blockNumber":3839409,"blockTimestamp":1725394831,"chain":"BERACHAIN_BARTIO","id":"80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1600000000000000000_3839409","newRFV":"1600000000000000000","transactionHash":"0x04952f50ebb279e0aefa44b47eaa7fef0c13b9e9a56a8748b1379646f07b3507","treasuryAddress":"0x8628E8B3142511B1B9D389d4ccb9F9613818e310"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_15788606551934480_3843581	1725402948	80084	3843581	68	RFVChanged	{"blockNumber":3843581,"blockTimestamp":1725402948,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_15788606551934480_3843581","newRFV":"15788606551934480","transactionHash":"0x5ef8a3ff63451b2ce3a0fc35c558ea70e726f8b20e95ee1d7d51977638f4318e","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1000000000000000000_3852948	1725421061	80084	3852948	208	RFVChanged	{"blockNumber":3852948,"blockTimestamp":1725421061,"chain":"BERACHAIN_BARTIO","id":"80084_0x8628E8B3142511B1B9D389d4ccb9F9613818e310_1000000000000000000_3852948","newRFV":"1000000000000000000","transactionHash":"0x54089a43e5748eedf23cc4270db9601f41fff772ea86ea4a4469203c814ea1b6","treasuryAddress":"0x8628E8B3142511B1B9D389d4ccb9F9613818e310"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4082044438612962902_3857338	1725429613	80084	3857338	107	RFVChanged	{"blockNumber":3857338,"blockTimestamp":1725429613,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4082044438612962902_3857338","newRFV":"4082044438612962902","transactionHash":"0x8819d716fcf8bb91352e9ec800641b99aa28947646fd5d6c350b4e16faf0bebf","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4547160717682730344_3857398	1725429720	80084	3857398	80	RFVChanged	{"blockNumber":3857398,"blockTimestamp":1725429720,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4547160717682730344_3857398","newRFV":"4547160717682730344","transactionHash":"0xb4c334fd900989642f0aa3e9bbe4ab99b6a22525d2fd29720adf5b96783e3ac7","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7273333333333333333_3857518	1725429955	80084	3857518	234	RFVChanged	{"blockNumber":3857518,"blockTimestamp":1725429955,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7273333333333333333_3857518","newRFV":"7273333333333333333","transactionHash":"0x92351d98a13e44c3e2f118f157e3ecfd0d161c0973ec953b8b5773a51fb5c3f6","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16188606551934480_3857628	1725430168	80084	3857628	165	RFVChanged	{"blockNumber":3857628,"blockTimestamp":1725430168,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16188606551934480_3857628","newRFV":"16188606551934480","transactionHash":"0xf21781d8c216066498949d82d331a3f92ab68fc097966d058184304c02e0b94b","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_2010000000000000_3871891	1725458338	80084	3871891	80	RFVChanged	{"blockNumber":3871891,"blockTimestamp":1725458338,"chain":"BERACHAIN_BARTIO","id":"80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_2010000000000000_3871891","newRFV":"2010000000000000","transactionHash":"0x3c941771b273cd50d1b69efa24408884880819d3f74216d2475c57c7d875a604","treasuryAddress":"0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16190606551934480_3876975	1725468448	80084	3876975	135	RFVChanged	{"blockNumber":3876975,"blockTimestamp":1725468448,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16190606551934480_3876975","newRFV":"16190606551934480","transactionHash":"0xcd80cd257c4d4ec0163a47a4618f321e651a98d6198466d7c0cdf5f2ef1b9a29","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7280000000000000000_3886260	1725486615	80084	3886260	704	RFVChanged	{"blockNumber":3886260,"blockTimestamp":1725486615,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7280000000000000000_3886260","newRFV":"7280000000000000000","transactionHash":"0x0932cc50112969ebbe093a7ed180e856a029768737cb655b4d4de7a9faadb916","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13725490196078431_3886500	1725487092	80084	3886500	79	RFVChanged	{"blockNumber":3886500,"blockTimestamp":1725487092,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13725490196078431_3886500","newRFV":"13725490196078431","transactionHash":"0x2f936d8607118afb1616d60387282b49f22c252c223c849c098c1f0aed7382ba","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13823529411764705_3887162	1725488461	80084	3887162	494	RFVChanged	{"blockNumber":3887162,"blockTimestamp":1725488461,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13823529411764705_3887162","newRFV":"13823529411764705","transactionHash":"0xb15c952dcfac608cf3489e99cfc198163d98b0b4ab82f557f36438e2a449474e","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16200606551934480_3892395	1725499209	80084	3892395	65	RFVChanged	{"blockNumber":3892395,"blockTimestamp":1725499209,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16200606551934480_3892395","newRFV":"16200606551934480","transactionHash":"0x2b04d3483f2a4fea62bae14a82cefd7a61d51488ec67e66073c4b7b6b883b302","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13848411764705882_3895532	1725505606	80084	3895532	614	RFVChanged	{"blockNumber":3895532,"blockTimestamp":1725505606,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_13848411764705882_3895532","newRFV":"13848411764705882","transactionHash":"0x155695dee86fb47356455c8a3bda64647d1aaae8091b07a476c52ac707ba180b","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_11557947050515121_3896765	1725508123	80084	3896765	76	RFVChanged	{"blockNumber":3896765,"blockTimestamp":1725508123,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_11557947050515121_3896765","newRFV":"11557947050515121","transactionHash":"0x2e429b58dc84d4a152963ddba3142b45e901f6c52cfc73a018728d8fbb88ac9b","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9754404791197783_3897850	1725510292	80084	3897850	40	RFVChanged	{"blockNumber":3897850,"blockTimestamp":1725510292,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9754404791197783_3897850","newRFV":"9754404791197783","transactionHash":"0x7e2bfcba64c3370714d9931f1b3b7cd65afba5719f93620e32be8646dafc1cdb","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9906578704241261_3898389	1725511392	80084	3898389	717	RFVChanged	{"blockNumber":3898389,"blockTimestamp":1725511392,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9906578704241261_3898389","newRFV":"9906578704241261","transactionHash":"0xac64044854b0286fbc03f1531dc5cb1189b8f70e5a2f1b6b536500b0906a4157","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4593672345589707088_3924648	1725565151	80084	3924648	140	RFVChanged	{"blockNumber":3924648,"blockTimestamp":1725565151,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4593672345589707088_3924648","newRFV":"4593672345589707088","transactionHash":"0x4d0a86b3e88b8e890b273d9d2cbfc8d8a2cd15a723f6a547250b36d2cb7fd606","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9004923622491555_3932783	1725581279	80084	3932783	43	RFVChanged	{"blockNumber":3932783,"blockTimestamp":1725581279,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9004923622491555_3932783","newRFV":"9004923622491555","transactionHash":"0xf87a2e961f892e70532d8d8f84be4d0fbcf4a4f3715395c17b14ceb69cd49f21","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16202606551934480_3947210	1725610099	80084	3947210	111	RFVChanged	{"blockNumber":3947210,"blockTimestamp":1725610099,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16202606551934480_3947210","newRFV":"16202606551934480","transactionHash":"0x99d82c882d36f66e11170906bcc36b0663e1752651b56ba23f9db56628a95988","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222606551934480_3954766	1725625175	80084	3954766	57	RFVChanged	{"blockNumber":3954766,"blockTimestamp":1725625175,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222606551934480_3954766","newRFV":"16222606551934480","transactionHash":"0x53b8dc9fead4f2229a59957e65eb5de4c588ff59a74d96329f368058c6a716c1","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4616928159543195460_3954794	1725625217	80084	3954794	112	RFVChanged	{"blockNumber":3954794,"blockTimestamp":1725625217,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4616928159543195460_3954794","newRFV":"4616928159543195460","transactionHash":"0xd61c41ede7d2cb158807de3bd7e2a40818674db9fb3d14b606ba5f7ff06106c4","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9353333333333333333_3954821	1725625269	80084	3954821	78	RFVChanged	{"blockNumber":3954821,"blockTimestamp":1725625269,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9353333333333333333_3954821","newRFV":"9353333333333333333","transactionHash":"0x10d9e2035c737343b78491e516aac1eca120e5cbb2755531e3fefb8393bb9dbd","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7313333333333333333_3954842	1725625306	80084	3954842	41	RFVChanged	{"blockNumber":3954842,"blockTimestamp":1725625306,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7313333333333333333_3954842","newRFV":"7313333333333333333","transactionHash":"0x3b6646e9da8317bd2281eaad67a77951a556e20a9bdd628d5657b62971017469","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222608542864585_3958498	1725632814	80084	3958498	46	RFVChanged	{"blockNumber":3958498,"blockTimestamp":1725632814,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222608542864585_3958498","newRFV":"16222608542864585","transactionHash":"0x002540ae837fba1fbb73939b966c7a9ac3fd92eda45d976cee10065be2009e66","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7380000000000000000_3967139	1725650190	80084	3967139	91	RFVChanged	{"blockNumber":3967139,"blockTimestamp":1725650190,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7380000000000000000_3967139","newRFV":"7380000000000000000","transactionHash":"0x41daaea741d8cc9515c04b9d3259956e507f372f5b7c8f461745fba9201744e7","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4619253740938544297_3972465	1725660683	80084	3972465	114	RFVChanged	{"blockNumber":3972465,"blockTimestamp":1725660683,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4619253740938544297_3972465","newRFV":"4619253740938544297","transactionHash":"0xf6c56b98fea46b7298db76f888641121e5af539c501d9eae6ee90301ce42d4e2","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621579322333893134_3972475	1725660712	80084	3972475	432	RFVChanged	{"blockNumber":3972475,"blockTimestamp":1725660712,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621579322333893134_3972475","newRFV":"4621579322333893134","transactionHash":"0x9703b00fff84ef56ba676a379e657ba1cbd164c34b12508b1c4d4f67c1f8eb95","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9360000000000000000_3972500	1725660759	80084	3972500	30	RFVChanged	{"blockNumber":3972500,"blockTimestamp":1725660759,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9360000000000000000_3972500","newRFV":"9360000000000000000","transactionHash":"0x68a4c5fc79b595a02a79f3671eb577f3cd083e19b7ab4ec72428bd8c4ebef0c0","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995022237578307954_3972509	1725660775	80084	3972509	89	RFVChanged	{"blockNumber":3972509,"blockTimestamp":1725660775,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995022237578307954_3972509","newRFV":"1995022237578307954","transactionHash":"0xe9d69405bd3f3761bb0dc2ff8374a3554ad1ac4ec67db8829fadc15b5bd8c481","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9015875556627018_3972774	1725661301	80084	3972774	195	RFVChanged	{"blockNumber":3972774,"blockTimestamp":1725661301,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_9015875556627018_3972774","newRFV":"9015875556627018","transactionHash":"0x1d99c9fcc828a7dab9fde3ced914ce4e4afb03e2bd8ad0166d3d263a9a5f207e","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059467410355649862_3979803	1725674956	80084	3979803	45	RFVChanged	{"blockNumber":3979803,"blockTimestamp":1725674956,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059467410355649862_3979803","newRFV":"1059467410355649862","transactionHash":"0x57d4b1e74f5e8f2470d7782b4325409b71240b1280b398258f64b174c226f8a3","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2982456140350877_3986050	1725687276	80084	3986050	107	RFVChanged	{"blockNumber":3986050,"blockTimestamp":1725687276,"chain":"BERACHAIN_BARTIO","id":"80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2982456140350877_3986050","newRFV":"2982456140350877","transactionHash":"0x8f5538f9190954286304472933c866b0da4f5b7c988fa55d243f46cc5fa82730","treasuryAddress":"0xB3281C2e3bC254d491d5eEf55835d02396673764"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059767710655950163_4000976	1725717807	80084	4000976	120	RFVChanged	{"blockNumber":4000976,"blockTimestamp":1725717807,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059767710655950163_4000976","newRFV":"1059767710655950163","transactionHash":"0x22f4366bce2889a6c7e9c99d09f894912967ace0f72ac23e01e21bb0504e9690","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621983076994692971_4009206	1725734673	80084	4009206	208	RFVChanged	{"blockNumber":4009206,"blockTimestamp":1725734673,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4621983076994692971_4009206","newRFV":"4621983076994692971","transactionHash":"0x6c1b2fdc25d53de939739f44d58fc4beec8b758b714e98cabf32d831a6aaba8d","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4622215635134227855_4011739	1725739776	80084	4011739	320	RFVChanged	{"blockNumber":4011739,"blockTimestamp":1725739776,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4622215635134227855_4011739","newRFV":"4622215635134227855","transactionHash":"0x4ef086e9306f8dac81035b724ed954930bf7908e0ad0d2aca89cea3776110e70","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222808542864585_4011873	1725740036	80084	4011873	48	RFVChanged	{"blockNumber":4011873,"blockTimestamp":1725740036,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16222808542864585_4011873","newRFV":"16222808542864585","transactionHash":"0xb7be32ec918fe9128ba2835dfd9a166a6f8f0f8e95f5c0c7e17b56705de673df","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16223148542864585_4011892	1725740068	80084	4011892	161	RFVChanged	{"blockNumber":4011892,"blockTimestamp":1725740068,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16223148542864585_4011892","newRFV":"16223148542864585","transactionHash":"0xeb371a0190390d9aebbe6b07230358d3b18553b389e49200a330ef2dc73e43a9","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8677594690784407_4014964	1725746176	80084	4014964	29	RFVChanged	{"blockNumber":4014964,"blockTimestamp":1725746176,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8677594690784407_4014964","newRFV":"8677594690784407","transactionHash":"0x90c52d327fc2adebab2a32334302597f08318d38cfcedef94da8f1b5ab304045","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4626866797924925529_4015002	1725746259	80084	4015002	17	RFVChanged	{"blockNumber":4015002,"blockTimestamp":1725746259,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4626866797924925529_4015002","newRFV":"4626866797924925529","transactionHash":"0x3e026d8348ae04abd70506146da47bb0efd58b3ecd8f57257b04855a53253d19","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9426666666666666666_4041757	1725799177	80084	4041757	102	RFVChanged	{"blockNumber":4041757,"blockTimestamp":1725799177,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_9426666666666666666_4041757","newRFV":"9426666666666666666","transactionHash":"0xcca6463991699ad41a8c29d129b4e28b3a291a1b9e754ab277d4d3039d4934b1","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7446666666666666666_4041789	1725799243	80084	4041789	204	RFVChanged	{"blockNumber":4041789,"blockTimestamp":1725799243,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7446666666666666666_4041789","newRFV":"7446666666666666666","transactionHash":"0x3c66b2c45494bb64e1b91b0b53d05fa5510c9fd4e6495cf31bac255a861167de","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16241148542864585_4074136	1725863753	80084	4074136	5	RFVChanged	{"blockNumber":4074136,"blockTimestamp":1725863753,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16241148542864585_4074136","newRFV":"16241148542864585","transactionHash":"0x350413ca6e51b1ba5d03a6c9bace421d6fcc031dbccb8e973e79f7f52e3e54d8","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059872269964387538_4089893	1725897528	80084	4089893	70	RFVChanged	{"blockNumber":4089893,"blockTimestamp":1725897528,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059872269964387538_4089893","newRFV":"1059872269964387538","transactionHash":"0x250459f80a36f86f7edef6982c87c8bc15a15b48b7858b46430040b66bbc20b4","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000746328406542907_4098893	1725916460	80084	4098893	233	RFVChanged	{"blockNumber":4098893,"blockTimestamp":1725916460,"chain":"BERACHAIN_BARTIO","id":"80084_0x9321f6e31883F20B299aD541a1421D7a06DCCcAC_1000746328406542907_4098893","newRFV":"1000746328406542907","transactionHash":"0xa3ad12fea4b08ba1a43d9b7f8e0bc265aff5d93322a4c25daa3403b6a4f1f45c","treasuryAddress":"0x9321f6e31883F20B299aD541a1421D7a06DCCcAC"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16341148542864585_4100409	1725919580	80084	4100409	158	RFVChanged	{"blockNumber":4100409,"blockTimestamp":1725919580,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16341148542864585_4100409","newRFV":"16341148542864585","transactionHash":"0x06bd7a5908f2b9053cc93ed0dbd8b445606ac3e18f33b36f6bfb600e1d399a0f","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8467667874725460_4106515	1725931799	80084	4106515	52	RFVChanged	{"blockNumber":4106515,"blockTimestamp":1725931799,"chain":"BERACHAIN_BARTIO","id":"80084_0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794_8467667874725460_4106515","newRFV":"8467667874725460","transactionHash":"0x3dee443a8109fbd57ceaee0f03d827b73c4a0473e8149ac59e2138d552b56e99","treasuryAddress":"0x1fb02e215dAAF7AB45198D44Ebe485c973cfc794"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7453333333333333333_4111432	1725941630	80084	4111432	51	RFVChanged	{"blockNumber":4111432,"blockTimestamp":1725941630,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_7453333333333333333_4111432","newRFV":"7453333333333333333","transactionHash":"0x321179f480c6176c0e936c41c0a763437134caa5af373615236a5d39f91e6eed","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15426666666666666666_4118181	1725955314	80084	4118181	72	RFVChanged	{"blockNumber":4118181,"blockTimestamp":1725955314,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15426666666666666666_4118181","newRFV":"15426666666666666666","transactionHash":"0xb32842d825c541c8a370efc7ee3490216ef3baf1f02197a016d507196d31e8fc","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_12010000000000000_4126941	1725973604	80084	4126941	79	RFVChanged	{"blockNumber":4126941,"blockTimestamp":1725973604,"chain":"BERACHAIN_BARTIO","id":"80084_0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf_12010000000000000_4126941","newRFV":"12010000000000000","transactionHash":"0x81e8e1c7f551e616e1a37eac96ce56f48c90d37f08f598901dd6439e4e8d61bc","treasuryAddress":"0x51487a0270fa56F6FCFCEEc82328876d19eE8cCf"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16342148542864585_4141574	1726003176	80084	4141574	86	RFVChanged	{"blockNumber":4141574,"blockTimestamp":1726003176,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16342148542864585_4141574","newRFV":"16342148542864585","transactionHash":"0xc33dcfbd95d2598cfc4f95104931dac38107fdc066c4bd49bf0de6d57dc0a423","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629192379320274367_4141586	1726003208	80084	4141586	104	RFVChanged	{"blockNumber":4141586,"blockTimestamp":1726003208,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629192379320274367_4141586","newRFV":"4629192379320274367","transactionHash":"0xb715aa740c79365d6795c83863fef593143ef58cebd787487b07f0138ffce812","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2945161290322580_4146684	1726013594	80084	4146684	666	RFVChanged	{"blockNumber":4146684,"blockTimestamp":1726013594,"chain":"BERACHAIN_BARTIO","id":"80084_0xB3281C2e3bC254d491d5eEf55835d02396673764_2945161290322580_4146684","newRFV":"2945161290322580","transactionHash":"0x20bf053b03be7054b9b8b707b75d2a75aac16ee4ad730dfb3e38678bec4c987f","treasuryAddress":"0xB3281C2e3bC254d491d5eEf55835d02396673764"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15493333333333333333_4152808	1726025522	80084	4152808	144	RFVChanged	{"blockNumber":4152808,"blockTimestamp":1726025522,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15493333333333333333_4152808","newRFV":"15493333333333333333","transactionHash":"0x46faf5b7962c1d483ab3e565e53d3e456bfba94a2f88eee3f2a193f73c28597b","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059900876861562692_4195369	1726109810	80084	4195369	164	RFVChanged	{"blockNumber":4195369,"blockTimestamp":1726109810,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059900876861562692_4195369","newRFV":"1059900876861562692","transactionHash":"0xabbf3ed3c144c20c4aa1e8d0c92f9c09e4e7d824d4e16abfa9e62147d50e7f87","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995042613934680356_4217694	1726156088	80084	4217694	31	RFVChanged	{"blockNumber":4217694,"blockTimestamp":1726156088,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995042613934680356_4217694","newRFV":"1995042613934680356","transactionHash":"0xb12c2c8082d43609756c990f5301460d6d532ac3d550221c435349ce70cd555a","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344148542864585_4261883	1726251369	80084	4261883	182	RFVChanged	{"blockNumber":4261883,"blockTimestamp":1726251369,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344148542864585_4261883","newRFV":"16344148542864585","transactionHash":"0x9829696c92f864a47f6bb55d4e0eb9cb41cda3b9b959b038b4f54967e2c40ae6","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059929484530863497_4303538	1726343091	80084	4303538	26	RFVChanged	{"blockNumber":4303538,"blockTimestamp":1726343091,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1059929484530863497_4303538","newRFV":"1059929484530863497","transactionHash":"0xcb6acbb765ea37a544d4c1ff33e6c59475e8593d88b9fd49f9be07a2bbe63110","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344348542864585_4349050	1726440530	80084	4349050	217	RFVChanged	{"blockNumber":4349050,"blockTimestamp":1726440530,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16344348542864585_4349050","newRFV":"16344348542864585","transactionHash":"0xc4f7b0c7849afdf5641a1206a9a9b31c0c60cdb1fac5d3c14f002a55891acbb3","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_8120000000000000000_4349542	1726441531	80084	4349542	57	RFVChanged	{"blockNumber":4349542,"blockTimestamp":1726441531,"chain":"BERACHAIN_BARTIO","id":"80084_0xe0941F720B65d3d924FdEF58597da9cBb28f48a6_8120000000000000000_4349542","newRFV":"8120000000000000000","transactionHash":"0xa93a5a1d45b047724c1d308935e169c6171fbabc43d6b0eeb92e759955c86e3a","treasuryAddress":"0xe0941F720B65d3d924FdEF58597da9cBb28f48a6"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16444348542864585_4349568	1726441585	80084	4349568	12	RFVChanged	{"blockNumber":4349568,"blockTimestamp":1726441585,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16444348542864585_4349568","newRFV":"16444348542864585","transactionHash":"0xfa523204df4d2177840b906b167ed33703f8c365d41119e0199d72fd501a6f10","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15826666666666666666_4349584	1726441629	80084	4349584	13	RFVChanged	{"blockNumber":4349584,"blockTimestamp":1726441629,"chain":"BERACHAIN_BARTIO","id":"80084_0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8_15826666666666666666_4349584","newRFV":"15826666666666666666","transactionHash":"0x9d5c5dd0d3b5feb8ddb19931e024f185ab72c2a907f0f44fb4bd3ad7a651c87b","treasuryAddress":"0x756be8ECebf815A7EA4Af6dee80E4111E559D1A8"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_0_4437743	1726625612	80084	4437743	278	RFVChanged	{"blockNumber":4437743,"blockTimestamp":1726625612,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_0_4437743","newRFV":"0","transactionHash":"0xb604a16d781a5876f4c94f61d9e3a20f5f461368dfd4e6a367ab9f2b3ed8a626","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_16666666666666666_4438319	1726626749	80084	4438319	584	RFVChanged	{"blockNumber":4438319,"blockTimestamp":1726626749,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_16666666666666666_4438319","newRFV":"16666666666666666","transactionHash":"0x8b4a93d0afc3a3b06aceaa01bfabe7bd3ce44e0757ff4f4b5bfed3d97f37409e","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18333333333333333_4439849	1726629764	80084	4439849	129	RFVChanged	{"blockNumber":4439849,"blockTimestamp":1726629764,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18333333333333333_4439849","newRFV":"18333333333333333","transactionHash":"0xd4ac570c2398476aa14b1a9f060fa30c721e8f1e2cd699a37489c865d13213bd","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629424937459809250_4455659	1726661438	80084	4455659	77	RFVChanged	{"blockNumber":4455659,"blockTimestamp":1726661438,"chain":"BERACHAIN_BARTIO","id":"80084_0xE55A1ff57C48b02a788711f9412Ca316686F9528_4629424937459809250_4455659","newRFV":"4629424937459809250","transactionHash":"0xf07d01a2d020c2ac82065a3fdeda6315bfbae4356ff0f8d70e1b1c5f47d85358","treasuryAddress":"0xE55A1ff57C48b02a788711f9412Ca316686F9528"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361299435028248_4468576	1726687332	80084	4468576	101	RFVChanged	{"blockNumber":4468576,"blockTimestamp":1726687332,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361299435028248_4468576","newRFV":"18361299435028248","transactionHash":"0xfa73db29f076d4950fe5d210e1bcc2823c3c79959989cd25b5e11f5227e69a3c","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361341227459175_4478283	1726705953	80084	4478283	373	RFVChanged	{"blockNumber":4478283,"blockTimestamp":1726705953,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361341227459175_4478283","newRFV":"18361341227459175","transactionHash":"0x7be20c57f11f3376363532046e3e8e7ebf568cb94b246a4a9a9692fdedfd4d56","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361543711787013_4480026	1726709283	80084	4480026	217	RFVChanged	{"blockNumber":4480026,"blockTimestamp":1726709283,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361543711787013_4480026","newRFV":"18361543711787013","transactionHash":"0xe5bfaa42138e390f7f3bb69979af22860384c446df86d95322341c008c218ac8","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361611206562959_4480669	1726710512	80084	4480669	180	RFVChanged	{"blockNumber":4480669,"blockTimestamp":1726710512,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18361611206562959_4480669","newRFV":"18361611206562959","transactionHash":"0x706cadc003642c90b742d5726056f79d126a36abdda808d50b475d447111556f","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362029130872223_4481074	1726711271	80084	4481074	111	RFVChanged	{"blockNumber":4481074,"blockTimestamp":1726711271,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362029130872223_4481074","newRFV":"18362029130872223","transactionHash":"0x891b9892f00d6d30b9ec328a1a0fe63587ddfe8374508ae4a65128792d9d7845","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362299527900317_4481096	1726711336	80084	4481096	362	RFVChanged	{"blockNumber":4481096,"blockTimestamp":1726711336,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_18362299527900317_4481096","newRFV":"18362299527900317","transactionHash":"0x37225d878a2c976441b12ed33e90a01ea0676a7af824619b4c453fc3b6ab8854","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47553188339426841_4497856	1726743485	80084	4497856	118	RFVChanged	{"blockNumber":4497856,"blockTimestamp":1726743485,"chain":"BERACHAIN_BARTIO","id":"80084_0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79_47553188339426841_4497856","newRFV":"47553188339426841","transactionHash":"0xb095ab7df4d385cbe027e1b066bcd2a5d6f6b24c6ca90576a44c8245e2e88c0a","treasuryAddress":"0xb415417c1Ad2c47dECD7c38232B18e0C1c5FFa79"}	\N	\N	\N	\N
80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995108864304106744_4498940	1726745583	80084	4498940	304	RFVChanged	{"blockNumber":4498940,"blockTimestamp":1726745583,"chain":"BERACHAIN_BARTIO","id":"80084_0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804_1995108864304106744_4498940","newRFV":"1995108864304106744","transactionHash":"0xc0c1450546771b25af51f87668971d7a3d50adf4b719ff7bb5d69599d8b86a27","treasuryAddress":"0xd65F2ca0F3aca30cf8E654d4084C86fA1739B804"}	\N	\N	\N	\N
80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1060043834915224133_4498959	1726745619	80084	4498959	651	RFVChanged	{"blockNumber":4498959,"blockTimestamp":1726745619,"chain":"BERACHAIN_BARTIO","id":"80084_0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e_1060043834915224133_4498959","newRFV":"1060043834915224133","transactionHash":"0x853f079484a28dff0e64c07493f6de8d6d0d9e00a95df738d96085d0f8cd2d16","treasuryAddress":"0xc0f974934C19E667C00EBFCa7e793Cb02F023A1e"}	\N	\N	\N	\N
80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16464348542864585_4504762	1726756697	80084	4504762	25	RFVChanged	{"blockNumber":4504762,"blockTimestamp":1726756697,"chain":"BERACHAIN_BARTIO","id":"80084_0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f_16464348542864585_4504762","newRFV":"16464348542864585","transactionHash":"0x71dea112b33f17e980e0552118a0c04b53e2e2229481d4b1ba94294eadaa9506","treasuryAddress":"0xC46D17a6934a4148b0DF963Be959b40dDcF70A2f"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34722927869101978_4517102	1726780605	80084	4517102	125	RFVChanged	{"blockNumber":4517102,"blockTimestamp":1726780605,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34722927869101978_4517102","newRFV":"34722927869101978","transactionHash":"0x45e92462fde8e15e2220373bfccf60681eedfae79333061f68c5be4849834ae1","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809437248297028_4519221	1726784678	80084	4519221	95	RFVChanged	{"blockNumber":4519221,"blockTimestamp":1726784678,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809437248297028_4519221","newRFV":"34809437248297028","transactionHash":"0xb4c4e69a32e1a5b938afedcbb9dbe31f3b89c9edf613ea137cd10b7e40d4b6b1","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809747286473538_4519919	1726786005	80084	4519919	252	RFVChanged	{"blockNumber":4519919,"blockTimestamp":1726786005,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809747286473538_4519919","newRFV":"34809747286473538","transactionHash":"0x9d885c410dcf36254a8d0fcdf202a62b0ed8a18f589cefc49037a6626fe6d15c","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809812568306010_4520131	1726786425	80084	4520131	147	RFVChanged	{"blockNumber":4520131,"blockTimestamp":1726786425,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34809812568306010_4520131","newRFV":"34809812568306010","transactionHash":"0xc3b2ef6db4107a4a08915b45c36ff482c5ad9bc7099ff13e6baec4abd66847c2","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810246702597499_4520570	1726787224	80084	4520570	157	RFVChanged	{"blockNumber":4520570,"blockTimestamp":1726787224,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810246702597499_4520570","newRFV":"34810246702597499","transactionHash":"0x0822e68de76bfa7b123a8809715c9f57ca859612b1c114bc3e7affe84f21b2e3","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810804933003967_4520734	1726787515	80084	4520734	288	RFVChanged	{"blockNumber":4520734,"blockTimestamp":1726787515,"chain":"BERACHAIN_BARTIO","id":"80084_0x55E58ea273c0d962E8D56BB7E3F1756842128154_34810804933003967_4520734","newRFV":"34810804933003967","transactionHash":"0x2163ed213accd5b8c261552d3bd3e7d324f15201fb47d631ade77b738b66a93c","treasuryAddress":"0x55E58ea273c0d962E8D56BB7E3F1756842128154"}	\N	\N	\N	\N
80084_0xD33c9b08BCa676E2d5E496A00bB00FaBbB4F7D55_1000000000000000000_4540764	1726825718	80084	4540764	495	RFVChanged	{"blockNumber":4540764,"blockTimestamp":1726825718,"chain":"BERACHAIN_BARTIO","id":"80084_0xD33c9b08BCa676E2d5E496A00bB00FaBbB4F7D55_1000000000000000000_4540764","newRFV":"1000000000000000000","transactionHash":"0x18edb2e2d398158cdda968a7faa58a2d68b0fba2503e67d03e76e73d2ce43caf","treasuryAddress":"0xD33c9b08BCa676E2d5E496A00bB00FaBbB4F7D55"}	\N	\N	\N	\N
\.


--
-- Data for Name: entity_history_filter; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.entity_history_filter (entity_id, chain_id, old_val, new_val, block_number, block_timestamp, previous_block_number, log_index, previous_log_index, entity_type) FROM stdin;
\.


--
-- Data for Name: event_sync_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event_sync_state (chain_id, block_number, log_index, block_timestamp) FROM stdin;
80084	4540764	495	1726825718
\.


--
-- Data for Name: persisted_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.persisted_state (id, envio_version, config_hash, schema_hash, handler_files_hash, abi_files_hash) FROM stdin;
1	2.3.0	9f16aec3eb66e30e7caae75e9b2f52ee5c54463255bc8bfe38cea76b1afa9104	7b4d122c834ca8dc48ebdadcc1960a810edce7a813b8bf000cd4b2c63fc7ea04	e15a173394a48a02cbf2c60fae2e88a6a719258be443d57e8124167aea8fce90	a2440fe1ab32707cf6eb3dc5f03ee007fbe5651dffef9071bd9cfe40bf1054e2
\.


--
-- Data for Name: raw_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.raw_events (chain_id, event_id, event_name, contract_name, block_number, log_index, src_address, block_hash, block_timestamp, block_fields, transaction_fields, params, db_write_timestamp) FROM stdin;
\.


--
-- Name: persisted_state_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.persisted_state_id_seq', 1, false);


--
-- Name: hdb_action_log hdb_action_log_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_action_log
    ADD CONSTRAINT hdb_action_log_pkey PRIMARY KEY (id);


--
-- Name: hdb_cron_event_invocation_logs hdb_cron_event_invocation_logs_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
    ADD CONSTRAINT hdb_cron_event_invocation_logs_pkey PRIMARY KEY (id);


--
-- Name: hdb_cron_events hdb_cron_events_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_events
    ADD CONSTRAINT hdb_cron_events_pkey PRIMARY KEY (id);


--
-- Name: hdb_metadata hdb_metadata_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_metadata
    ADD CONSTRAINT hdb_metadata_pkey PRIMARY KEY (id);


--
-- Name: hdb_metadata hdb_metadata_resource_version_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_metadata
    ADD CONSTRAINT hdb_metadata_resource_version_key UNIQUE (resource_version);


--
-- Name: hdb_scheduled_event_invocation_logs hdb_scheduled_event_invocation_logs_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
    ADD CONSTRAINT hdb_scheduled_event_invocation_logs_pkey PRIMARY KEY (id);


--
-- Name: hdb_scheduled_events hdb_scheduled_events_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_events
    ADD CONSTRAINT hdb_scheduled_events_pkey PRIMARY KEY (id);


--
-- Name: hdb_schema_notifications hdb_schema_notifications_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_schema_notifications
    ADD CONSTRAINT hdb_schema_notifications_pkey PRIMARY KEY (id);


--
-- Name: hdb_version hdb_version_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_version
    ADD CONSTRAINT hdb_version_pkey PRIMARY KEY (hasura_uuid);


--
-- Name: RFVChanged RFVChanged_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."RFVChanged"
    ADD CONSTRAINT "RFVChanged_pkey" PRIMARY KEY (id);


--
-- Name: chain_metadata chain_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_metadata
    ADD CONSTRAINT chain_metadata_pkey PRIMARY KEY (chain_id);


--
-- Name: dynamic_contract_registry dynamic_contract_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dynamic_contract_registry
    ADD CONSTRAINT dynamic_contract_registry_pkey PRIMARY KEY (chain_id, contract_address);


--
-- Name: end_of_block_range_scanned_data end_of_block_range_scanned_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.end_of_block_range_scanned_data
    ADD CONSTRAINT end_of_block_range_scanned_data_pkey PRIMARY KEY (chain_id, block_number);


--
-- Name: entity_history_filter entity_history_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_history_filter
    ADD CONSTRAINT entity_history_filter_pkey PRIMARY KEY (entity_id, chain_id, block_number, block_timestamp, log_index, previous_log_index, entity_type);


--
-- Name: entity_history entity_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_history
    ADD CONSTRAINT entity_history_pkey PRIMARY KEY (entity_id, block_timestamp, chain_id, block_number, log_index, entity_type);


--
-- Name: event_sync_state event_sync_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_sync_state
    ADD CONSTRAINT event_sync_state_pkey PRIMARY KEY (chain_id);


--
-- Name: persisted_state persisted_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.persisted_state
    ADD CONSTRAINT persisted_state_pkey PRIMARY KEY (id);


--
-- Name: raw_events raw_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_events
    ADD CONSTRAINT raw_events_pkey PRIMARY KEY (chain_id, event_id);


--
-- Name: hdb_cron_event_invocation_event_id; Type: INDEX; Schema: hdb_catalog; Owner: postgres
--

CREATE INDEX hdb_cron_event_invocation_event_id ON hdb_catalog.hdb_cron_event_invocation_logs USING btree (event_id);


--
-- Name: hdb_cron_event_status; Type: INDEX; Schema: hdb_catalog; Owner: postgres
--

CREATE INDEX hdb_cron_event_status ON hdb_catalog.hdb_cron_events USING btree (status);


--
-- Name: hdb_cron_events_unique_scheduled; Type: INDEX; Schema: hdb_catalog; Owner: postgres
--

CREATE UNIQUE INDEX hdb_cron_events_unique_scheduled ON hdb_catalog.hdb_cron_events USING btree (trigger_name, scheduled_time) WHERE (status = 'scheduled'::text);


--
-- Name: hdb_scheduled_event_status; Type: INDEX; Schema: hdb_catalog; Owner: postgres
--

CREATE INDEX hdb_scheduled_event_status ON hdb_catalog.hdb_scheduled_events USING btree (status);


--
-- Name: hdb_version_one_row; Type: INDEX; Schema: hdb_catalog; Owner: postgres
--

CREATE UNIQUE INDEX hdb_version_one_row ON hdb_catalog.hdb_version USING btree (((version IS NOT NULL)));


--
-- Name: entity_history_entity_type_entity_id_block_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX entity_history_entity_type_entity_id_block_timestamp ON public.entity_history USING btree (entity_type, entity_id, block_timestamp);


--
-- Name: hdb_cron_event_invocation_logs hdb_cron_event_invocation_logs_event_id_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
    ADD CONSTRAINT hdb_cron_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_cron_events(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: hdb_scheduled_event_invocation_logs hdb_scheduled_event_invocation_logs_event_id_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: postgres
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
    ADD CONSTRAINT hdb_scheduled_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_scheduled_events(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;


CREATE TABLE "public"."NftTransfers"(
    id TEXT PRIMARY KEY,
    chain VARCHAR(255) NOT NULL,
    block_timestamp INT NOT NULL,
    block_number INT NOT NULL,
    transaction_hash VARCHAR(255) NOT NULL,
    contract_address VARCHAR(255) NOT NULL,
    from_address VARCHAR(255) NOT NULL,
    to_address VARCHAR(255) NOT NULL,
    caller_address VARCHAR(255) NOT NULL,
    token_id TEXT NOT NULL,
    quantity BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TYPE entity_type ADD VALUE 'NftTransfers';

--
-- PostgreSQL database dump complete
--

