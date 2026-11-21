# Домашнее задание к занятию «Репликация и масштабирование. Часть 2»

**Выполнил:** Haujs

---

### Задание 1

Опишите основные преимущества использования масштабирования методами:

- активный master-сервер и пассивный репликационный slave-сервер;
- master-сервер и несколько slave-серверов.

**Решение.**

**1. Активный master + пассивный slave (hot standby)**

- **Отказоустойчивость.** Slave хранит полную копию данных. При отказе master его можно повысить до роли master (failover) и продолжить запись — простой минимален.
- **Резервное копирование без нагрузки на master.** Дампы (`mysqldump`, `xtrabackup`) снимаются с slave, поэтому production-сервер не тормозит.
- **Обслуживание и обновления.** Обновление версии MySQL, смена оборудования, реиндекс выполняются сначала на slave, затем производится переключение.
- **Защита от катастроф.** Slave можно вынести в другой дата-центр/зону доступности — данные сохранятся при потере основного ЦОД.
- Минусы: slave простаивает (не отдаёт чтение), возможен лаг репликации, failover требует автоматизации (MHA, Orchestrator, Keepalived) или ручных действий.

**2. Master + несколько slave (read scaling)**

- **Масштабирование чтения.** SELECT-запросы распределяются между slave, суммарная пропускная способность чтения растёт линейно с числом slave.
- **Разделение нагрузки.** Аналитика, отчёты, поиск, экспорт и бэкапы идут на slave и не конкурируют с транзакционной записью на master.
- **Географическое распределение.** Slave размещаются ближе к пользователям (read-local), снижая задержку ответа.
- **Отказоустойчивость.** Любой slave может быть повышен до master; при выходе одного slave остальные продолжают обслуживать чтение.
- Минусы: лаг репликации (read-after-write аномалии), master остаётся единственной точкой записи, растут расходы на железо и сложность балансировки/мониторинга.

Итог: первый вариант — простой запасной узел «на всякий случай», второй — рабочий кластер, где slave одновременно увеличивают throughput чтения и служат кандидатами на failover.

---

### Задание 2

Разработайте план для выполнения горизонтального и вертикального шаринга базы данных. База данных состоит из трёх таблиц: пользователи, книги, магазины.

**Решение.**

#### Вертикальный шаринг (по таблицам/доменам)

Разделяем по функциональному признаку: каждая таблица уезжает в собственную БД на собственный сервер.

| БД | Таблица | Назначение |
|---|---|---|
| `users_db` | `users` | профили, авторизация, роли |
| `books_db` | `books` | каталог книг, описания, цены |
| `stores_db` | `stores` | магазины, адреса, остатки |

Правила:

- Connect-строки и роутинг хранятся в приложении (или в ProxySQL/Vitess).
- **Запрещаются кросс-БД `JOIN`** — вместо них приложение делает последовательные запросы или используется денормализация (например, в `books` храним `store_name`, в `stores` — `city`).
- У каждой БД свой master (READ/WRITE) и по одному replica (READ ONLY) для чтения и бэкапов.
- Плюсы: меньше конкуренции за блокировки, компактнее индексы, независимое масштабирование и обновление доменов, изоляция отказов.

#### Горизонтальный шаринг (по строкам внутри таблицы)

Ключ шардирования выбирается так, чтобы большинство запросов попадали в один шард:

| Таблица | Ключ шарда | Правило | Число шардов |
|---|---|---|---|
| `users` | `user_id` | `user_id % 2` | 2 |
| `books` | `book_id` | `book_id % 2` | 2 |
| `stores` | `store_id` / регион | `store_id % 2` либо по региону | 1 (маленькая таблица) + replica |

Принципы:

- **Роутер шардов** (приложение или ProxySQL) по значению ключа определяет нужный экземпляр: `shard = id % 2`.
- **Глобальные ID** генерируются централизованно (Snowflake, UUID, sequence-сервис), иначе возможны коллизии между шардами.
- **Локальность данных:** всё, что часто читается вместе (книга + её остаток в магазине), кладётся в один шард — тогда `JOIN` остаётся локальным.
- **Кросс-шард-запросы** (scatter-gather) избегаются: в запросе всегда присутствует ключ шарда. Справочники дублируются во все шарды.
- **Репликация внутри шарда:** 1 master + 1 replica на шард; реплика читает SELECT и служит failover-кандидатом.

#### Режимы работы серверов

| Узел | Роль | Режим |
|---|---|---|
| `users_shard_0/1`, `books_shard_0/1`, `stores` | master | `read_only=OFF`, binlog включён, принимает INSERT/UPDATE/DELETE |
| `users_shard_0/1-replica`, `books_shard_0/1-replica`, `stores-replica` | slave | `read_only=ON`, `super_read_only=ON`, только SELECT и бэкапы |
| Роутер | балансировщик | stateless, не хранит данные, знает `id % N` и адреса шардов |

#### Блок-схема

```mermaid
flowchart TB
    APP[Приложение] --> ROUTER{Роутер шардов<br/>ProxySQL / Vitess / код приложения}

    subgraph VERT["Вертикальное разделение по доменам"]
      subgraph USERS["Домен: пользователи"]
        U0[(users_shard_0<br/>MASTER RW)]
        U0R[(users_shard_0<br/>REPLICA RO)]
        U1[(users_shard_1<br/>MASTER RW)]
        U1R[(users_shard_1<br/>REPLICA RO)]
      end
      subgraph BOOKS["Домен: книги"]
        B0[(books_shard_0<br/>MASTER RW)]
        B0R[(books_shard_0<br/>REPLICA RO)]
        B1[(books_shard_1<br/>MASTER RW)]
        B1R[(books_shard_1<br/>REPLICA RO)]
      end
      subgraph STORES["Домен: магазины"]
        S0[(stores<br/>MASTER RW)]
        S0R[(stores<br/>REPLICA RO)]
      end
    end

    ROUTER -->|"user_id % 2"| U0
    ROUTER -->|"user_id % 2"| U1
    ROUTER -->|"book_id % 2"| B0
    ROUTER -->|"book_id % 2"| B1
    ROUTER -->|"store_id"| S0

    U0 -. репликация .-> U0R
    U1 -. репликация .-> U1R
    B0 -. репликация .-> B0R
    B1 -. репликация .-> B1R
    S0 -. репликация .-> S0R

    ROUTER -. SELECT / отчёты .-> U0R
    ROUTER -. SELECT / отчёты .-> B0R
    ROUTER -. SELECT / отчёты .-> S0R
```

Тот же план в виде изображения:

![Блок-схема шардинга](img/sharding-diagram.png)

---

### Задание 3*

Выполните настройку выбранных методов шардинга из задания 2.

**Решение.** Описан и сконфигурирован кластер из 10 контейнеров MySQL 8.0: по 2 master-шарда и 2 replica на домены `users` и `books`, а также master + replica домена `stores`.

Файлы:

- [`docker-compose.yml`](docker-compose.yml) — конфигурация Docker с сетевыми адресами, `server-id`, binlog и `read_only` для реплик;
- [`sql/init.sql`](sql/init.sql) — создание БД, таблиц и пользователя репликации;
- [`sql/replication.sql`](sql/replication.sql) — команды настройки репликации (выполняются после старта контейнеров).

Порядок запуска:

```bash
docker compose up -d
# дождаться готовности всех MySQL, затем на каждом мастере:
docker compose exec users-shard-0 mysql -uroot -proot -e "SHOW MASTER STATUS;"
# подставить FILE/POS в sql/replication.sql и выполнить его на репликах
docker compose exec users-shard-0-replica mysql -uroot -proot < sql/replication.sql
docker compose exec users-shard-0-replica mysql -uroot -proot -e "SHOW SLAVE STATUS\G"
```

**Ожидаемое состояние после запуска**

`docker ps`:

```
CONTAINER ID   IMAGE       STATUS                    PORTS                                       NAMES
a1f3c8d20e4b   mysql:8.0   Up 12 minutes (healthy)   0.0.0.0:3307->3306/tcp, :::3307->3306/tcp   users-shard-0
b27e4a91c6d3   mysql:8.0   Up 12 minutes             0.0.0.0:3308->3306/tcp, :::3308->3306/tcp   users-shard-0-replica
c94d1b7e3a08   mysql:8.0   Up 12 minutes (healthy)   0.0.0.0:3309->3306/tcp, :::3309->3306/tcp   users-shard-1
d3a6f02c5b91   mysql:8.0   Up 12 minutes             0.0.0.0:3310->3306/tcp, :::3310->3306/tcp   users-shard-1-replica
e48b2c90a7f5   mysql:8.0   Up 12 minutes (healthy)   0.0.0.0:3311->3306/tcp, :::3311->3306/tcp   books-shard-0
f51c9d3e8a26   mysql:8.0   Up 12 minutes             0.0.0.0:3312->3306/tcp, :::3312->3306/tcp   books-shard-0-replica
071de4a2b9c8   mysql:8.0   Up 12 minutes (healthy)   0.0.0.0:3313->3306/tcp, :::3313->3306/tcp   books-shard-1
18e2b7c04f6a   mysql:8.0   Up 12 minutes             0.0.0.0:3314->3306/tcp, :::3314->3306/tcp   books-shard-1-replica
29f3c8d1a7b0   mysql:8.0   Up 12 minutes (healthy)   0.0.0.0:3315->3306/tcp, :::3315->3306/tcp   stores
3a4d9e2f6b18   mysql:8.0   Up 12 minutes             0.0.0.0:3316->3306/tcp, :::3316->3306/tcp   stores-replica
```

`SHOW MASTER STATUS` на `users-shard-0`:

```
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000003 |     1569 |              |                  |                   |
+------------------+----------+--------------+------------------+-------------------+
```

`SHOW SLAVE STATUS\G` на `users-shard-0-replica` (ключевые поля):

```
*************************** 1. row ***************************
               Slave_IO_State: Waiting for source to send event
                  Master_Host: users-shard-0
                  Master_User: repl
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000003
          Read_Master_Log_Pos: 1569
               Relay_Log_File: relay-bin.000002
                Relay_Log_Pos: 454
        Relay_Master_Log_File: mysql-bin.000003
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB:
          Last_IO_Errno: 0
          Last_SQL_Errno: 0
        Seconds_Behind_Master: 0
                  Auto_Position: 0
```

Проверка шардирования и репликации на тестовых строках:

```sql
-- запись в шарды (роутер выбирает инстанс по id % 2)
INSERT INTO users_db.users (user_id, first_name, last_name, email, city)
VALUES (4, 'Mike', 'Hillyer', 'mike@example.com', 'Lethbridge');   -- users-shard-0
INSERT INTO users_db.users (user_id, first_name, last_name, email, city)
VALUES (5, 'Jon', 'Stephens', 'jon@example.com', 'Woodridge');     -- users-shard-1

INSERT INTO books_db.books (book_id, title, author, store_id, store_name, price)
VALUES (2, 'Sakila Learning', 'A. Author', 1, 'Main Store', 9.99); -- books-shard-0
INSERT INTO books_db.books (book_id, title, author, store_id, store_name, price)
VALUES (3, 'Sharding Guide', 'B. Writer', 2, 'North Store', 14.99);-- books-shard-1

INSERT INTO stores_db.stores (store_id, name, city, address, region)
VALUES (1, 'Main Store', 'Lethbridge', '12 Main St', 'West');      -- stores
```

```
users-shard-0:  4 | Mike  | Hillyer  | Lethbridge
users-shard-1:  5 | Jon   | Stephens | Woodridge
users-shard-0-replica:  4 | Mike | Hillyer | Lethbridge   <- репликация работает
books-shard-0:  2 | Sakila Learning | Main Store
books-shard-1:  3 | Sharding Guide  | North Store
stores:         1 | Main Store | Lethbridge
```

Маршрутизация в приложении:

```sql
-- шард 0
SELECT * FROM users_db.users WHERE user_id = 4;   -- 4 % 2 = 0  -> users-shard-0
-- шард 1
SELECT * FROM users_db.users WHERE user_id = 5;   -- 5 % 2 = 1  -> users-shard-1
```

> Приведённые выше выводы — ожидаемый результат после запуска конфигурации (в этой среде Docker не запускался). FILE/POS в `replication.sql` нужно подставить из `SHOW MASTER STATUS` после фактического старта контейнеров.
