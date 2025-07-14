FROM ruby:3.2-slim

ARG ISSUER_VERSION
ARG ISSUER_SOURCE=repo
LABEL org.opencontainers.image.version=$ISSUER_VERSION

# Install necessary build tools and dependencies (minimal footprint)
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git && \
    rm -rf /var/lib/apt/lists/*

# Install issuer gem based on ISSUER_SOURCE
RUN if [ "$ISSUER_SOURCE" = "published" ]; then \
      echo "Installing issuer from RubyGems..." && \
      gem install issuer; \
    else \
      echo "Will install issuer from repository source..."; \
    fi

# Set app directory for build context (only needed for repo builds)
WORKDIR /app

# Copy repository source and build gem (only when ISSUER_SOURCE=repo)
COPY . .
RUN if [ "$ISSUER_SOURCE" = "repo" ]; then \
      gem install rake && \
      gem build issuer.gemspec && \
      gem install issuer-*.gem && \
      rm -rf /app/*; \
    fi

# Ensure gem executables are in PATH
ENV PATH="/usr/local/bundle/bin:$PATH"

# Set runtime working dir to isolated mount point
WORKDIR /workdir

# Default entrypoint and fallback command
ENTRYPOINT ["issuer"]
CMD ["help"]