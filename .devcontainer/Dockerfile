FROM mcr.microsoft.com/devcontainers/base:trixie

# Copy and install Zscaler certificate before features run
COPY zscaler-cert.pem /usr/local/share/ca-certificates/zscaler.pem
RUN update-ca-certificates
