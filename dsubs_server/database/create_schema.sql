BEGIN;

CREATE TABLE players (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    login_name TEXT NOT NULL UNIQUE,
    login_password TEXT NOT NULL,
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

COMMIT;