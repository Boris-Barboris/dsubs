-- CREATE DATABASE `dsubs_prod` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

BEGIN;

CREATE TABLE players (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    login_name TEXT NOT NULL UNIQUE,
    pw_salt TEXT NOT NULL,
    pw_pdkdf2 TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP
);

CREATE TABLE captain_type (
    name varchar(32) PRIMARY KEY
);

INSERT INTO captain_type VALUES ('player'), ('bot'), ('animal');

CREATE TABLE kill_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP,
    shooter_captain_name TEXT,
    shooter_captain_type varchar(32),
    shooter_hull_name TEXT,
    dead_captain_name TEXT,
    dead_captain_type varchar(32),
    dead_hull_name TEXT,
    weapon_name TEXT,
    weapon_travelled FLOAT,

    FOREIGN KEY (shooter_captain_type) REFERENCES captain_type(`name`),
    FOREIGN KEY (dead_captain_type) REFERENCES captain_type(`name`)
);

CREATE TABLE scenario_types (
    name varchar(64) PRIMARY KEY
);

INSERT INTO scenario_types VALUES ('standalone'), ('tutorial'),
    ('capmaignMission'), ('persistentSimulator');

CREATE TABLE simulator_destroy_reasons (
    name varchar(64) PRIMARY KEY
);

INSERT INTO simulator_destroy_reasons VALUES
    ('timeout'), ('scenario-initiated'), ('abandon');

CREATE TABLE simulator_instances (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP,
    destroyed_at TIMESTAMP,
    destroy_reason TEXT,
    creator_id BIGINT,
    scenario_name TEXT NOT NULL,
    scenario_type TEXT NOT NULL,

    FOREIGN KEY (creator_id) REFERENCES players(`id`),
    FOREIGN KEY (destroy_reason) REFERENCES simulator_destroy_reasons(`name`),
    FOREIGN KEY (scenario_type) REFERENCES scenario_types(`name`)
);

ALTER TABLE kill_records ADD CONSTRAINT FOREIGN KEY (simulator_id)
    REFERENCES simulator_instances(id);

CREATE INDEX IF NOT EXISTS sim_instance_creator_id_idx ON
    simulator_instances(creator_id);

INSERT INTO simulator_instances (id, scenario_name, scenario_type) VALUES
    ('main_arena', 'main_arena');

CREATE TABLE player_scenario_completion (
    player_id BIGINT NOT NULL REFERENCES players(id),
    scenario_name TEXT NOT NULL,

    PRIMARY KEY (player_id, scenario_name)
);

CREATE TABLE campaign_progress (
    player_id BIGINT NOT NULL REFERENCES players(id),
    campaign_name TEXT NOT NULL,
    last_available_scenario TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT 'false',

    PRIMARY KEY (player_id, campaign_name)
);

COMMIT;