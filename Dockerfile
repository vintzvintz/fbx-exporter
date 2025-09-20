# Build stage
FROM golang:1.24-alpine3.20 AS builder

# Set working directory
WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN --network=host go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o freebox-exporter .

# Final stage
FROM alpine:3.20

# Create non-root user
RUN adduser -D -s /bin/sh fbxexporter

WORKDIR /home/fbxexporter

# Copy the binary from builder stage
COPY --from=builder /app/freebox-exporter .

# Change ownership to our user
RUN chown fbxexporter:fbxexporter freebox-exporter

# Switch to our user
USER fbxexporter

# Expose the metrics port
EXPOSE 9091

# Run the exporter
ENTRYPOINT ["./freebox-exporter"]
CMD ["/run/secrets/freebox_token"]