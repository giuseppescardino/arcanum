# Encrypted PostgreSQL backups for the sync server (see backup.sh).
# Same major version as the db service, so pg_dump/pg_restore match it.
FROM postgres:18
RUN apt-get update \
    && apt-get install -y --no-install-recommends age curl \
    && rm -rf /var/lib/apt/lists/*
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod 755 /usr/local/bin/backup.sh
ENTRYPOINT ["backup.sh"]
CMD ["loop"]
