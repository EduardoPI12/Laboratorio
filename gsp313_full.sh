#!/bin/bash

# Colores
BLACK=`tput setaf 0`; RED=`tput setaf 1`; GREEN=`tput setaf 2`; YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`; MAGENTA=`tput setaf 5`; CYAN=`tput setaf 6`; WHITE=`tput setaf 7`
BG_MAGENTA=`tput setab 5`; BG_GREEN=`tput setab 2`; BG_RED=`tput setab 1`; BOLD=`tput bold`; RESET=`tput sgr0`

echo "${BG_MAGENTA}${BOLD}🚀 Iniciando ejecución del script para el Lab GSP313${RESET}"

# -------------------- TAREA 1: Crear 3 VMs -----------------------
echo "${CYAN}🔧 Creando instancias web1, web2, web3 con Apache...${RESET}"
for NAME in web1 web2 web3; do
  gcloud compute instances create $NAME \
    --zone=$ZONE \
    --machine-type=e2-small \
    --tags=network-lb-tag \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y apache2
service apache2 start
echo "<h3>Web Server: '"$NAME"'</h3>" > /var/www/html/index.html'
done
echo "${GREEN}${BOLD}✅ Tarea 1 completada: VMs creadas con Apache${RESET}"

# -------------------- TAREA 2: Balanceador de red -----------------------
echo "${CYAN}🌐 Configurando balanceador de red...${RESET}"

gcloud compute firewall-rules create $FIREWALL \
  --allow tcp:80 \
  --target-tags=network-lb-tag \
  --direction=INGRESS \
  --network=default

gcloud compute addresses create network-lb-ip-1 --region=$REGION

gcloud compute target-pools create www-pool --region=$REGION

gcloud compute target-pools add-instances www-pool \
  --instances=web1,web2,web3 \
  --zone=$ZONE

gcloud compute forwarding-rules create network-lb-forwarding-rule \
  --region=$REGION \
  --ports=80 \
  --address=network-lb-ip-1 \
  --target-pool=www-pool

echo "${GREEN}${BOLD}✅ Tarea 2 completada: Balanceador de red listo${RESET}"

# -------------------- TAREA 3: Balanceador HTTP -----------------------
echo "${CYAN}🧱 Configurando balanceador HTTP (L7)...${RESET}"

cat << EOF > startup.sh
#! /bin/bash
apt-get update
apt-get install -y apache2
hostname > /var/www/html/index.html
EOF

gcloud compute instance-templates create lb-backend-template \
  --metadata-from-file startup-script=startup.sh \
  --machine-type=e2-medium \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --tags=allow-health-check

gcloud compute instance-groups managed create lb-backend-group \
  --template=lb-backend-template \
  --size=2 \
  --zone=$ZONE

gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --allow tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check

gcloud compute health-checks create http http-basic-check \
  --port 80

gcloud compute instance-groups managed set-named-ports lb-backend-group \
  --named-ports=http:80 \
  --zone=$ZONE

gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --health-checks=http-basic-check \
  --port-name=http \
  --global

gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global

gcloud compute url-maps create web-map-http \
  --default-service=web-backend-service

gcloud compute target-http-proxies create http-lb-proxy \
  --url-map=web-map-http

gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global

gcloud compute forwarding-rules create http-content-rule \
  --address=lb-ipv4-1 \
  --global \
  --target-http-proxy=http-lb-proxy \
  --ports=80

echo "${GREEN}${BOLD}✅ Tarea 3 completada: Balanceador HTTP operativo${RESET}"

# -------------------- Mostrar IPs finales -----------------------
echo ""
echo "${YELLOW}${BOLD}🌍 IP pública del Balanceador de Red (Layer 4):${RESET}"
gcloud compute addresses describe network-lb-ip-1 --region=$REGION --format="value(address)"
echo ""
echo "${YELLOW}${BOLD}🌍 IP pública del Balanceador HTTP (Layer 7):${RESET}"
gcloud compute addresses describe lb-ipv4-1 --global --format="value(address)"

echo ""
echo "${BG_GREEN}${BOLD}🎉 LAB COMPLETADO EXITOSAMENTE. ¡Revisa tu puntuación en Qwiklabs!${RESET}"
