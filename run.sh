#!/bin/bash

DEFAULT_DEPLOYMENT_ROOT_DIR=./deployment-test/
DEFAULT_TEMPLATE_DIR=./templates/

SOLO_DOCKER_COMPOSE=./docker-compose-test-single.yml
DEPLOYMENT_ROOT=${DEPLOYMENT_ROOT:-"$DEFAULT_DEPLOYMENT_ROOT_DIR"}
TEMPLATE_DIR=${TEMPLATE_DIR:-"$DEFAULT_TEMPLATE_DIR"}
CHAIN_ID=${CHAIN_ID:-7071}

VAL_NUM=${1:-3}

function generate_validator_keys ()
{
  # this function is only used for bootnodes bootstrapping.

  valnum=$1
  local_deploy_path=${DEPLOYMENT_ROOT}/validator-$valnum
  #start solo container
  LOCAL_DEPLOY_PATH=$local_deploy_path docker-compose -f $SOLO_DOCKER_COMPOSE up -d

  #generate and export keys and address
  docker exec -it validator-solo besu public-key export --to=/home/besu/pubkey
  docker exec -it validator-solo besu public-key export-address --to=/home/besu/nodeaddress
  # stop container
  LOCAL_DEPLOY_PATH=$local_deploy_path docker-compose -f $SOLO_DOCKER_COMPOSE down
  
}

function generate_bootnodes_config ()
{
  bootnodes_ids=($@)
  echo "${bootnodes_ids[@]}"

  bootnodes_addrs=""
  echo "">$DEPLOYMENT_ROOT/bootnodes.txt
  for v in "${bootnodes_ids[@]}";
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/validator-$v
    generate_validator_keys $v
    nodeAddr=$(cat $local_deploy_path/nodeaddress  | python3 -c 'import sys; a=input(); print(a[2:])')
    bootnodes_addrs=$bootnodes_addrs$nodeAddr
    echo "enode://$nodeAddr@validator-$v:30303?discport=30303">>$DEPLOYMENT_ROOT/bootnodes.txt
  done
  echo $bootnodes_addrs
  
 #generating the genesisFile
 sed -e "s/\${CHAIN_ID}/${CHAIN_ID}/g" \
     -e "s/\${BOOTNODE1_ADDRESS}/$bootnodes_addrs/g" \
    ${TEMPLATE_DIR}/cliqueGenesis-template.json > ${DEPLOYMENT_ROOT}/network-genesis.json

 # copy genesis file to all validators
  for v in "${bootnodes_ids[@]}";
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/validator-$v
    cp ${DEPLOYMENT_ROOT}/network-genesis.json $local_deploy_path/config/network-genesis.json
    sed -e "s/\${VALNAME}/validator-$v/g" \
        -e "s/\${PROMJOB}/besu-validator-$v/g" \
        $TEMPLATE_DIR/config-template.toml > $local_deploy_path/config/config.toml
  done

  
}



##### MAIN

generate_bootnodes_config 0 1 2

docker-compose -f docker-compose-test.yml up -d
