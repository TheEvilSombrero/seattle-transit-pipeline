\restrict dbmate

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg13+2)
-- Dumped by pg_dump version 18.3 (Postgres.app)

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

--
-- Name: gtfs_static; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA gtfs_static;


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agency; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.agency (
    agency_id text NOT NULL,
    agency_name text NOT NULL,
    agency_url text NOT NULL,
    agency_timezone text NOT NULL,
    agency_lang text,
    agency_phone text,
    agency_fare_url text,
    agency_email text
);


--
-- Name: calendar; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.calendar (
    service_id text NOT NULL,
    monday boolean NOT NULL,
    tuesday boolean NOT NULL,
    wednesday boolean NOT NULL,
    thursday boolean NOT NULL,
    friday boolean NOT NULL,
    saturday boolean NOT NULL,
    sunday boolean NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL
);


--
-- Name: calendar_dates; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.calendar_dates (
    service_id text NOT NULL,
    date date NOT NULL,
    exception_type smallint NOT NULL
);


--
-- Name: routes; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.routes (
    agency_id text NOT NULL,
    route_id text NOT NULL,
    route_short_name text,
    route_long_name text,
    route_type integer NOT NULL,
    route_desc text,
    route_url text,
    route_color text,
    route_text_color text
);


--
-- Name: shapes; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.shapes (
    shape_id text NOT NULL,
    shape_pt_sequence integer NOT NULL,
    shape_pt_lat double precision NOT NULL,
    shape_pt_lon double precision NOT NULL,
    shape_dist_traveled double precision
);


--
-- Name: stop_times; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.stop_times (
    trip_id text NOT NULL,
    stop_id text NOT NULL,
    arrival_time interval,
    departure_time interval,
    timepoint smallint,
    stop_sequence integer NOT NULL,
    shape_dist_traveled double precision,
    departure_buffer text
);


--
-- Name: stops; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.stops (
    stop_id text NOT NULL,
    stop_name text NOT NULL,
    stop_lat double precision NOT NULL,
    stop_lon double precision NOT NULL,
    stop_code text,
    stop_desc text,
    zone_id text,
    stop_url text,
    location_type smallint,
    parent_station text,
    wheelchair_boarding smallint,
    stop_timezone text,
    platform_code text,
    tts_stop_name text
);


--
-- Name: trips; Type: TABLE; Schema: gtfs_static; Owner: -
--

CREATE TABLE gtfs_static.trips (
    route_id text NOT NULL,
    trip_id text NOT NULL,
    service_id text NOT NULL,
    trip_short_name text,
    trip_headsign text,
    direction_id smallint,
    block_id text,
    shape_id text,
    wheelchair_accessible smallint,
    drt_advance_book_min text,
    bikes_allowed smallint,
    peak_offpeak text,
    boarding_type text
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: agency agency_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.agency
    ADD CONSTRAINT agency_pkey PRIMARY KEY (agency_id);


--
-- Name: calendar_dates calendar_dates_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.calendar_dates
    ADD CONSTRAINT calendar_dates_pkey PRIMARY KEY (service_id, date);


--
-- Name: calendar calendar_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.calendar
    ADD CONSTRAINT calendar_pkey PRIMARY KEY (service_id);


--
-- Name: routes routes_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.routes
    ADD CONSTRAINT routes_pkey PRIMARY KEY (route_id);


--
-- Name: shapes shapes_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.shapes
    ADD CONSTRAINT shapes_pkey PRIMARY KEY (shape_id, shape_pt_sequence);


--
-- Name: stop_times stop_times_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.stop_times
    ADD CONSTRAINT stop_times_pkey PRIMARY KEY (trip_id, stop_sequence);


--
-- Name: stops stops_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.stops
    ADD CONSTRAINT stops_pkey PRIMARY KEY (stop_id);


--
-- Name: trips trips_pkey; Type: CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.trips
    ADD CONSTRAINT trips_pkey PRIMARY KEY (trip_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: routes routes_agency_id_fkey; Type: FK CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.routes
    ADD CONSTRAINT routes_agency_id_fkey FOREIGN KEY (agency_id) REFERENCES gtfs_static.agency(agency_id);


--
-- Name: stop_times stop_times_stop_id_fkey; Type: FK CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.stop_times
    ADD CONSTRAINT stop_times_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES gtfs_static.stops(stop_id);


--
-- Name: stop_times stop_times_trip_id_fkey; Type: FK CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.stop_times
    ADD CONSTRAINT stop_times_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES gtfs_static.trips(trip_id);


--
-- Name: stops stops_parent_station_fkey; Type: FK CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.stops
    ADD CONSTRAINT stops_parent_station_fkey FOREIGN KEY (parent_station) REFERENCES gtfs_static.stops(stop_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: trips trips_route_id_fkey; Type: FK CONSTRAINT; Schema: gtfs_static; Owner: -
--

ALTER TABLE ONLY gtfs_static.trips
    ADD CONSTRAINT trips_route_id_fkey FOREIGN KEY (route_id) REFERENCES gtfs_static.routes(route_id);


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20260528013752'),
    ('20260528014650'),
    ('20260528015843'),
    ('20260528021201'),
    ('20260528023134'),
    ('20260529020222'),
    ('20260529023128'),
    ('20260529031546'),
    ('20260529033826');
