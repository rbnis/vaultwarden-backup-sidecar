FROM alpine:3.22.1

RUN apk add --no-cache sqlite tar gzip dcron gnupg
RUN apk add --no-cache s5cmd --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/

COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/backup.sh

ENV CRON_SCHEDULE="0 2 * * *"

ENTRYPOINT ["/entrypoint.sh"]
