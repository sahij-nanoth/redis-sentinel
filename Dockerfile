FROM registry.access.redhat.com/ubi8/ubi:8.10

USER root

RUN dnf -y update && \
    dnf -y install hostname shadow-utils procps-ng iproute findutils tar gzip which haproxy && \
    dnf clean all

# Optional: keep only if your organization requires Java in the same base image
RUN dnf -y install java-21-openjdk-headless && \
    dnf clean all

# Copy your internal Redis 7.2 RPM into the build context with a matching name
COPY redis-7.2*.rpm /tmp/redis.rpm

RUN dnf -y install /tmp/redis.rpm && \
    rm -f /tmp/redis.rpm && \
    dnf clean all

RUN mkdir -p /opt/redis/conf /opt/redis/scripts /data /var/lib/haproxy && \
    chmod -R g=u /opt/redis /data /var/lib/haproxy /etc/haproxy

COPY conf/redis.conf /opt/redis/conf/redis.conf
COPY conf/sentinel.conf /opt/redis/conf/sentinel.conf
COPY conf/haproxy.cfg /opt/redis/conf/haproxy.cfg
COPY scripts/entrypoint.sh /opt/redis/scripts/entrypoint.sh

RUN chmod +x /opt/redis/scripts/entrypoint.sh

EXPOSE 6379 26379 16379

USER 1001

ENTRYPOINT ["/opt/redis/scripts/entrypoint.sh"]
CMD ["redis"]
