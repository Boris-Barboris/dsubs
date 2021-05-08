BEGIN;

ALTER TABLE kill_records ADD COLUMN
    simulator_id varchar(64);

UPDATE kill_records SET simulator_id = 'main_arena';

ALTER TABLE kill_records MODIFY simulator_id varchar(64) NOT NULL;

COMMIT;