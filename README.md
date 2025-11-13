## Moodle LTS Docker images

Production-ready Apache images for Moodle LTS lines with PHP 8.1/8.2, tuned Redis sessions, and a prewired cron scheduler. This repository backs [pasechnik/moodle_lts_images](https://hub.docker.com/r/pasechnik/moodle_lts_images) but can be used to build custom variants.

### Supported tags and variants

- `4.5.7-lts` – Moodle 4.5.7 LTS, PHP 8.1, document root `/var/www/moodle`, virtual host `apache-4.x.conf`.
- `5.0.3-lts` – Moodle 5.0.3 LTS, PHP 8.2, document root `/var/www/moodle/public`, virtual host `apache-5.x.conf`.
- `5.1.0-lts`, `latest` – Moodle 5.1.0 LTS, PHP 8.2, public webroot `/var/www/moodle/public`.

See the [Docker Hub tags page](https://hub.docker.com/r/pasechnik/moodle_lts_images/tags) for the live list.

### Quick reference

- **Source & issues**: [github.com/pavel-pasechnik/moodle_lts_images](https://github.com/pavel-pasechnik/moodle_lts_images)
- **Base images**: official `php:<PHP_VERSION>-apache`
- **Supported databases**: PostgreSQL 13+, MySQL 8+, MariaDB 10.5+ (clients only ship with the container)

### Image highlights

- Apache 2.4 with `rewrite`, `headers`, `ssl`, `expires`, `deflate`, `FallbackResource /r.php`, `AcceptPathInfo On`, `Options -Indexes`, `EnableSendfile Off`, and `EnableMMAP Off`.
- PHP 8.1/8.2 with `intl`, `soap`, `xsl`, `opcache`, `gd`, `zip`, `pdo_mysql`, `pdo_pgsql`, `pgsql`, `mysqli`, and more.
- PECL extensions `igbinary`, `msgpack`, `redis` compiled with igbinary/msgpack/lzf support.
- Cron job every minute via `/etc/cron.d/moodle-cron`.
- Entry script writes Redis session configuration to `/usr/local/etc/php/conf.d/redis-session.ini`.
- Custom overrides in `config/php/php.ini` copied to `/usr/local/etc/php/conf.d/zzz-moodle.ini` (ships with `max_input_vars = 5000`, higher resource/time limits, error/log suppression, and tuned opcache).
- Elasticsearch support should be installed at the application level via the official Composer client (PECL module is discontinued).

### How to use these images

Run a published tag:

```bash
docker run --rm -p 8080:80 \
  -e REDIS_HOST=redis \
  -v moodledata:/var/www/moodledata \
  pasechnik/moodle_lts_images:5.1.0-lts
```

Build/push your own variant:

```bash
docker build \
  --build-arg PHP_VERSION=8.2 \
  --build-arg MOODLE_VERSION=v5.1.0 \
  --build-arg DOCUMENT_ROOT=/var/www/moodle/public \
  --build-arg APACHE_CONF=apache-5.x.conf \
  -t your-namespace/moodle:5.1.0-lts .

docker push your-namespace/moodle:5.1.0-lts
```

### PHP configuration overrides

The build copies `config/php/php.ini` into `/usr/local/etc/php/conf.d/zzz-moodle.ini`, so its directives win over defaults in the base `php.ini`. Out of the box it:

- raises `max_input_vars` to `5000`, satisfying the Moodle installer;
- bumps typical upload/time/memory limits (`upload_max_filesize = 50M`, `post_max_size = 50M`, `memory_limit = 512M`, `max_execution_time = 300`);
- disables runtime error display/logging (`display_errors = Off`, `log_errors = Off`); and
- configures opcache for medium-sized deployments.

Adjust this file to suit your environment, then rebuild/push the image—the `zzz-` prefix ensures the overrides load last.

#### Sample docker-compose

```yaml
services:
  moodle:
    image: pasechnik/moodle_lts_images:5.1.0-lts
    depends_on:
      - db
      - redis
    environment:
      REDIS_HOST: redis
      REDIS_DB: 2
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

volumes:
  moodledata:
```

### Build arguments

| ARG | Purpose | Default |
|-----|---------|---------|
| `PHP_VERSION` | Base image (`php:<ver>-apache`). | `8.2` |
| `MOODLE_VERSION` | Moodle git tag to clone. | `v5.1.0` |
| `MOODLE_GIT_REPO` | Moodle repository URL (override with your fork if needed). | `https://github.com/moodle/moodle.git` |
| `DOCUMENT_ROOT` | Directory Apache serves. | `/var/www/moodle/public` |
| `APACHE_CONF` | Virtual host file copied into Apache. | `apache-5.x.conf` |

### Runtime environment (Redis)

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_REDIS_SESSION` | `1` | Set to `0` to skip Redis session handler configuration. |
| `REDIS_HOST` | `redis` | Redis hostname. |
| `REDIS_PORT` | `6379` | Redis port. |
| `REDIS_DB` | `0` | Database index reserved for sessions. |
| `REDIS_PASSWORD` | empty | Optional password appended to the DSN. |
| `REDIS_TIMEOUT` | `2.5` | Connection timeout (seconds). |
| `REDIS_READ_TIMEOUT` | `2.5` | Read timeout (seconds). |
| `REDIS_SESSION_LOCKING` | `1` | Enables Moodle-safe session locking. |
| `REDIS_SESSION_LOCK_RETRIES` | `200` | Number of lock retry attempts. |
| `REDIS_SESSION_LOCK_WAIT` | `20000` | Microseconds to wait between retries. |
| `REDIS_PCONNECT_POOLING` | `1` | Turns on persistent connection pooling. |

### Database requirements

- **PostgreSQL**: 13+. Tune `max_connections`, `shared_buffers`, `work_mem`, etc., per Moodle’s guidelines.
- **MySQL / MariaDB**: enable Barracuda (`innodb_file_per_table=1`, `innodb_file_format=Barracuda`), use `utf8mb4`, increase `innodb_buffer_pool_size` and `innodb_log_file_size`, and clear strict `sql_mode`. See the [official Moodle docs](https://docs.moodle.org/501/en/MySQL) for the full checklist.

### HTTPS and reverse proxies

- Terminate TLS in front of the container (Nginx, Traefik, Kubernetes ingress) and forward HTTP to port 80.
- During installation set `$CFG->wwwroot` to the external `https://` URL so Moodle emits secure links.

### CI / publishing

The workflow in `.github/workflows/build.yml` logs into Docker Hub on every push to `main`, builds the matrix, and publishes the `*-lts` tags plus `latest`. Track releases via GitHub Actions or the Docker Hub tags page.
