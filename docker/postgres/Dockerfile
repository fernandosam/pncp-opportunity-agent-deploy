FROM postgres:18-bookworm
COPY entrypoint.sh /usr/local/bin/pncp-postgres
COPY init-runtime.sh /docker-entrypoint-initdb.d/10-runtime.sh
RUN chmod 755 /usr/local/bin/pncp-postgres /docker-entrypoint-initdb.d/10-runtime.sh
ENTRYPOINT ["pncp-postgres"]
CMD ["postgres", "-c", "ssl=on", "-c", "ssl_cert_file=/run/pncp-tls/server.crt", "-c", "ssl_key_file=/run/pncp-tls/server.key", "-c", "password_encryption=scram-sha-256"]
