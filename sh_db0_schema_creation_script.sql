--(c) MIT License 2021 ashd97

-- We will try to use Optimistic concurrency control 
-- https://en.wikipedia.org/wiki/Optimistic_concurrency_control

-- TODO
-- CREATE FUNCTION files.add_worker_log ..
-- 

-- CREATE DATABASE sh_db0_dev;

-- echo "alter database sh_db0_dev rename to delete_me; DROP database delete_me;" | psql -tAx -U postgres

-- echo 'CREATE DATABASE sh_db0_dev;' | psql -tAx -U postgres

-- cat sh_db0_schema_creation_script.sql | psql -tAx -U postgres -d sh_db0_dev


DROP SCHEMA IF EXISTS files CASCADE;

CREATE SCHEMA files;

ALTER SCHEMA files OWNER TO postgres;

SET search_path TO files;

--
-- For playing, debugging and analytics
--
CREATE USER debugger WITH PASSWORD 'debugger';
GRANT CONNECT on DATABASE sh_db0_dev TO debugger;

--
-- For shworker only
--
CREATE USER shworker WITH PASSWORD 'shworker';
GRANT CONNECT on DATABASE sh_db0_dev TO shworker;

GRANT USAGE on SCHEMA files TO debugger;

GRANT USAGE on SCHEMA files TO shworker;

SET search_path TO files, public;

--
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;
--


--
-- Main table for SMILES processing
--
DROP TABLE IF EXISTS files.files CASCADE;
-- TRUNCATE files.files;
CREATE TABLE files.files (
    -- id integer NOT NULL,
    id SERIAL PRIMARY KEY,
    smiles character varying(255),
    num_conformers integer,
    docking_score real,
    created_ts timestamp with time zone DEFAULT now() NOT NULL, -- time of record creation => status = 0
    start_ts timestamp with time zone, -- ts of when was shworker launched
    stop_ts timestamp with time zone, -- ts of when was shworker finished
    -- protected boolean DEFAULT false,
    status integer DEFAULT 0, -- unprocessed record, -1 is indicating that job is done, if > 0 ( its worker_id) then in progress
    last_worker_id integer DEFAULT NULL, -- will get it from status when id will be in process
    -- problemstatus DEFAULT 'NO_PROBLEM'::character varying
    priority integer DEFAULT 1
);

-- ALTER TABLE files.files ADD COLUMN last_worker_id integer DEFAULT NULL;

-- ALTER TABLE files.files ADD COLUMN priority integer DEFAULT 1;

--
-- ALTER TABLE ONLY files.files
--    ADD CONSTRAINT _records_id_unique UNIQUE (id);
    
CREATE INDEX _id_idx ON files.files USING btree (id);
    
CREATE INDEX _smiles_idx ON files.files USING btree (smiles);

CREATE INDEX _starts_idx ON files.files USING btree (start_ts);

CREATE INDEX _createdts_idx ON files.files USING btree (created_ts);

CREATE INDEX _stops_idx ON files.files USING btree (stop_ts);

CREATE INDEX _status_idx ON files.files USING btree (status);

CREATE INDEX _last_worker_id_idx ON files.files USING btree (last_worker_id);
--


GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA files TO debugger;


GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA files TO debugger;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA files TO shworker;

--
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE files.files TO debugger;

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE files.files TO shworker;
--


-- Some sample data just for better understanding
-- 
-- INSERT INTO files.files (id, smiles, num_conformers, docking_score, start_ts, stop_ts, status) VALUES (15, 'CC1CC(OC(=O)CN2CCCC2=O)CC(C)(C)C1', 35, -3.2115562, '2021-02-27 14:07:36.015431-08', '2021-02-27 14:07:36.01898-08', -1);
-- INSERT INTO files.files (id, smiles, num_conformers, docking_score, start_ts, stop_ts, status) VALUES (19, 'CN1C(=O)C(O)N=C(c2ccccc2)c2cc(Cl)ccc21', 6, -3.4170113, '2021-02-27 14:10:38.10848-08', '2021-02-27 14:10:38.112477-08', -1);
--

    -- 
    -- --
    -- -- Trigger will monitor something more..
    -- --
    --  DROP TRIGGER log_last_worker_id_trigger ON files.files;
    --  DROP FUNCTION log_last_worker_id();
    --  
    --  CREATE FUNCTION log_last_worker_id() RETURNS trigger
    --      LANGUAGE plpgsql
    --      AS $$
    --  BEGIN
    --  --
    -- 
    --  
    --    RETURN NEW;
    --  END;
    --  $$;
    --  -- trigger is working on next UPDATE
    --  CREATE TRIGGER log_last_worker_id_trigger
    --      AFTER UPDATE ON files.files
    --      EXECUTE PROCEDURE log_last_worker_id();
    --  -- --
    -- 


--
-- Declaration of how shworker will receiving unprocessed records:
-- shworker is sending worker_id using the function
-- all transactions will be processed as if they were all running sequentially
--
DROP FUNCTION IF EXISTS files.get_unprocessed_entry(integer);

CREATE FUNCTION files.get_unprocessed_entry(integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE 
      unprocessed_id INTEGER;
      _worker_id  ALIAS FOR $1;
    BEGIN
    -- Prepare unprocessed_id (or check if there is something to update at all)
        SELECT id 
        into unprocessed_id
        FROM files.files 
        WHERE status = 0 
            AND start_ts is NULL 
        ORDER BY id ASC limit 1;
    --
        IF ( SELECT current_setting('transaction_isolation') ) <> 'serializable'
        THEN
            RETURN -1; -- wrong isolation level
        ELSIF ( unprocessed_id IS NULL) 
            THEN
                RETURN -2; -- no records to update
        ELSE
        UPDATE files.files 
        SET status = _worker_id, last_worker_id = _worker_id, start_ts = NOW () 
            WHERE id = unprocessed_id;
        --
        UPDATE files.live_workers
        SET  start_ts = NOW ()
            WHERE worker_id = _worker_id;
        RETURN unprocessed_id; -- one updated record
        END IF;
    END;
  $_$;

ALTER FUNCTION files.get_unprocessed_entry(integer) OWNER TO postgres;

-- -- Call sample
-- BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; 
-- SELECT files.get_unprocessed_entry (worker_id); END;
-- --








--
-- Declaration of how shworker will receiving unprocessed records:
-- shworker is sending worker_id using the function
-- all transactions will be processed as if they were all running sequentially
--
DROP FUNCTION IF EXISTS files.get_unprocessed_entry_by_priority(integer);

CREATE FUNCTION files.get_unprocessed_entry_by_priority(integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE 
      unprocessed_id INTEGER;
      _worker_id  ALIAS FOR $1;
    BEGIN
            -- Prepare unprocessed_id (or check if there is something to update at all)
                SELECT MIN(id) 
                INTO unprocessed_id
                FROM files.files 
                WHERE status = 0 
                    AND start_ts is NULL
                GROUP BY priority, created_ts
                ORDER BY priority DESC
                LIMIT 1;
                --
                IF ( SELECT current_setting('transaction_isolation') ) <> 'serializable'
                THEN
                    RETURN -1; -- wrong isolation level
                ELSIF ( unprocessed_id IS NULL) 
                    THEN
                        RETURN -2; -- no records to update
                ELSE
                UPDATE files.files 
                SET status = _worker_id, last_worker_id = _worker_id, start_ts = NOW () 
                    WHERE id = unprocessed_id;
                --
                UPDATE files.live_workers
                SET  start_ts = NOW ()
                    WHERE worker_id = _worker_id;
                RETURN unprocessed_id; -- one updated record
                END IF;
                --
                EXCEPTION
                    WHEN SQLSTATE '40001' THEN
		    	RETURN -3;
                        -- RAISE NOTICE 'serialization_failure (Class 40 – Transaction Rollback)'; 
                        -- nothing to do on 'could not serialize access due to concurrent update 
                        -- just continue the cycle to retry UPDATE 
                        -- https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING
                        -- https://www.postgresql.org/docs/9.6/errcodes-appendix.html
    END;
  $_$;

ALTER FUNCTION files.get_unprocessed_entry_by_priority(integer) OWNER TO postgres;

-- -- Call sample
-- BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; 
-- SELECT files.get_unprocessed_entry (worker_id); END;
-- --







-- --
-- Clean all records with id of this worker (past fails?)
-- --

DROP FUNCTION IF EXISTS files.clean_records_for_worker(integer);

CREATE FUNCTION files.clean_records_for_worker(integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
      _worker_id ALIAS FOR $1;
      -- _done  BOOLEAN;
    BEGIN
        IF ( SELECT current_setting('transaction_isolation') ) <> 'serializable'
        THEN
            RETURN -1;
        ELSE
            UPDATE files.files
			SET status = 0, start_ts = NULL
			WHERE id IN (
				SELECT id
				FROM files.files
					WHERE status = _worker_id
					AND start_ts is NOT NULL
			);
			RETURN 1;
        END IF;
    END;
  $_$;

ALTER FUNCTION files.clean_records_for_worker(integer) OWNER TO postgres;
-- --


-- --
-- Function removes entry using specific files.id
-- (better never delete records. We will have difficulties with autovacuum setup)
-- --
DROP FUNCTION IF EXISTS files.remove_entry(integer);

CREATE FUNCTION files.remove_entry(integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
      _file_id ALIAS FOR $1;
      -- _done  BOOLEAN;
    BEGIN
        IF ( SELECT current_setting('transaction_isolation') ) <> 'serializable'
        THEN
            RETURN -1;
        ELSE
            DELETE FROM files.files
            WHERE id = _file_id;
			RETURN 1;
            -- RETURN FOUND;
        END IF;
    END;
  $_$;

ALTER FUNCTION files.remove_entry(integer) OWNER TO postgres;
-- --


-- -- Analytics VIEWs
-- -- Just write SELECT * from files.processing_queue;
CREATE VIEW files.processing_queue AS
    SELECT id
    FROM files.files
        WHERE status > 0;
-- --
        
GRANT SELECT ON TABLE files.processing_queue TO debugger;
GRANT SELECT ON TABLE files.processing_queue TO shworker;


-- --
CREATE VIEW files.number_of_processed_records AS
SELECT count(*) FROM (
    SELECT id
        FROM files.files
        WHERE status IN ('-1')
        ) as number_of_records;
-- --

GRANT SELECT ON TABLE files.number_of_processed_records TO debugger;
GRANT SELECT ON TABLE files.number_of_processed_records TO shworker;


-- --
CREATE VIEW files.number_of_unprocessed_records AS
SELECT count(*) as count FROM (
    SELECT id
        FROM files.files
        WHERE status = 0
        ) as number_of_records;
-- --


GRANT SELECT ON TABLE files.number_of_unprocessed_records TO debugger;
GRANT SELECT ON TABLE files.number_of_unprocessed_records TO shworker;

        
-- --
-- SELECT * from files.best LIMIT 10;
CREATE VIEW files.best AS
        SELECT id
        , smiles
        , docking_score
        , created_ts
        , stop_ts - start_ts as delay
        FROM files.files
        WHERE docking_score < 0 
        ORDER BY docking_score ASC;
-- --
        
GRANT SELECT ON TABLE files.best TO debugger;
GRANT SELECT ON TABLE files.best TO shworker;


-- --

DROP VIEW IF EXISTS lock_monitor;

CREATE VIEW lock_monitor AS(
SELECT
  COALESCE(blockingl.relation::regclass::text,blockingl.locktype) as locked_item,
  now() - blockeda.query_start AS waiting_duration, blockeda.pid AS blocked_pid,
  blockeda.query as blocked_query, blockedl.mode as blocked_mode,
  blockinga.pid AS blocking_pid, blockinga.query as blocking_query,
  blockingl.mode as blocking_mode
FROM pg_catalog.pg_locks blockedl
JOIN pg_stat_activity blockeda ON blockedl.pid = blockeda.pid
JOIN pg_catalog.pg_locks blockingl ON(
  ( (blockingl.transactionid=blockedl.transactionid) OR
  (blockingl.relation=blockedl.relation AND blockingl.locktype=blockedl.locktype)
  ) AND blockedl.pid != blockingl.pid)
JOIN pg_stat_activity blockinga ON blockingl.pid = blockinga.pid
  AND blockinga.datid = blockeda.datid
WHERE NOT blockedl.granted
AND blockinga.datname = current_database()
);
SELECT * from lock_monitor;

-- --

-- --
-- Main list of workers
-- TRUNCATE files.live_workers;
-- --
DROP TABLE IF EXISTS files.live_workers CASCADE;

CREATE TABLE files.live_workers (
    worker_id SERIAL PRIMARY KEY,
    node_ip character varying(255) DEFAULT NULL,
    created_ts timestamp with time zone DEFAULT now(), -- time of record creation => status = 0
    start_ts timestamp with time zone DEFAULT NULL, -- ts of when was shworker started last time
    stop_ts timestamp with time zone DEFAULT NULL -- ts of when was shworker finished last time
    -- protected boolean DEFAULT false,
    -- status BOOLEAN DEFAULT TRUE, -- is it working on something or not
    -- number_of_processed_records integer DEFAULT 0
    -- problemstatus DEFAULT 'NO_PROBLEM'::character varying
    -- worker_log_path character varying
);

--
CREATE INDEX _worker_id_idx ON files.live_workers USING btree (worker_id);
    
CREATE INDEX _w_createdts_idx ON files.live_workers USING btree (created_ts);

CREATE INDEX _w_startts_idx ON files.live_workers USING btree (created_ts);

CREATE INDEX _w_stopts_idx ON files.live_workers USING btree (stop_ts);

-- CREATE INDEX _status_idx ON files.live_workers USING btree (status);

CREATE INDEX _node_ip_idx ON files.live_workers USING btree (node_ip);
--

--
GRANT SELECT,UPDATE ON TABLE files.live_workers TO shworker;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE files.live_workers TO debugger;
--


-- --
-- Function will return worker_id for a new request.
-- DROP FUNCTION files.add_worker;
-- --
DROP FUNCTION IF EXISTS files.add_worker();

CREATE FUNCTION files.add_worker() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
      active_node_ip character varying(255);
      generated_worker_id INTEGER;
    BEGIN
    -- we should log ip of a node with worker/workers for debugging
        SELECT 
            CASE 
                WHEN client_addr IS NOT NULL THEN client_addr
                WHEN client_addr IS NULL THEN '127.0.0.1'
            END as client_addr
            into active_node_ip
        FROM pg_stat_activity 
        WHERE usename = 'shworker' -- should be shworker, login from pipeline
            AND state = 'active' 
            AND query_start > ( now() - 1 * INTERVAL '1 minute' )
            ORDER BY query_start DESC 
            LIMIT 1;
    --
        IF ( SELECT current_setting('transaction_isolation') ) <> 'serializable'
        THEN
            RETURN -1;
        ELSE
                --
                 INSERT INTO files.live_workers ( node_ip, start_ts ) 
                 VALUES ( active_node_ip, NOW() );
                -- 
                SELECT worker_id
                    into generated_worker_id
                FROM files.live_workers
                    -- WHERE node_ip = active_node_ip
                ORDER BY start_ts DESC
                LIMIT 1; 
                --
            RETURN generated_worker_id;
        END IF;
    END;
  $_$;

ALTER FUNCTION files.add_worker() OWNER TO postgres;

-- -- Call sample
-- BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; 
-- select files.add_worker(); END;
-- select * from files.live_workers;
-- --




-- --
-- Fuction is updating current status of worker_ID.
-- Its receiving end_status + docking_score + num_conformers + id + worker_id
-- Currently set_worker_result python will call on Final Stage
-- --
DROP FUNCTION files.set_worker_result;
-- --
CREATE FUNCTION files.set_worker_result( integer, real, integer, integer, integer ) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
        _end_status ALIAS FOR $1;
        _docking_score ALIAS FOR $2;
        _num_conformers ALIAS FOR $3;
        _record_id ALIAS FOR $4;
        _worker_id ALIAS FOR $5;
    BEGIN
        IF ( _end_status IS  NULL 
                OR _docking_score IS  NULL 
                OR _num_conformers IS  NULL 
                OR _record_id IS  NULL 
                OR _worker_id IS  NULL)
        THEN
            RETURN -1;
        ELSE
                 UPDATE files.files
                    SET status = _end_status
                            , stop_ts = NOW ()
                            ,  docking_score = _docking_score
                            , num_conformers = _num_conformers
                            , last_worker_id = _worker_id
                    WHERE id = _record_id;
                    --
                 UPDATE files.live_workers
                    SET  stop_ts = NOW ()
                    WHERE worker_id = _worker_id;
            RETURN 1;
        END IF;
    END;
  $_$;

ALTER FUNCTION files.set_worker_result( integer, real, integer, integer, integer ) OWNER TO postgres;


-- -- Call sample
-- SELECT files.set_worker_result ( '-1', '-3.4170113', '6', '19', 1); 
-- -- Data Sample
-- INSERT INTO files.files (id, smiles, num_conformers, docking_score, start_ts, stop_ts, status) VALUES (19, 'CN1C(=O)C(O)N=C(c2ccccc2)c2cc(Cl)ccc21', 6, -3.4170113, '2021-02-27 14:10:38.10848-08', '2021-02-27 14:10:38.112477-08', -1);
-- 


    
    -- Get Active Workers. 
    -- Info is not always accurate because of average dock time.
    -- Warning, intercepted addresses are not always accurate.
CREATE OR REPLACE VIEW active_workers AS 
    WITH avg_dock_time AS (
        SELECT 
            last_worker_id
            , AVG( stop_ts - start_ts ) as avg_dock_time
        FROM files.files 
        WHERE docking_score IS NOT NULL
        GROUP BY last_worker_id
    )
     , done_by_workers AS (
        SELECT 
            COUNT(id) as finished_smiles
            , last_worker_id 
        FROM files.files 
        GROUP BY last_worker_id
     )
    SELECT DISTINCT
        live_workers.worker_id
        , live_workers.node_ip as historical_node_ip
        , live_workers.created_ts
        , live_workers.start_ts
        , avg_dock_time.avg_dock_time
        , done_by_workers.finished_smiles
    FROM files.live_workers, files.files, avg_dock_time, done_by_workers
    WHERE 
        live_workers.worker_id = avg_dock_time.last_worker_id
        AND live_workers.worker_id = done_by_workers.last_worker_id
        AND live_workers.start_ts - live_workers.stop_ts > interval '1 second' 
        AND live_workers.start_ts > ( NOW () - 
            4 * ( SELECT MAX (avg_dock_time) FROM avg_dock_time ) 
        )
         AND live_workers.worker_id IN (
             SELECT status from files.files WHERE status > 0
        )
    ORDER BY node_ip, worker_id, created_ts;
    --     SELECT * FROM active_workers;  
    --     SELECT count (*) FROM active_workers;   
    --     SELECT AVG(avg_dock_time) as current_general_avg_dock_time FROM active_workers;   
    

    
    
-- --
-- Fuction is updating current status of worker_ID.
-- Its receiving end_status + docking_score + num_conformers + id + worker_id
-- Currently set_worker_result python will call on Final Stage
-- --
DROP FUNCTION files.extrapolation;
-- --
CREATE FUNCTION files.extrapolation( integer ) RETURNS interval
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
        workers_to_be_added ALIAS FOR $1;
        avg_left_time interval;
    BEGIN
        SELECT CAST ( (
            (   -- Smiles records for each active worker
                ( SELECT count (id) from files.files 
                    WHERE 
                        docking_score is null AND status = 0 ) /
                    ( ( SELECT count (*) FROM active_workers ) + workers_to_be_added ) 
            ) * 
            (   -- General avg dock time from active workers
                SELECT AVG(avg_dock_time) as current_general_avg_dock_time 
                FROM active_workers 
            ) 
            ) AS interval)
            INTO avg_left_time;
            RETURN avg_left_time;
    END;
  $_$;

ALTER FUNCTION files.extrapolation( integer ) OWNER TO postgres;



-- -- 
DROP FUNCTION files.clean_files_of_broken_workers;
-- --
CREATE FUNCTION files.clean_files_of_broken_workers( ) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
    DECLARE
        updated integer;
    BEGIN
        UPDATE files.files
        SET start_ts = NULL
        , status = 0
        where 
            docking_score is NULL
            AND stop_ts is NULL
            AND start_ts < now() - interval '12 hour'
        ;
    END;
  $_$;

ALTER FUNCTION files.clean_files_of_broken_workers( ) OWNER TO postgres;
    


