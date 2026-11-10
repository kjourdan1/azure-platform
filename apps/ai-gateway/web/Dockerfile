# nginx-unprivileged 1.30 (branche stable ; 1.28 n'est plus reconstruite), épinglé par
# digest. UID 101, port 8080.
FROM nginxinc/nginx-unprivileged:1.30-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
# Correctifs Alpine publiés après la construction de l'image de base : sans eux, le scan
# Trivy de la CI bloque la publication.
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY static/ /usr/share/nginx/html/
EXPOSE 8080
