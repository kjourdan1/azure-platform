# Image épinglée par digest (python:3.13-slim) : une reconstruction donne la même base.
FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS deps
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r /tmp/requirements.txt

FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Correctifs Debian publiés après l'image de base ; pip (et les bibliothèques qu'il embarque)
# ne sert qu'à construire : retiré de l'image d'exécution, il ne peut plus y être vulnérable.
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip && rm -rf /usr/local/lib/python3.13/ensurepip
COPY --from=deps /install /usr/local
WORKDIR /srv
COPY app ./app
# Utilisateur numérique non root : vérifiable par Kubernetes (runAsNonRoot) sans le résoudre.
USER 10001:10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header", "--no-access-log"]
