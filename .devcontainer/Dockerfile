FROM mcr.microsoft.com/devcontainers/base:trixie

# Copy and install Zscaler certificate before features run
COPY zscaler-cert.pem /usr/local/share/ca-certificates/zscaler.crt
RUN update-ca-certificates

# Also set environment variable for curl to find certificates
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
