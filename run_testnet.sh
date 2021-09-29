#!/bin/bash

WORKING_DIR=${WORKING_DIR:-$(realpath ./)}
TEMPLATES_DIR=${TEMPLATES_DIR:-$(realpath ./templates/)}
COMPOSE_FILENAME=${COMPOSE_FILENAME:-"docker-compose-testnet.yaml"}
OUTPUT_DIR=${OUTPUT_DIR:-$(realpath ./configfiles)}
VAL_NAME_PREFIX=${VAL_NAME_PREFIX:-"validator-"}
#PEER_PORT=${PEER_PORT:-51235}

IMAGE_TAG=${IMAGE_TAG:-"latest"}
TESTNET_NAME=${TESTNET_NAME:-"eth_testnet"}

VAL_NUM=${1:-3}

source scripts/helper_functions.sh

dockercompose_testnet_generator ${VAL_NUM} ${OUTPUT_DIR}

docker network create ${TESTNET_NAME}

#run testnet
echo "Starting the testnet..."

TESTNET_NAME=${TESTNET_NAME} CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${WORKING_DIR}/${COMPOSE_FILENAME} up -d

echo "Waiting for everything goes up..."
sleep 10
