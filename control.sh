#!/bin/bash

DEFAULT_ENVFILE="$(dirname $0)/defaults.env"
ENVFILE=${ENVFILE:-"$DEFAULT_ENVFILE"}

### Define or load default variables
WORKING_DIR=$(realpath $(dirname $0))
TEMPLATES_DIR=$(realpath $(dirname $0)/templates/)
COMPOSE_FILENAME=$(dirname $0)/docker-compose-testnet.yaml
OUTPUT_DIR=$(realpath $(dirname $0)/configfiles)


source $ENVFILE
###

### Source scripts under scripts directory
. $(dirname $0)/scripts/helper_functions.sh
###


USAGE="$(basename $0) is the main control script for the testnet.
Usage : $(basename $0) <action> <arguments>

Actions:
  start     --val-num|-n <num of validators>
       Starts a network with <num_validators> 
  configure --bootnodes-num|-bn <num of validators>
       configures a network with <num_validators> 
  stop
       Stops the running network
  clean
       Cleans up the configuration directories of the network
  status
       Prints the status of the network
        "

function help()
{
  echo "$USAGE"
}

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


function generate_network_configs()
{
  nvals=$1
  echo "Generating network configuration for $nvals validators..."
  dockercompose_testnet_generator ${nvals} ${OUTPUT_DIR}
  echo "  done!"
}

function start_network()
{
  nvals=$1
  echo "Starting network with $nvals validators..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml up -d
  docker network create ${TESTNET_NAME}

  #run testnet
  echo "Starting the testnet..."

  TESTNET_NAME=${TESTNET_NAME} CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${WORKING_DIR}/${COMPOSE_FILENAME} up -d

  echo "Waiting for everything goes up..."
  sleep 10
  echo "  network started!"
}

function stop_network()
{
  echo "Stopping network..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml down
  TESTNET_NAME=${TESTNET_NAME} CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${WORKING_DIR}/${COMPOSE_FILENAME} down
  echo "  stopped!"
}

function print_status()
{
  echo "Printing status of the  network..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml status
  TESTNET_NAME=${TESTNET_NAME} CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${WORKING_DIR}/${COMPOSE_FILENAME} ps

  echo "  Finished!"
}

function do_cleanup()
{
  echo "Cleaning up network configuration..."
  # rm -rf ${DEPLOYMENT_DIR}/*
  rm -rf ${OUTPUT_DIR}/*
  echo "  clean up finished!"
}


ARGS="$@"

if [ $# -lt 1 ]
then
  #echo "No args"
  help
  exit 1
fi

while [ "$1" != "" ]; do
  case $1 in
    "start" ) shift
      while [ "$1" != "" ]; do
        case $1 in 
             -n|--val-num ) shift
               VAL_NUM=$1
               ;;
        esac
        shift
      done
      start_network $VAL_NUM
      exit
      ;;
    "configure" ) shift
      while [ "$1" != "" ]; do
        case $1 in 
             -bn|--bootnodes-num ) shift
               BOOT_VAL_NUM=$1
               ;;
             -vn|--val-num ) shift
               VAL_NUM=$1
               ;;
        esac
        shift
      done
      generate_network_configs $VAL_NUM
      exit
      ;;
    "stop" ) shift
      stop_network
      exit
      ;;
    "status" ) shift
      print_status
      exit
      ;;
    "clean" ) shift
      do_cleanup
      exit
      ;;
  esac
  shift
done
