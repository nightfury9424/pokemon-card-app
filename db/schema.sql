--
-- PostgreSQL database dump
--

-- Dumped from database version 14.17 (Homebrew)
-- Dumped by pg_dump version 14.17 (Homebrew)

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
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    asset_id character varying(50) NOT NULL,
    user_id character varying(50) NOT NULL,
    card_id character varying(50) NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    purchase_price integer,
    card_status character varying(20) NOT NULL,
    grading_company character varying(20),
    grade_value character varying(20),
    cert_number character varying(100),
    memo text,
    purchased_at date,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT assets_purchase_price_check CHECK ((purchase_price >= 0)),
    CONSTRAINT assets_quantity_check CHECK ((quantity > 0))
);


--
-- Name: cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cards (
    card_id character varying(50) NOT NULL,
    product_id character varying(50) NOT NULL,
    official_card_code character varying(100),
    name character varying(200) NOT NULL,
    collection_number character varying(50),
    rarity_code character varying(50),
    language character varying(10) NOT NULL,
    super_type character varying(30) NOT NULL,
    sub_type character varying(50),
    illustrator character varying(100),
    image_url character varying(500),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    local_image_path character varying(500),
    image_feature_vector public.vector(768),
    en_scrydex_ref character varying(100),
    jp_scrydex_ref character varying(200),
    card_type character varying(30),
    ko_phash character varying(16),
    jp_phash character varying(16),
    en_phash character varying(16)
);


--
-- Name: chat_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_messages (
    chat_message_id character varying(50) NOT NULL,
    chat_room_id character varying(50) NOT NULL,
    sender_user_id character varying(50) NOT NULL,
    message text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    is_read boolean DEFAULT false NOT NULL
);


--
-- Name: chat_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_rooms (
    chat_room_id character varying(50) NOT NULL,
    sale_listing_id character varying(50) NOT NULL,
    seller_user_id character varying(50) NOT NULL,
    buyer_user_id character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    last_message text,
    last_message_at timestamp without time zone
);


--
-- Name: grading_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grading_results (
    result_id character varying(50) NOT NULL,
    user_id character varying(50) NOT NULL,
    card_id character varying(50),
    centering_score numeric(3,1) NOT NULL,
    corner_score numeric(3,1) NOT NULL,
    surface_score numeric(3,1) NOT NULL,
    whitening_score numeric(3,1) NOT NULL,
    total_score numeric(3,1) NOT NULL,
    heavy_whitening boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: jp_set_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jp_set_mappings (
    ptcg_set_id character varying(50) NOT NULL,
    jp_set_id character varying(50) NOT NULL,
    jp_set_name character varying(200)
);


--
-- Name: post_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_interests (
    interest_id character varying(50) NOT NULL,
    user_id character varying(50) NOT NULL,
    trade_id character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: price_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_snapshots (
    price_snapshot_id character varying(50) NOT NULL,
    card_id character varying(50) NOT NULL,
    source character varying(20) NOT NULL,
    source_item_id character varying(100),
    source_url character varying(500),
    price integer NOT NULL,
    currency character varying(10) DEFAULT 'KRW'::character varying NOT NULL,
    card_status character varying(50) NOT NULL,
    grading_company character varying(20),
    grade_value character varying(20),
    cert_number character varying(100),
    traded_at timestamp without time zone NOT NULL,
    collected_at timestamp without time zone DEFAULT now() NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT price_snapshots_price_check CHECK ((price > 0))
);


--
-- Name: price_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_summaries (
    price_summary_id character varying(50) NOT NULL,
    card_id character varying(50) NOT NULL,
    card_status character varying(20) NOT NULL,
    grading_company character varying(20),
    grade_value character varying(20),
    period character varying(10) NOT NULL,
    median_price integer,
    avg_price integer,
    min_price integer,
    max_price integer,
    trade_count integer DEFAULT 0 NOT NULL,
    calculated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    product_id character varying(50) NOT NULL,
    name character varying(200) NOT NULL,
    series_name character varying(200),
    product_type character varying(30),
    language character varying(10) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    image_url character varying(500)
);


--
-- Name: ptcg_set_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ptcg_set_mappings (
    product_id character varying(50) NOT NULL,
    ptcg_set_id character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: sale_listings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_listings (
    sale_listing_id character varying(50) NOT NULL,
    asset_id character varying(50) NOT NULL,
    sale_quantity integer DEFAULT 1 NOT NULL,
    desired_price integer,
    memo text,
    is_public boolean DEFAULT false NOT NULL,
    sale_status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT sale_listings_desired_price_check CHECK ((desired_price >= 0)),
    CONSTRAINT sale_listings_sale_quantity_check CHECK ((sale_quantity > 0))
);


--
-- Name: trade_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_posts (
    trade_id character varying(50) NOT NULL,
    seller_id character varying(50) NOT NULL,
    card_id character varying(50) NOT NULL,
    title character varying(200) NOT NULL,
    description text,
    price integer,
    card_status character varying(20) DEFAULT 'RAW'::character varying NOT NULL,
    grading_company character varying(20),
    grade_value character varying(20),
    status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    view_count integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    image_url text
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id character varying(50) NOT NULL,
    kakao_id character varying(100) NOT NULL,
    nickname character varying(50) NOT NULL,
    profile_image_url character varying(500),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    is_portfolio_public boolean DEFAULT false NOT NULL
);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (asset_id);


--
-- Name: cards cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_pkey PRIMARY KEY (card_id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (chat_message_id);


--
-- Name: chat_rooms chat_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT chat_rooms_pkey PRIMARY KEY (chat_room_id);


--
-- Name: grading_results grading_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_results
    ADD CONSTRAINT grading_results_pkey PRIMARY KEY (result_id);


--
-- Name: jp_set_mappings jp_set_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jp_set_mappings
    ADD CONSTRAINT jp_set_mappings_pkey PRIMARY KEY (ptcg_set_id);


--
-- Name: post_interests post_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_interests
    ADD CONSTRAINT post_interests_pkey PRIMARY KEY (interest_id);


--
-- Name: price_snapshots price_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_snapshots
    ADD CONSTRAINT price_snapshots_pkey PRIMARY KEY (price_snapshot_id);


--
-- Name: price_summaries price_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_summaries
    ADD CONSTRAINT price_summaries_pkey PRIMARY KEY (price_summary_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: ptcg_set_mappings ptcg_set_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ptcg_set_mappings
    ADD CONSTRAINT ptcg_set_mappings_pkey PRIMARY KEY (product_id);


--
-- Name: sale_listings sale_listings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_listings
    ADD CONSTRAINT sale_listings_pkey PRIMARY KEY (sale_listing_id);


--
-- Name: trade_posts trade_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_posts
    ADD CONSTRAINT trade_posts_pkey PRIMARY KEY (trade_id);


--
-- Name: chat_rooms uq_chat_room; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT uq_chat_room UNIQUE (sale_listing_id, buyer_user_id);


--
-- Name: post_interests uq_user_trade; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_interests
    ADD CONSTRAINT uq_user_trade UNIQUE (user_id, trade_id);


--
-- Name: users users_kakao_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_kakao_id_key UNIQUE (kakao_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: idx_assets_card_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_card_id ON public.assets USING btree (card_id);


--
-- Name: idx_assets_card_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_card_status ON public.assets USING btree (card_status);


--
-- Name: idx_assets_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_user_id ON public.assets USING btree (user_id);


--
-- Name: idx_cards_collection_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_collection_number ON public.cards USING btree (collection_number);


--
-- Name: idx_cards_image_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_image_vector ON public.cards USING hnsw (image_feature_vector public.vector_cosine_ops);


--
-- Name: idx_cards_language; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_language ON public.cards USING btree (language);


--
-- Name: idx_cards_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_name ON public.cards USING btree (name);


--
-- Name: idx_cards_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_product_id ON public.cards USING btree (product_id);


--
-- Name: idx_cards_sub_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_sub_type ON public.cards USING btree (sub_type);


--
-- Name: idx_cards_super_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cards_super_type ON public.cards USING btree (super_type);


--
-- Name: idx_chat_messages_chat_room_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_messages_chat_room_id ON public.chat_messages USING btree (chat_room_id);


--
-- Name: idx_chat_messages_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_messages_created_at ON public.chat_messages USING btree (created_at DESC);


--
-- Name: idx_chat_rooms_buyer_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_rooms_buyer_user_id ON public.chat_rooms USING btree (buyer_user_id);


--
-- Name: idx_chat_rooms_seller_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_rooms_seller_user_id ON public.chat_rooms USING btree (seller_user_id);


--
-- Name: idx_grading_results_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grading_results_user_id ON public.grading_results USING btree (user_id);


--
-- Name: idx_price_snapshots_card_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_snapshots_card_id ON public.price_snapshots USING btree (card_id);


--
-- Name: idx_price_snapshots_card_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_snapshots_card_status ON public.price_snapshots USING btree (card_status);


--
-- Name: idx_price_snapshots_grade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_snapshots_grade ON public.price_snapshots USING btree (grading_company, grade_value);


--
-- Name: idx_price_snapshots_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_snapshots_source ON public.price_snapshots USING btree (source);


--
-- Name: idx_price_snapshots_traded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_snapshots_traded_at ON public.price_snapshots USING btree (traded_at DESC);


--
-- Name: idx_products_language; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_language ON public.products USING btree (language);


--
-- Name: idx_products_series_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_series_name ON public.products USING btree (series_name);


--
-- Name: idx_sale_listings_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sale_listings_asset_id ON public.sale_listings USING btree (asset_id);


--
-- Name: idx_sale_listings_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sale_listings_is_public ON public.sale_listings USING btree (is_public);


--
-- Name: idx_sale_listings_sale_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sale_listings_sale_status ON public.sale_listings USING btree (sale_status);


--
-- Name: uq_cards_product_collection; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cards_product_collection ON public.cards USING btree (product_id, collection_number);


--
-- Name: uq_price_summaries_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_price_summaries_key ON public.price_summaries USING btree (card_id, card_status, grading_company, grade_value, period);


--
-- PostgreSQL database dump complete
--

