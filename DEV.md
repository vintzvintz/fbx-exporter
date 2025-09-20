# Guide de Développement - Freebox Exporter

Ce document contient les instructions pour le développement local et les tests de l'exporter Prometheus pour Freebox.

## Configuration de l'Environnement de Développement

Un environnement complet avec Prometheus et Grafana est configuré dans `dev/` pour tester l'exporter localement.

### Démarrage des Services

```bash
cd dev
docker compose up -d
```

### Configuration

- **Interface Prometheus** : http://localhost:9090
- **Interface Grafana** : http://localhost:3000 (admin/mot_de_passe_dans_.secrets)
- **Target configurée** : `freebox-exporter:9091` (service Docker interne)
- **Rétention des données** : 2 ans (730 jours)
- **Network Docker** : fbx-export

### Variables d'Environnement

La configuration utilise un fichier `.env` pour personnaliser (copiez `.env.example` vers `.env`) :

```bash
# Versions des images
PROMETHEUS_VERSION=v2.55.1
GRAFANA_VERSION=11.3.1

# Ports
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
FREEBOX_EXPORTER_PORT=9091

# Credentials Grafana
GRAFANA_ADMIN_USER=admin
# Password stored in .secrets/grafana_admin_password.txt

# Rétention et intervalles
PROMETHEUS_RETENTION_TIME=730d
PROMETHEUS_SCRAPE_INTERVAL=15s
FREEBOX_SCRAPE_INTERVAL=30s

# Network
DOCKER_NETWORK_NAME=fbx-export

# Données
PROMETHEUS_DATA_PATH=./data/prometheus
GRAFANA_DATA_PATH=./data/grafana
GRAFANA_PROVISIONING_PATH=./data/grafana/provisioning
```

### Sécurité et Secrets

Les données sensibles sont gérées via Docker secrets :
- **Token Freebox** : Placez votre token dans `dev/.secrets/token.json`
- **Mot de passe Grafana** : Dans `dev/.secrets/grafana_admin_password.txt`

Exemple de structure de token :
```json
{
  "api": {
    "api_domain": "example.fbxos.fr",
    "uid": "00000000000000000000000000000000",
    "https_available": true,
    "https_port": 42513,
    "device_name": "Freebox Server",
    "api_version": "14.0",
    "api_base_url": "/api/",
    "device_type": "FreeboxServer8,1"
  },
  "app_token": "your_app_token_here_64_characters_long"
}
```

### Commandes utiles

```bash
# Premier démarrage : copier la configuration
cp .env.example .env
# Puis configurer vos secrets dans dev/.secrets/

# Construire les images (nécessaire pour freebox-exporter)
cd dev && docker compose build

# Démarrer tous les services
cd dev && docker compose up -d

# Arrêter tous les services
cd dev && docker compose down

# Redémarrer avec rebuild
cd dev && docker compose up -d --build

# Voir les logs
cd dev && docker compose logs -f

# Voir les logs d'un service spécifique
cd dev && docker compose logs -f prometheus
cd dev && docker compose logs -f grafana
cd dev && docker compose logs -f freebox-exporter

# Vérifier le statut des conteneurs
cd dev && docker compose ps

# Vérifier les targets Prometheus
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool

# Vérifier les métriques freebox-exporter
curl -s http://localhost:9091/metrics | grep "^freebox_" | head -10
```

## Environnement de Développement Complet

### Workflow de développement avec Docker

1. **Configuration initiale** :
   ```bash
   # Copier la configuration d'exemple
   cp dev/.env.example dev/.env

   # Créer le répertoire des secrets
   mkdir -p dev/.secrets

   # Configurer le mot de passe Grafana
   echo "votre_mot_de_passe" > dev/.secrets/grafana_admin_password.txt

   # Placer votre token Freebox (voir structure ci-dessus)
   cp token.json dev/.secrets/token.json
   ```

2. **Démarrer l'environnement complet** :
   ```bash
   cd dev
   docker compose build  # Construction initiale
   docker compose up -d  # Démarrage des services
   ```

3. **Accéder aux interfaces** :
   - **Prometheus** : http://localhost:9090
   - **Grafana** : http://localhost:3000 (admin/votre_mot_de_passe)
   - **Métriques freebox-exporter** : http://localhost:9091/metrics

4. **Vérifier le fonctionnement** :
   - Prometheus → Status → Targets → vérifier que freebox-exporter est UP
   - Explorer les métriques `freebox_*` dans Prometheus
   - Créer des dashboards Grafana

### Test de l'Exporter en mode standalone

Pour tester l'exporter hors Docker :

```bash
# Avec un fichier de token existant
go run . token.json

# Ou installation puis exécution
go install
freebox-exporter token.json
```

### Vérification des métriques

```bash
# Vérifier que l'exporter répond
curl http://localhost:9091/metrics

# Compter le nombre de métriques freebox
curl -s http://localhost:9091/metrics | grep "^freebox_" | wc -l

# Exemples de métriques disponibles
curl -s http://localhost:9091/metrics | grep -E "freebox_(uptime|temperature|bandwidth)"
```

## Gestion des Données

### Scripts de Sauvegarde/Restauration

```bash
# Créer une sauvegarde
cd dev && ./backup.sh [nom_optionnel]

# Lister les sauvegardes disponibles
ls dev/backups/

# Restaurer depuis une sauvegarde
cd dev && ./restore.sh backup_20240913_174500.tar.gz
```

### Healthchecks Docker

Les services incluent des healthchecks automatiques :
- **Prometheus** : Vérification de `/-/healthy`
- **Grafana** : Vérification de `/api/health`
- **Dépendances** : Grafana attend que Prometheus soit healthy

## Structure des Fichiers de Développement

```
dev/
├── docker-compose.yml              # Configuration Docker avec 3 services
├── prometheus.yml                  # Configuration Prometheus (scraping freebox-exporter)
├── .env                           # Variables d'environnement (copier depuis .env.example)
├── .env.example                   # Template de configuration
├── .secrets/                      # Secrets Docker (non versionné)
│   ├── token.json                 # Token d'authentification Freebox
│   ├── token-example.json         # Exemple de structure de token
│   └── grafana_admin_password.txt # Mot de passe admin Grafana
└── data/                          # Données persistantes (non versionné)
    ├── prometheus/                # Base de données Prometheus
    └── grafana/                   # Configuration et données Grafana
        └── provisioning/          # Configuration automatique Grafana
            └── datasources/
                └── prometheus.yml # Datasource pointant vers service prometheus
```

### Services Docker

- **prometheus** : Scrape les métriques de freebox-exporter toutes les 30s
- **grafana** : Interface de visualisation avec datasource Prometheus pré-configuré
- **freebox-exporter** : Service buildé depuis le Dockerfile local, utilise les secrets Docker

## Métriques Disponibles

L'exporter expose des métriques avec le préfixe `freebox_` couvrant :

- Métriques système (uptime, température, vitesses des ventilateurs)
- Métriques de connexion (bande passante, octets transférés, stats XDSL/FTTH)
- Statistiques des ports switch et des appareils connectés
- Informations WiFi (points d'accès et stations)
- Découverte d'hôtes LAN et connectivité

## Dépannage

### L'exporter n'apparaît pas dans les targets

- Vérifier que l'exporter est bien démarré sur le port 9091
- Vérifier la connectivité : `curl http://localhost:9091/metrics`
- Vérifier les logs : `cd dev && docker compose logs prometheus`
- Vérifier le healthcheck : `cd dev && docker compose ps`

### Services ne démarrent pas

- Vérifier les ports disponibles : `netstat -tlnp | grep :9090`
- Vérifier les logs : `cd dev && docker compose logs`
- Vérifier les variables d'environnement dans `.env`
- Redémarrer avec rebuild : `cd dev && docker compose up -d --build`

### Grafana ne se connecte pas à Prometheus

- Vérifier que Prometheus est healthy : `curl http://localhost:9090/-/healthy`
- Vérifier le network Docker : `docker network ls | grep fbx-export`
- Vérifier la configuration datasource dans `data/grafana/provisioning/datasources/`

### Problèmes de permissions sur les données

```bash
# Corriger les permissions des répertoires de données
sudo chown -R $USER:$USER dev/data/
chmod -R 755 dev/data/
```

### Erreurs de connexion à la Freebox

- Vérifier le fichier de token
- Vérifier la connectivité réseau vers la Freebox
- Relancer le processus d'autorisation si nécessaire