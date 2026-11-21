CREATE DATABASE IF NOT EXISTS users_db;
CREATE DATABASE IF NOT EXISTS books_db;
CREATE DATABASE IF NOT EXISTS stores_db;

CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'repl_pass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

USE users_db;
CREATE TABLE IF NOT EXISTS users (
    user_id     BIGINT PRIMARY KEY,
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    email       VARCHAR(100) UNIQUE,
    city        VARCHAR(50),
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

USE books_db;
CREATE TABLE IF NOT EXISTS books (
    book_id     BIGINT PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    author      VARCHAR(100),
    store_id    BIGINT NOT NULL,
    store_name  VARCHAR(100),
    price       DECIMAL(10,2) DEFAULT 0.00,
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    KEY idx_store (store_id)
) ENGINE=InnoDB;

USE stores_db;
CREATE TABLE IF NOT EXISTS stores (
    store_id    BIGINT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    city        VARCHAR(50),
    address     VARCHAR(200),
    region      VARCHAR(50),
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
