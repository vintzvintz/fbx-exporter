# FBX Exporter - Production Deployment

Production-ready Docker Compose stack for Freebox monitoring with Prometheus and Grafana. Designed for hobby users with VPS deployment and Traefik integration.

## Overview

This deployment provides:
- **Freebox Exporter**: Collects metrics from your Freebox router
- **Prometheus**: Stores and queries metrics data
- **Grafana**: Visualizes metrics with dashboards
- **Docker Secrets**: Secure credential management
- **Traefik Integration**: SSL termination and routing
- **Health Checks**: Automatic service monitoring

## Deployment Strategy

### Recommended Architecture
- **Development**: Linux home PC using `dev/` environment
- **Production**: VPS with existing Traefik setup
- **Repository**: GitHub for code and config templates
- **Secrets**: Local/VPS only (never in Git)

### VPS Directory Structure
```
/opt/fbx-exporter/
├── docker-compose.yml          # From this repo
├── .env                       # Production config
├── secrets/                   # Docker secrets (gitignored)
│   ├── freebox_token.json
│   ├── grafana_admin_user.txt
│   └── grafana_admin_password.txt
└── update.sh                  # Deployment script
```

## Quick Deployment

### 1. VPS Setup
```bash
# Create deployment directory
sudo mkdir -p /opt/fbx-exporter
cd /opt/fbx-exporter

# Clone repository
git clone https://github.com/vintzvintz/fbx-exporter.git .
cd prod/
```

### 2. Configure Secrets
```bash
# Copy example files
cp secrets/freebox_token.json.example secrets/freebox_token.json
cp secrets/grafana_admin_user.txt.example secrets/grafana_admin_user.txt
cp secrets/grafana_admin_password.txt.example secrets/grafana_admin_password.txt

# Generate Freebox token (on local PC with Freebox access)
# Transfer freebox_token.json to VPS securely
scp freebox_token.json user@vps:/opt/fbx-exporter/prod/secrets/freebox_token.json

# Set Grafana credentials
echo "admin" > secrets/grafana_admin_user.txt
echo "$(openssl rand -base64 32)" > secrets/grafana_admin_password.txt

# Secure permissions
chmod 600 secrets/*
sudo chown root:docker secrets/
```

### 3. Traefik Integration
```bash
# Add to docker-compose.yml or create override
cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  grafana:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fbx-grafana.rule=Host(\`fbx.yourdomain.com\`)"
      - "traefik.http.routers.fbx-grafana.tls.certresolver=letsencrypt"
      - "traefik.http.services.fbx-grafana.loadbalancer.server.port=3000"
    networks:
      - traefik
      - fbx-export

networks:
  traefik:
    external: true
EOF
```

### 4. Deploy Stack
```bash
# Optional: customize configuration
cp .env.example .env && nano .env

# Deploy services
docker-compose up -d

# Verify deployment
docker-compose ps
```

### 5. Access Services
- **Grafana**: `https://fbx.yourdomain.com` (via Traefik)
- **Metrics**: Internal only (accessible by Prometheus)
- **Prometheus**: Internal only (accessible through Grafana)

## Configuration

### Environment Variables
Customize via `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_PORT` | 3000 | Grafana web interface port |
| `PROMETHEUS_RETENTION_TIME` | 30d | Data retention period |
| `DOCKER_NETWORK_NAME` | fbx-export-prod | Internal network name |
| `FBX_EXPORTER_IMAGE_TAG` | latest | Docker image version |

### Docker Secrets
Sensitive data is managed via Docker secrets:

| Secret | File | Purpose |
|--------|------|---------|
| `freebox_token` | `secrets/freebox_token.json` | Freebox API authentication |
| `grafana_admin_user` | `secrets/grafana_admin_user.txt` | Grafana username |
| `grafana_admin_password` | `secrets/grafana_admin_password.txt` | Grafana password |

### Traefik Labels
For external access through Traefik:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.fbx-grafana.rule=Host(\`fbx.yourdomain.com\`)"
  - "traefik.http.routers.fbx-grafana.tls.certresolver=letsencrypt"
  - "traefik.http.services.fbx-grafana.loadbalancer.server.port=3000"
```

## Security Features

- **No External Metrics Port**: Only accessible internally
- **Docker Secrets**: File-based secret mounting
- **Network Isolation**: Services communicate via internal networks
- **Traefik SSL**: Automatic HTTPS with Let's Encrypt
- **Git Protection**: Actual secret files never committed
- **Permission Control**: 600 permissions on secret files

## Operations

### Development Workflow
```bash
# On local PC (development)
cd dev/
docker-compose up -d  # Development environment

# Test changes locally
# Commit and push to GitHub
git add . && git commit -m "feature: ..." && git push
```

### Production Updates
```bash
# On VPS
cd /opt/fbx-exporter/prod/
git pull origin main
docker-compose pull
docker-compose up -d --remove-orphans
```

### Monitoring
```bash
# Service status
docker-compose ps

# Live logs
docker-compose logs -f

# Traefik logs
docker logs traefik | grep fbx

# Individual service logs
docker-compose logs freebox-exporter
```

### Maintenance
```bash
# Update script
cat > update.sh << 'EOF'
#!/bin/bash
cd /opt/fbx-exporter/prod/
git pull
docker-compose pull
docker-compose up -d --remove-orphans
echo "Deployment updated successfully"
EOF
chmod +x update.sh

# Run updates
./update.sh
```

### Backup
```bash
# Backup Prometheus data
docker run --rm -v prod_prometheus_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz -C /data .

# Backup Grafana data (including dashboards)
docker run --rm -v prod_grafana_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/grafana-$(date +%Y%m%d).tar.gz -C /data .

# Backup secrets (encrypted)
tar czf secrets-backup-$(date +%Y%m%d).tar.gz secrets/
gpg --symmetric secrets-backup-$(date +%Y%m%d).tar.gz
rm secrets-backup-$(date +%Y%m%d).tar.gz
```

## Token Management

### Initial Token Generation
```bash
# On local PC (requires physical Freebox access)
cd fbx-exporter/
go run . freebox_token.json

# Accept authorization on Freebox device
# Transfer token securely to VPS
scp freebox_token.json user@vps:/opt/fbx-exporter/prod/secrets/freebox_token.json
```

### Token Rotation
```bash
# Generate new token locally
go run . new_freebox_token.json

# Update VPS
scp new_freebox_token.json user@vps:/opt/fbx-exporter/prod/secrets/freebox_token.json
ssh user@vps "cd /opt/fbx-exporter/prod && docker-compose restart freebox-exporter"
```

## Troubleshooting

### Connection Issues
```bash
# Test Freebox connectivity from VPS
docker-compose exec freebox-exporter wget -q --spider http://mafreebox.freebox.fr

# Check token validity
docker-compose logs freebox-exporter | grep -i "auth\|token\|error"

# Test from local network (if VPS is external)
# May need VPN or port forwarding for external VPS access to local Freebox
```

### Service Problems
```bash
# Debug mode
# Edit docker-compose.yml, add "-debug" to freebox-exporter command
docker-compose up -d freebox-exporter

# Health check status
docker inspect --format='{{.State.Health.Status}}' freebox-exporter

# Traefik routing issues
docker logs traefik | grep fbx
```

### Common Fixes
| Problem | Solution |
|---------|----------|
| Permission denied | `chmod 600 secrets/*` |
| Service won't start | Check `docker-compose logs [service]` |
| Metrics empty | Verify token validity and Freebox connectivity |
| Can't access via Traefik | Check domain DNS and Traefik labels |
| External VPS can't reach Freebox | Setup VPN or port forwarding |

## Advanced Deployment Options

### CI/CD with GitHub Actions
```yaml
# .github/workflows/deploy.yml
name: Deploy to VPS
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to VPS
        uses: appleboy/ssh-action@v0.1.5
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /opt/fbx-exporter/prod
            git pull
            docker-compose pull
            docker-compose up -d --remove-orphans
```


### Multiple Freebox Support
```bash
# Create separate deployments
mkdir -p /opt/fbx-exporter/{home,office}
# Deploy with different tokens and domains
```

## Network Considerations

### External VPS Access to Local Freebox
If your VPS is external and needs to access a local Freebox:

1. **VPN Solution** (Recommended):
   ```bash
   # Setup WireGuard/OpenVPN on home network
   # Connect VPS to home network via VPN
   ```

2. **Port Forwarding**:
   ```bash
   # Forward Freebox API port (80/443) through router
   # Security risk - not recommended
   ```

3. **Reverse SSH Tunnel**:
   ```bash
   # From home PC, create tunnel to VPS
   ssh -R 8080:mafreebox.freebox.fr:80 user@vps
   # Configure exporter to use localhost:8080
   ```

## Architecture Details

### Service Dependencies
```
freebox-exporter (healthy)
    ↓
prometheus (scrapes metrics)
    ↓
grafana (visualizes data)
    ↓
traefik (external access)
```

### Data Flow
1. **Exporter** connects to Freebox API using token
2. **Prometheus** scrapes metrics from exporter every 30s
3. **Grafana** queries Prometheus for dashboard data
4. **Traefik** provides SSL termination and routing
5. **Users** access dashboards via `https://fbx.yourdomain.com`

### Network Layout
- **External**: Traefik → Grafana (HTTPS)
- **Internal**: Grafana ↔ Prometheus ↔ Exporter
- **Secrets**: Read-only mounts at `/run/secrets/`

## Best Practices

### Repository Management
- ✅ Store code and configuration templates in GitHub
- ✅ Use environment variables for configuration
- ✅ Version control deployment documentation
- ❌ Never commit real secrets or tokens
- ❌ Avoid storing production .env files in Git

### Security
- Use Docker secrets for all sensitive data
- Implement regular secret rotation
- Monitor access logs and failed attempts
- Keep services internal unless external access needed
- Use Traefik for SSL termination and routing

### Maintenance
- Regular updates via Git pull + Docker pull
- Automated backups of data volumes
- Health monitoring and alerting
- Log rotation and cleanup

## Support

- **Repository**: https://github.com/vintzvintz/fbx-exporter
- **Issues**: https://github.com/vintzvintz/fbx-exporter/issues
- **Freebox API**: https://dev.freebox.fr/sdk/os/
- **Traefik Docs**: https://doc.traefik.io/traefik/