## Moodle LTS Docker images

Production ready Apache images for Moodle LTS lines with tuned Redis sessions and Elasticsearch driver support.

### Supported tags

| Tag | Moodle | PHP | Document root | Notes |
|-----|--------|-----|---------------|-------|
| `4.5.7-php81` | 4.5.7 (LTS) | 8.1 | `/var/www/moodle` | Default Moodle 4.x layout (Apache config `apache-4.x.conf`). |
| `5.0.3-php82` | 5.0.3 (LTS) | 8.2 | `/var/www/moodle/public` | Modern layout with public webroot. |
| `5.1.0`, `latest` | 5.1.0 (LTS) | 8.2 | `/var/www/moodle/public` | Next LTS, doubles as `latest`. |

Build commands (run from repo root):

```bash
docker build \
  --build-arg PHP_VERSION=8.1 \
  --build-arg MOODLE_VERSION=v4.5.7 \
  --build-arg DOCUMENT_ROOT=/var/www/moodle \
  --build-arg APACHE_CONF=apache-4.x.conf \
  -t your-dockerhub-user/moodle:4.5.7-php81 .

docker build \
  --build-arg PHP_VERSION=8.2 \
  --build-arg MOODLE_VERSION=v5.0.3 \
  --build-arg DOCUMENT_ROOT=/var/www/moodle/public \
  --build-arg APACHE_CONF=apache-5.x.conf \
  -t your-dockerhub-user/moodle:5.0.3-php82 .

docker build \
  --build-arg PHP_VERSION=8.2 \
  --build-arg MOODLE_VERSION=v5.1.0 \
  --build-arg DOCUMENT_ROOT=/var/www/moodle/public \
  --build-arg APACHE_CONF=apache-5.x.conf \
  -t your-dockerhub-user/moodle:5.1.0 .
```

Push to DockerHub with `docker push your-dockerhub-user/moodle:<tag>`.

### Runtime services

- Apache + PHP (opcache, intl, soap, gd, pgsql, mysqli, PDO drivers).
- Cron pre-configured to run Moodle every minute.
- PostgreSQL, MySQL, and MariaDB client libraries (connect using `config.php`).
- Redis & Elasticsearch PHP extensions.

### Routing requirements (Moodle 4.5+)

- Moodle’s Routing Engine (introduced in 4.5) requires Apache’s `FallbackResource /r.php`. Both `apache-4.x.conf` and `apache-5.x.conf` ship with this directive.
- Moodle 5.1 adds a `/public` directory. When targeting Moodle 5.1+ you **must** set `DOCUMENT_ROOT=/var/www/moodle/public` (already the default for the 5.x builds) so only web-safe assets are exposed.
- `.htaccess` overrides are disabled (`AllowOverride None`) because routing + slash arguments are handled centrally. Adjust the Apache configs in this repo if you need to re-enable directory overrides.
- `AcceptPathInfo On` and `Options -Indexes` are set on the served directory so Moodle slash-arguments work while hiding directory listings.
- `EnableSendfile Off` / `EnableMMAP Off` are applied globally to avoid file corruption when Moodle stores data on shared or containerised volumes (per Moodle Apache docs).

### Enabling HTTPS

- Terminate TLS in front of the container (e.g., Nginx, Traefik, AWS ALB, or Kubernetes ingress) and proxy cleartext traffic to port 80.
- Set Moodle’s `$CFG->wwwroot` to the external `https://` URL during installation; otherwise it will continue to emit HTTP links and fail some security checks.
- If you need Apache inside the container to serve TLS directly, mount certificates and enable the existing `ssl` module (already enabled) with a custom vhost file.

### Redis optimizations for Moodle

The container writes `/usr/local/etc/php/conf.d/redis-session.ini` during startup, enabling Redis-backed sessions together with Moodle-recommended locking values. Control via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_REDIS_SESSION` | `1` | Set to `0` to disable automatic Redis session handler. |
| `REDIS_HOST` | `redis` | Hostname of your Redis service. |
| `REDIS_PORT` | `6379` | Redis port. |
| `REDIS_DB` | `0` | Database index reserved for sessions. |
| `REDIS_PASSWORD` | empty | Optional password appended to session DSN. |
| `REDIS_TIMEOUT` | `2.5` | Connection timeout (seconds). |
| `REDIS_READ_TIMEOUT` | `2.5` | Read timeout (seconds). |
| `REDIS_SESSION_LOCKING` | `1` | Enables Moodle-safe session locking. |
| `REDIS_SESSION_LOCK_RETRIES` | `200` | Retry attempts while waiting on a lock. |
| `REDIS_SESSION_LOCK_WAIT` | `20000` | Wait time between retries in microseconds. |
| `REDIS_PCONNECT_POOLING` | `1` | Enables Redis persistent connection pooling. |

With these defaults, pointing the container at a Redis service is enough to get low-latency session storage. Adjust DB indices per environment to keep sessions separate from other caches.

### MySQL / MariaDB prerequisites

These containers only ship DB client tools; you must configure your external MySQL/MariaDB server according to the [Moodle 5.0+ MySQL guide](https://docs.moodle.org/501/en/MySQL). Essential settings (MySQL 8+ syntax) that should be present in `mysqld` configuration:

```ini
[mysqld]
default_storage_engine = InnoDB
innodb_file_per_table = 1
innodb_file_format = Barracuda
innodb_large_prefix = 1
innodb_file_format_max = Barracuda
innodb_file_format = Barracuda
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_buffer_pool_size = 1G        # adjust to >= 50% of server RAM
max_allowed_packet = 256M
innodb_log_file_size = 256M
sql_mode = ""
```

MariaDB should follow the same principles. In addition to the above, ensure the server runs MariaDB 10.5+ with `innodb_default_row_format=dynamic` and `innodb_strict_mode=ON` as documented in the [Moodle MariaDB guide](https://docs.moodle.org/501/en/MariaDB). Restart the DB after applying changes, then create the Moodle database with `utf8mb4_unicode_ci` collation before running the installer.

### Example docker-compose

```yaml
services:
  moodle:
    image: your-dockerhub-user/moodle:5.1.0
    depends_on:
      - db
      - redis
    environment:
      REDIS_HOST: redis
      REDIS_DB: 2
      REDIS_SESSION_LOCK_RETRIES: 500
    volumes:
      - moodledata:/var/www/moodledata
    ports:
      - "8080:80"

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: moodle
      POSTGRES_PASSWORD: supersecret
      POSTGRES_DB: moodle

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "60", "1"]

volumes:
  moodledata:
```

Inside Moodle, complete the database setup using the `db` service connection string and configure Redis application caches via the admin UI if required.
