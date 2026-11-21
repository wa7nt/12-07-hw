-- Выполнять на каждом сервере-реплике после получения FILE/POS
-- командой SHOW MASTER STATUS на соответствующем master.

-- 1) users-shard-0-replica  <-  users-shard-0  (server-id=11 <- 10)
CHANGE MASTER TO
  MASTER_HOST='users-shard-0',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='repl_pass',
  MASTER_LOG_FILE='mysql-bin.000002',
  MASTER_LOG_POS=156;
START SLAVE;

-- 2) users-shard-1-replica  <-  users-shard-1  (server-id=21 <- 20)
CHANGE MASTER TO
  MASTER_HOST='users-shard-1',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='repl_pass',
  MASTER_LOG_FILE='mysql-bin.000002',
  MASTER_LOG_POS=156;
START SLAVE;

-- 3) books-shard-0-replica  <-  books-shard-0  (server-id=31 <- 30)
CHANGE MASTER TO
  MASTER_HOST='books-shard-0',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='repl_pass',
  MASTER_LOG_FILE='mysql-bin.000002',
  MASTER_LOG_POS=156;
START SLAVE;

-- 4) books-shard-1-replica  <-  books-shard-1  (server-id=41 <- 40)
CHANGE MASTER TO
  MASTER_HOST='books-shard-1',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='repl_pass',
  MASTER_LOG_FILE='mysql-bin.000002',
  MASTER_LOG_POS=156;
START SLAVE;

-- 5) stores-replica  <-  stores  (server-id=51 <- 50)
CHANGE MASTER TO
  MASTER_HOST='stores',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='repl_pass',
  MASTER_LOG_FILE='mysql-bin.000002',
  MASTER_LOG_POS=156;
START SLAVE;

-- Проверка на каждой реплике:
-- SHOW SLAVE STATUS\G
-- Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
