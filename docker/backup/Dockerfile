FROM postgres:18-alpine
RUN apk add --no-cache age bash ca-certificates coreutils
COPY backup.sh /usr/local/bin/pncp-backup
COPY schedule.sh /usr/local/bin/pncp-backup-schedule
RUN chmod 755 /usr/local/bin/pncp-backup /usr/local/bin/pncp-backup-schedule
ENTRYPOINT ["pncp-backup"]
