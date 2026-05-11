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
-- Name: admin_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    role character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp(6) without time zone,
    last_sign_in_at timestamp(6) without time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT admin_users_role_chk CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'product'::character varying, 'support'::character varying, 'engineering'::character varying])::text[])))
);


--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_users_id_seq OWNED BY public.admin_users.id;


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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    recipient_canonical text,
    source text DEFAULT 'internal'::text NOT NULL,
    notification_type text,
    CONSTRAINT notification_audit_source_check CHECK ((source = ANY (ARRAY['internal'::text, 'sendgrid_webhook'::text])))
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    recipient_canonical text,
    source text DEFAULT 'internal'::text NOT NULL,
    notification_type text,
    CONSTRAINT notification_audit_source_check CHECK ((source = ANY (ARRAY['internal'::text, 'sendgrid_webhook'::text])))
);


--
-- Name: notification_blacklist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_blacklist (
    id bigint NOT NULL,
    recipient_canonical character varying(320) NOT NULL,
    scope character varying(16) NOT NULL,
    target character varying(64),
    source character varying(32) NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT blacklist_scope_target_chk CHECK (((((scope)::text = 'global'::text) AND (target IS NULL)) OR (((scope)::text = ANY ((ARRAY['type'::character varying, 'channel'::character varying])::text[])) AND (target IS NOT NULL)))),
    CONSTRAINT blacklist_scope_values_chk CHECK (((scope)::text = ANY ((ARRAY['global'::character varying, 'type'::character varying, 'channel'::character varying])::text[]))),
    CONSTRAINT blacklist_source_values_chk CHECK (((source)::text = ANY ((ARRAY['manual'::character varying, 'admin_ui'::character varying, 'hard_bounce'::character varying, 'dropped'::character varying, 'spamreport'::character varying])::text[])))
);


--
-- Name: notification_blacklist_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_blacklist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_blacklist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_blacklist_id_seq OWNED BY public.notification_blacklist.id;


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
-- Name: notification_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_rules (
    id bigint NOT NULL,
    notification_type text NOT NULL,
    channels text[],
    max_per_day integer,
    cooldown_seconds integer,
    digest_window_seconds integer,
    priority text,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT notification_rules_cooldown_positive CHECK (((cooldown_seconds IS NULL) OR (cooldown_seconds > 0))),
    CONSTRAINT notification_rules_digest_positive CHECK (((digest_window_seconds IS NULL) OR (digest_window_seconds > 0))),
    CONSTRAINT notification_rules_max_per_day_positive CHECK (((max_per_day IS NULL) OR (max_per_day > 0))),
    CONSTRAINT notification_rules_priority_check CHECK (((priority IS NULL) OR (priority = ANY (ARRAY['critical'::text, 'standard'::text, 'bulk'::text]))))
);


--
-- Name: notification_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_rules_id_seq OWNED BY public.notification_rules.id;


--
-- Name: pending_digests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pending_digests (
    id bigint NOT NULL,
    notification_type text NOT NULL,
    recipient_canonical text NOT NULL,
    correlation_id uuid NOT NULL,
    event_id bigint NOT NULL,
    payload jsonb NOT NULL,
    rule_snapshot jsonb NOT NULL,
    dispatch_at timestamp with time zone NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    consolidated_into uuid,
    locked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pending_digests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'consolidating'::text, 'consolidated'::text, 'orphaned'::text])))
);


--
-- Name: pending_digests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pending_digests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pending_digests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pending_digests_id_seq OWNED BY public.pending_digests.id;


--
-- Name: rule_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rule_changes (
    id bigint NOT NULL,
    notification_rule_id bigint,
    admin_user_id bigint NOT NULL,
    action character varying NOT NULL,
    before jsonb,
    after jsonb,
    changed_at timestamp(6) without time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT rule_changes_action_chk CHECK (((action)::text = ANY ((ARRAY['created'::character varying, 'updated'::character varying, 'deleted'::character varying])::text[])))
);


--
-- Name: rule_changes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rule_changes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rule_changes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rule_changes_id_seq OWNED BY public.rule_changes.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    id bigint NOT NULL,
    source text DEFAULT 'sendgrid'::text NOT NULL,
    payload jsonb NOT NULL,
    signature text NOT NULL,
    signature_ts text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    locked_at timestamp with time zone,
    processed_at timestamp with time zone,
    failed_reason text,
    attempts integer DEFAULT 0 NOT NULL,
    CONSTRAINT webhook_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'processed'::text, 'failed'::text])))
);


--
-- Name: webhook_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webhook_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webhook_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webhook_events_id_seq OWNED BY public.webhook_events.id;


--
-- Name: notification_audit_2026_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit ATTACH PARTITION public.notification_audit_2026_05 FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');


--
-- Name: notification_events_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events ATTACH PARTITION public.notification_events_default DEFAULT;


--
-- Name: admin_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users ALTER COLUMN id SET DEFAULT nextval('public.admin_users_id_seq'::regclass);


--
-- Name: dispatch_queue id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispatch_queue ALTER COLUMN id SET DEFAULT nextval('public.dispatch_queue_id_seq'::regclass);


--
-- Name: notification_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_audit ALTER COLUMN id SET DEFAULT nextval('public.notification_audit_id_seq'::regclass);


--
-- Name: notification_blacklist id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_blacklist ALTER COLUMN id SET DEFAULT nextval('public.notification_blacklist_id_seq'::regclass);


--
-- Name: notification_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events ALTER COLUMN id SET DEFAULT nextval('public.notification_events_id_seq'::regclass);


--
-- Name: notification_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_rules ALTER COLUMN id SET DEFAULT nextval('public.notification_rules_id_seq'::regclass);


--
-- Name: pending_digests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_digests ALTER COLUMN id SET DEFAULT nextval('public.pending_digests_id_seq'::regclass);


--
-- Name: rule_changes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_changes ALTER COLUMN id SET DEFAULT nextval('public.rule_changes_id_seq'::regclass);


--
-- Name: webhook_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events ALTER COLUMN id SET DEFAULT nextval('public.webhook_events_id_seq'::regclass);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


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
-- Name: notification_blacklist notification_blacklist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_blacklist
    ADD CONSTRAINT notification_blacklist_pkey PRIMARY KEY (id);


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
-- Name: notification_rules notification_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_rules
    ADD CONSTRAINT notification_rules_pkey PRIMARY KEY (id);


--
-- Name: notification_rules notification_rules_type_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_rules
    ADD CONSTRAINT notification_rules_type_unique UNIQUE (notification_type);


--
-- Name: pending_digests pending_digests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_digests
    ADD CONSTRAINT pending_digests_pkey PRIMARY KEY (id);


--
-- Name: rule_changes rule_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_changes
    ADD CONSTRAINT rule_changes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);


--
-- Name: idx_blacklist_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blacklist_lookup ON public.notification_blacklist USING btree (recipient_canonical, scope);


--
-- Name: idx_blacklist_source_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blacklist_source_created ON public.notification_blacklist USING btree (source, created_at DESC);


--
-- Name: idx_blacklist_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_blacklist_unique ON public.notification_blacklist USING btree (recipient_canonical, scope, target) NULLS NOT DISTINCT;


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
-- Name: idx_rule_changes_rule_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rule_changes_rule_time ON public.rule_changes USING btree (notification_rule_id, changed_at DESC);


--
-- Name: idx_rule_changes_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rule_changes_time ON public.rule_changes USING btree (changed_at DESC);


--
-- Name: idx_rule_changes_user_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rule_changes_user_time ON public.rule_changes USING btree (admin_user_id, changed_at DESC);


--
-- Name: index_admin_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_email ON public.admin_users USING btree (email);


--
-- Name: index_admin_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_reset_password_token ON public.admin_users USING btree (reset_password_token);


--
-- Name: index_admin_users_on_unlock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_unlock_token ON public.admin_users USING btree (unlock_token);


--
-- Name: index_rule_changes_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rule_changes_on_admin_user_id ON public.rule_changes USING btree (admin_user_id);


--
-- Name: index_rule_changes_on_notification_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rule_changes_on_notification_rule_id ON public.rule_changes USING btree (notification_rule_id);


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
-- Name: notification_audit_rate_limit_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_rate_limit_idx ON ONLY public.notification_audit USING btree (notification_type, recipient_canonical, created_at) WHERE ((notification_type IS NOT NULL) AND (recipient_canonical IS NOT NULL));


--
-- Name: notification_audit_2026_05_notification_type_recipient_cano_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_notification_type_recipient_cano_idx ON public.notification_audit_2026_05 USING btree (notification_type, recipient_canonical, created_at) WHERE ((notification_type IS NOT NULL) AND (recipient_canonical IS NOT NULL));


--
-- Name: notification_audit_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_payload_idx ON ONLY public.notification_audit USING gin (payload);


--
-- Name: notification_audit_2026_05_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_payload_idx ON public.notification_audit_2026_05 USING gin (payload);


--
-- Name: notification_audit_recipient_canonical_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_recipient_canonical_idx ON ONLY public.notification_audit USING btree (recipient_canonical) WHERE (recipient_canonical IS NOT NULL);


--
-- Name: notification_audit_2026_05_recipient_canonical_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_recipient_canonical_idx ON public.notification_audit_2026_05 USING btree (recipient_canonical) WHERE (recipient_canonical IS NOT NULL);


--
-- Name: notification_audit_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_status_created_at_idx ON ONLY public.notification_audit USING btree (status, created_at);


--
-- Name: notification_audit_2026_05_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_audit_2026_05_status_created_at_idx ON public.notification_audit_2026_05 USING btree (status, created_at);


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
-- Name: notification_rules_enabled_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_rules_enabled_idx ON public.notification_rules USING btree (notification_type) WHERE (enabled = true);


--
-- Name: pending_digests_dispatch_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pending_digests_dispatch_at_idx ON public.pending_digests USING btree (dispatch_at) WHERE (status = 'pending'::text);


--
-- Name: pending_digests_group_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pending_digests_group_idx ON public.pending_digests USING btree (notification_type, recipient_canonical, status);


--
-- Name: webhook_events_pending_processing_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_events_pending_processing_idx ON public.webhook_events USING btree (status, received_at) WHERE (status = ANY (ARRAY['pending'::text, 'processing'::text]));


--
-- Name: notification_audit_2026_05_correlation_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_correlation_id_idx ATTACH PARTITION public.notification_audit_2026_05_correlation_id_idx;


--
-- Name: notification_audit_2026_05_metadata_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_metadata_idx ATTACH PARTITION public.notification_audit_2026_05_metadata_idx;


--
-- Name: notification_audit_2026_05_notification_type_recipient_cano_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_rate_limit_idx ATTACH PARTITION public.notification_audit_2026_05_notification_type_recipient_cano_idx;


--
-- Name: notification_audit_2026_05_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_payload_idx ATTACH PARTITION public.notification_audit_2026_05_payload_idx;


--
-- Name: notification_audit_2026_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_pkey ATTACH PARTITION public.notification_audit_2026_05_pkey;


--
-- Name: notification_audit_2026_05_recipient_canonical_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_recipient_canonical_idx ATTACH PARTITION public.notification_audit_2026_05_recipient_canonical_idx;


--
-- Name: notification_audit_2026_05_status_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.notification_audit_status_created_at_idx ATTACH PARTITION public.notification_audit_2026_05_status_created_at_idx;


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
-- Name: rule_changes fk_rails_73c5ceade4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_changes
    ADD CONSTRAINT fk_rails_73c5ceade4 FOREIGN KEY (notification_rule_id) REFERENCES public.notification_rules(id) ON DELETE SET NULL;


--
-- Name: rule_changes fk_rails_e9c3e401cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_changes
    ADD CONSTRAINT fk_rails_e9c3e401cc FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260512170000'),
('20260512000003'),
('20260512000002'),
('20260512000001'),
('20260511185532'),
('20260511185531'),
('20260511185530'),
('20260511000002'),
('20260511000001'),
('20260510000003'),
('20260510000002'),
('20260510000001');

