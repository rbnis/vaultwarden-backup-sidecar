FROM alpine:3.22.1

RUN apk add --no-cache sqlite tar gzip gnupg
RUN apk add --no-cache s5cmd --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN apk add --no-cache supercronic --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/

COPY --chown=nobody:nobody entrypoint.sh /entrypoint.sh
COPY --chown=nobody:nobody backup.sh /usr/local/bin/backup.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/backup.sh

USER nobody

ENV CRON_SCHEDULE="0 2 * * *"

ENTRYPOINT ["/entrypoint.sh"]
