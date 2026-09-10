# Hermes Agent gateway for Google Chat (Pub/Sub).
# Extends official image with explicit Pub/Sub deps (Hermes Docker trap).
FROM nousresearch/hermes-agent:latest

USER root

RUN uv pip install --python /opt/hermes/.venv/bin/python \
    google-cloud-pubsub \
    google-api-python-client \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2

COPY deploy/entrypoint.sh /usr/local/bin/hermes-entrypoint.sh
COPY config/ /opt/hermes-config/
COPY profiles/ /opt/hermes-profiles/

RUN chmod +x /usr/local/bin/hermes-entrypoint.sh \
    && mkdir -p /opt/data /secrets \
    && chown -R hermes:hermes /opt/data /opt/hermes-config /opt/hermes-profiles 2>/dev/null || true

ENV HERMES_HOME=/opt/data
ENV PORT=8080

EXPOSE 8080 8642

ENTRYPOINT ["/usr/local/bin/hermes-entrypoint.sh"]
CMD ["gateway", "run"]
