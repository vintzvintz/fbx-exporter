#!/bin/bash

# Script de restauration pour les données Prometheus et Grafana
# Usage: ./restore.sh <backup_name.tar.gz>

set -e

if [ $# -eq 0 ]; then
    echo "❌ Usage: $0 <backup_name.tar.gz>"
    echo "📋 Sauvegardes disponibles:"
    ls -1 backups/*.tar.gz 2>/dev/null || echo "   Aucune sauvegarde trouvée"
    exit 1
fi

BACKUP_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vérifier que le fichier de sauvegarde existe
if [[ ! "$BACKUP_FILE" = /* ]]; then
    BACKUP_FILE="$SCRIPT_DIR/backups/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Fichier de sauvegarde introuvable: $BACKUP_FILE"
    exit 1
fi

echo "🔄 Restauration depuis: $BACKUP_FILE"

# Arrêter les services
echo "⏹️  Arrêt des services..."
docker compose stop

# Sauvegarder les données actuelles
echo "💾 Sauvegarde des données actuelles..."
BACKUP_CURRENT="backups/before_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
mkdir -p backups
tar -czf "$BACKUP_CURRENT" data/ 2>/dev/null || true

# Supprimer les données actuelles
echo "🗑️  Suppression des données actuelles..."
rm -rf data/prometheus/* data/grafana/* 2>/dev/null || true

# Restaurer depuis la sauvegarde
echo "📦 Extraction de la sauvegarde..."
tar -xzf "$BACKUP_FILE" -C .

# Redémarrer les services
echo "▶️  Redémarrage des services..."
docker compose up -d

echo "✅ Restauration terminée!"
echo "💾 Données précédentes sauvegardées dans: $BACKUP_CURRENT"