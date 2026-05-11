SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: dispatch_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dispatch_queue (
    id bigint NOT NULL,
    event_id bigint NOT NULL,
    priority text DEFAULT 'standard'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    locked_at timestamp with time zone,
    failed_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispatch_queue_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'standard'::text, 'bulk'::text]))),
    CONSTRAINT dispatch_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_flight'::text, 'done'::text, 'failed'::text])))
);


--
-- Name: dispatch_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dispatch_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dispatch_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dispatch_queue_id_seq OWNED BY public.dispatch_queue.id;


--
-- Name: notification_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_audit (
    id bigint NOT NULL,
    correlation_id uuid NOT NULL,
    event_id bigint,
    status text NOT NULL,
    channel text,
    rule_snapshot jsonb,
    payload jsonb,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
)
PARTITION BY RANGE (created_at);


--
-- Name: notification_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_audit_id_seq OWNED BY public.notification_audit.id;


--
-- Name: notification_audit_2026_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_audit_2026_05 (
    id bigint DEFAULT nextval('public.notification_audit_id_seq'::regclass) NOT NULL,
    correlation_id uuid NOT NULL,
    event_id bigint,
    status text NOT NULL,
    channel text,
    rule_snapshot jsonb,
    payload jsonb,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notification_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_events (
    id bigint NOT NULL,
    notification_type text NOT NULL,
    recipient_canonical text NOT NULL,
    recipient_type text NOT NULL,
    context_id text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    idempotency_hash text NOT NULL,
    idempotency_window_ts timestamp with time zone NOT NULL,
    correlation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notification_events_recipient_type_check CHECK ((recipient_type = ANY (ARRAY['email'::text, 'user_id'::text]))),
    CONSTRAINT notification_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'rejected'::text])))
)
PARTITION BY RANGE (idempotency_window_ts);


--
-- Name: notification_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_events_id_seq OWNED BY public.notification_events.id;


--
-- Name: notification_events_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_events_default (
    id bigint DEFAULT nextval('public.notification_events_id_seq'::regclass) NOT NULL,
    notification_type text NOT NULL,
    recipient_canonical text NOT NULL,
    recipient_type text NOT NULL,
    context_id text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    idempotency_hash text NOT NULL,
    idempotency_window_ts timestamp with time zone NOT NULL,
    correlation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notification_events_recipient_type_check CHECK ((recipient_type = ANY (ARRAY['email'::text, 'user_id'::text]))),
    CONSTRAINT notification_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'rejected'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: notification_audit_2026_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit ATTACH PARTITION public.notification_audit_2026_05 FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');


--
-- Name: notification_events_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events ATTACH PARTITION public.notification_events_default DEFAULT;


--
-- Name: dispatch_queue id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispatch_queue ALTER COLUMN id SET DEFAULT nextval('public.dispatch_queue_id_seq'::regclass);


--
-- Name: notification_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit ALTER COLUMN id SET DEFAULT nextval('public.notification_audit_id_seq'::regclass);


--
-- Name: notification_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events ALTER COLUMN id SET DEFAULT nextval('public.notification_events_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: dispatch_queue dispatch_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispatch_queue
    ADD CONSTRAINT dispatch_queue_pkey PRIMARY KEY (id);


--
-- Name: notification_audit notification_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit
    ADD CONSTRAINT notification_audit_pkey PRIMARY KEY (id, created_at);


--
-- Name: notification_audit_2026_05 notification_audit_2026_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit_2026_05
    ADD CONSTRAINT notification_audit_2026_05_pkey PRIMARY KEY (id, created_at);


--
-- Name: notification_events notification_events_correlation_id_idempotency_window_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events
    ADD CONSTRAINT notification_events_correlation_id_idempotency_window_ts_key UNIQUE (correlation_id, idempotency_window_ts);


--
-- Name: notification_events_default notification_events_default_correlation_id_idempotency_wind_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events_default
    ADD CONSTRAINT notification_events_default_correlation_id_idempotency_wind_key UNIQUE (correlation_id, idempotency_window_ts);


--
-- Name: notification_events notification_events_idempotency_hash_idempotency_window_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events
    ADD CONSTRAINT notification_events_idempotency_hash_idempotency_window_ts_key UNIQUE (idempotency_hash, idempotency_window_ts);


--
-- Name: notification_events_default notification_events_default_idempotency_hash_idempotency_wi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events_default
    ADD CONSTRAINT notification_events_default_idempotency_hash_idempotency_wi_key UNIQUE (idempotency_hash, idempotency_window_ts);


--
-- Name: notification_events notification_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events
    ADD CONSTRAINT notification_events_pkey PRIMARY KEY (id, idempotency_window_ts);


--
-- Name: notification_events_default notification_events_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events_default
    ADD CONSTRAINT notification_events_default_pkey PRIMARY KEY (id, idempotency_window_ts);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: idx_dispatch_queue_workable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispatch_queue_workable ON public.dispatch_queue USING btree (next_attempt_at, priority) WHERE (status = 'pending'::text);


--
-- Name: idx_notification_events_correlation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_correlation_id ON ONLY public.notification_events USING btree (correlation_id);


--
-- Name: idx_notification_events_notification_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_notification_type ON ONLY public.notification_events USING btree (notification_type);


--
-- Name: idx_notification_events_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_recipient ON ONLY public.notification_events USING btree (recipient_canonical);


--
-- Name: idx_notification_events_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_status_created_at ON ONLY public.notification_events USING btree (status, created_at);


--
-- Name: notification_audit_correlation_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_correlation_id_idx ON ONLY public.notification_audit USING btree (correlation_id);


--
-- Name: notification_audit_2026_05_correlation_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_correlation_id_idx ON public.notification_audit_2026_05 USING btree (correlation_id);


--
-- Name: notification_audit_metadata_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_metadata_idx ON ONLY public.notification_audit USING gin (metadata);


--
-- Name: notification_audit_2026_05_metadata_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_metadata_idx ON public.notification_audit_2026_05 USING gin (metadata);


--
-- Name: notification_audit_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_payload_idx ON ONLY public.notification_audit USING gin (payload);


--
-- Name: notification_audit_2026_05_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_payload_idx ON public.notification_audit_2026_05 USING gin (payload);


--
-- Name: notification_events_default_correlation_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_events_default_correlation_id_idx ON public.notification_events_default USING btree (correlation_id);


--
-- Name: notification_events_default_notification_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_events_default_notification_type_idx ON public.notification_events_default USING btree (notification_type);


--
-- Name: notification_events_default_recipient_canonical_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_events_default_recipient_canonical_idx ON public.notification_events_default USING btree (recipient_canonical);


--
-- Name: notification_events_default_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_events_default_status_created_at_idx ON public.notification_events_default USING btree (status, created_at);


--
-- Name: notification_audit_2026_05_correlation_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_correlation_id_idx ATTACH PARTITION public.notification_audit_2026_05_correlation_id_idx;


--
-- Name: notification_audit_2026_05_metadata_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_metadata_idx ATTACH PARTITION public.notification_audit_2026_05_metadata_idx;


--
-- Name: notification_audit_2026_05_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_payload_idx ATTACH PARTITION public.notification_audit_2026_05_payload_idx;


--
-- Name: notification_audit_2026_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_pkey ATTACH PARTITION public.notification_audit_2026_05_pkey;


--
-- Name: notification_events_default_correlation_id_idempotency_wind_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_events_correlation_id_idempotency_window_ts_key ATTACH PARTITION public.notification_events_default_correlation_id_idempotency_wind_key;


--
-- Name: notification_events_default_correlation_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_notification_events_correlation_id ATTACH PARTITION public.notification_events_default_correlation_id_idx;


--
-- Name: notification_events_default_idempotency_hash_idempotency_wi_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_events_idempotency_hash_idempotency_window_ts_key ATTACH PARTITION public.notification_events_default_idempotency_hash_idempotency_wi_key;


--
-- Name: notification_events_default_notification_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_notification_events_notification_type ATTACH PARTITION public.notification_events_default_notification_type_idx;


--
-- Name: notification_events_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_events_pkey ATTACH PARTITION public.notification_events_default_pkey;


--
-- Name: notification_events_default_recipient_canonical_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_notification_events_recipient ATTACH PARTITION public.notification_events_default_recipient_canonical_idx;


--
-- Name: notification_events_default_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_notification_events_status_created_at ATTACH PARTITION public.notification_events_default_status_created_at_idx;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260510000003'),
('20260510000002'),
('20260510000001');

