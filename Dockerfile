FROM python:3.10-alpine as poetry-export
# requires deps for poetry setup
RUN apk add libffi-dev build-base
# pin the version of poetry we install
ENV POETRY_VERSION=1.2.2 \
  # make poetry install to this location so we can add it to PATH
  POETRY_HOME="/opt/.poetry"
# setup poetry
RUN wget -O - -o /dev/null https://install.python-poetry.org | python -
# prepend poetry to path
ENV PATH="$POETRY_HOME/bin:$PATH"
# switch to build directory
WORKDIR /build
COPY poetry.lock pyproject.toml /build/
# export dependencies
RUN poetry export -f requirements.txt --output requirements.txt
# export dev dependencies
RUN poetry export -f requirements.txt --output requirements_dev.txt --only dev

COPY celery_exporter  /build/celery_exporter
# build the project wheel
RUN poetry build

FROM python:3.10-alpine as build-wheels
RUN apk add alpine-sdk
WORKDIR /src
# hiredis requires gcc, so build the wheel here
RUN pip wheel hiredis -w /src/wheelhouse

## Shared base ##
FROM python:3.10-alpine as base-image
WORKDIR /build
COPY --from=build-wheels /src/wheelhouse/ /build/wheelhouse/
RUN pip install wheelhouse/*.whl
# install requirements separately for improved caching
COPY --from=poetry-export /build/requirements.txt /build/requirements.txt
RUN pip install -r requirements.txt

## Dev image ##
FROM base-image AS dev
COPY --from=poetry-export /build/requirements_dev.txt /build/requirements_dev.txt
RUN pip install -r requirements_dev.txt
WORKDIR /app
COPY . .

## Prod image ##
FROM base-image as app
COPY --from=poetry-export /build/dist/ /build/dist/
RUN pip install /build/dist/*.whl
LABEL maintainer="Fabio Todaro <fbregist@gmail.com>"
ENTRYPOINT ["python", "-m", "celery_exporter"]
CMD []

ARG BUILD_DATE
ARG DOCKER_REPO
ARG VERSION
ARG VCS_REF

LABEL org.label-schema.schema-version="1.0" \
  org.label-schema.build-date=$BUILD_DATE \
  org.label-schema.name=$DOCKER_REPO \
  org.label-schema.version=$VERSION \
  org.label-schema.description="Prometheus metrics exporter for Celery" \
  org.label-schema.vcs-ref=$VCS_REF \
  org.label-schema.vcs-url="https://github.com/grafana/celery-exporter"

EXPOSE 9540
