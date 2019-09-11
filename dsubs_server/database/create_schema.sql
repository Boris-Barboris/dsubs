BEGIN;

CREATE TABLE players (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    login_name text NOT NULL UNIQUE,
    login_password text NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMIT;