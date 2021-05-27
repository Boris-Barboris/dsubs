BEGIN;

CREATE TABLE db_revision (
    revision INT NOT NULL
);
INSERT INTO db_revision VALUES (1);


ALTER TABLE kill_records ADD COLUMN simulator_id varchar(64);
UPDATE kill_records SET simulator_id = 'main_arena';
ALTER TABLE kill_records MODIFY simulator_id varchar(64) NOT NULL;
ALTER TABLE kill_records ADD COLUMN simulator_uniqid varchar(64);
ALTER TABLE kill_records ADD COLUMN scenario_name TEXT;


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
    uniqid varchar(64) PRIMARY KEY,
    id varchar(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT UTC_TIMESTAMP,
    destroyed_at TIMESTAMP,
    destroy_reason varchar(64),
    scenario_name TEXT,
    scenario_type varchar(64),

    FOREIGN KEY (destroy_reason) REFERENCES simulator_destroy_reasons(`name`),
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
    campaign_name TEXT NOT NULL,
    completed_missions INT NOT NULL,

    PRIMARY KEY (player_id, campaign_name),
    FOREIGN KEY (player_id) REFERENCES players(`id`)
);


COMMIT;