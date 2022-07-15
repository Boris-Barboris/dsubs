-- CREATE DATABASE `dsubs_prod` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

BEGIN;

CREATE TABLE db_revision (
    revision INT NOT NULL
);

INSERT INTO db_revision VALUES (2);

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
    simulator_id varchar(64) NOT NULL,
    simulator_uniqid varchar(64),
    scenario_name TEXT,
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
    ('campaignMission'), ('persistentSimulator');

CREATE TABLE simulator_instances (
    uniqid varchar(64) PRIMARY KEY,
    id varchar(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP,
    destroyed_at TIMESTAMP,
    destroy_reason varchar(64),
    scenario_name TEXT,
    scenario_type varchar(64),

    FOREIGN KEY (scenario_type) REFERENCES scenario_types(`name`)
);

CREATE TABLE scenario_side_outcomes (
    name varchar(64) PRIMARY KEY
);

INSERT INTO scenario_side_outcomes VALUES
    ('victory'), ('defeat'), ('draw');

-- used to record wins and losses of players in scenarios
CREATE TABLE player_scenario_completions (
    player_id BIGINT NOT NULL,
    scenario_name TEXT NOT NULL,
    scenario_type varchar(64),
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP,
    simulator_uniqid varchar(64) NOT NULL,
    side_outcome varchar(64) NOT NULL,

    FOREIGN KEY (player_id) REFERENCES players(`id`),
    FOREIGN KEY (scenario_type) REFERENCES scenario_types(`name`),
    FOREIGN KEY (side_outcome) REFERENCES scenario_side_outcomes(`name`)
);

CREATE INDEX player_scenario_completions_pididx ON
    player_scenario_completions (player_id, created_at);

CREATE TABLE player_campaign_progress (
    player_id BIGINT NOT NULL,
    campaign_name varchar(256) NOT NULL,
    completed_missions INT NOT NULL,

    PRIMARY KEY (player_id, campaign_name),
    FOREIGN KEY (player_id) REFERENCES players(`id`)
);

COMMIT;