#!/bin/bash

# Script de sauvegarde pour les données Prometheus et Grafana
# Usage: ./backup.sh [backup_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="${1:-backup_$TIMESTAMP}"

# Créer le répertoire de sauvegarde
mkdir -p "$BACKUP_DIR"

echo "🔄 Création de la sauvegarde: $BACKUP_NAME"

# Arrêter les services pour garantir la cohérence des données
echo "⏹️  Arrêt des services..."
docker compose stop

# Créer l'archive de sauvegarde
echo "📦 Création de l'archive..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" \
    data/ \
    --exclude='*.tmp' \
    --exclude='*.lock'

# Redémarrer les services
echo "▶️  Redémarrage des services..."
docker compose up -d

echo "✅ Sauvegarde terminée: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "📊 Taille: $(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"