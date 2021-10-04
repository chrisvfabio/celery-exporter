FROM python:3.6-alpine as base-image

ENV LANG=C.UTF-8

RUN apk add libgcc

FROM base-image as build-rs

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

WORKDIR /src

RUN apk add --no-cache alpine-sdk bash && \
    wget "https://sh.rustup.rs" -O rustup-init && \
    chmod +x ./rustup-init && \
    ./rustup-init -y --no-modify-path --default-toolchain stable --default-host `apk --print-arch`-unknown-linux-musl && \
    rm -rf rustup-init && \
    bash -c 'wget "https://github.com/PyO3/maturin/releases/download/v0.11.5/maturin-$(apk --print-arch)-unknown-linux-musl.tar.gz" -O maturin.tar.gz' && \
    tar -C /usr/local/cargo/bin -zxf maturin.tar.gz && \
    rm -rf maturin.tar.gz

COPY Cargo.toml Cargo.lock README.md ./
COPY src/ ./src
COPY celery_exporter/  ./celery_exporter/

RUN RUSTFLAGS="-C target-feature=-crt-static" maturin build --target `apk --print-arch`-unknown-linux-musl --release --manylinux off -o /src/wheelhouse

FROM base-image as app
LABEL maintainer="Fabio Todaro <fbregist@gmail.com>"

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
      org.label-schema.vcs-url="https://github.com/OvalMoney/celery-exporter"

WORKDIR /app/

COPY --from=build-rs /src/wheelhouse/ /app/wheelhouse/

COPY requirements/ ./requirements
RUN pip install -r ./requirements/requirements_celery5.txt

RUN pip install wheelhouse/*

ENTRYPOINT ["celery-exporter"]
CMD []

EXPOSE 9540
