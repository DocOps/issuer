FROM ruby:3.2-slim

ARG ISSUER_VERSION
LABEL org.opencontainers.image.version=$ISSUER_VERSION

# Install necessary build tools and dependencies (minimal footprint)
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      build-essential
    && rm -rf /var/lib/apt/lists/*

# Set app directory for build context
WORKDIR /app

# Copy local gem source and install it
COPY . .
RUN gem install rake
RUN gem build issuer.gemspec && \
  gem install issuer-*.gem && \
  rm -rf /app

# Ensure gem executables are in PATH
ENV PATH="/usr/local/bundle/bin:$PATH"

# Set runtime working dir to isolated mount point
WORKDIR /workdir

# Default entrypoint and fallback command
ENTRYPOINT ["issuer"]
CMD ["help"]