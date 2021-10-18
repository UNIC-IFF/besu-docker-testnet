#!/bin/bash

DEFAULT_ENVFILE="$(dirname $0)/defaults.env"
ENVFILE=${ENVFILE:-"$DEFAULT_ENVFILE"}

source $ENVFILE

### Define or load default variables
WORKING_DIR=$(realpath $(dirname $0))
TEMPLATES_DIR=$(realpath $(dirname $0)/templates/)
COMPOSE_FILENAME=$(dirname $0)/docker-compose-testnet.yaml
SOLO_DOCKER_COMPOSE=$(dirname $0)/docker-compose-test-single.yml
DEPLOYMENT_ROOT=$(dirname $0)/$DEPLOYMENT_ROOT
TEMPLATE_DIR=$(dirname $0)/$TEMPLATE_DIR
OUTPUT_DIR=${DEPLOYMENT_ROOT:-$(realpath $(dirname $0)/configfiles)}
FIXED_IP_PREFIX="192.168.190.1"

###

### Source scripts under scripts directory
. $(dirname $0)/scripts/helper_functions.sh
###


USAGE="$(basename $0) is the main control script for the testnet.
Usage : $(basename $0) <action> <arguments>

Actions:
  start
       Starts a network with <num_validators> 
  configure --bootnodes-num|-bn <num of validators> --val-num|-vn <num of validators>
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
  local_deploy_path=${DEPLOYMENT_ROOT}/${VALIDATORS_NAME_PREFIX}$valnum
  mkdir -p $local_deploy_path
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
  
  bootnodes_list=""
  bootnodes_addrs=""
  echo "">$DEPLOYMENT_ROOT/bootnodes.txt
  for v in "${bootnodes_ids[@]}";
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/${VALIDATORS_NAME_PREFIX}$v
    generate_validator_keys $v
    nodeAddr=$(cat $local_deploy_path/nodeaddress  | python3 -c 'import sys; a=input(); print(a[2:])')
    bootnodes_addrs=$bootnodes_addrs$nodeAddr
    pubkey=$(cat $local_deploy_path/pubkey  | python3 -c 'import sys; a=input(); print(a[2:])')
    bootnode_fixed_ip="${FIXED_IP_PREFIX}$v"
    echo $bootnode_fixed_ip > $local_deploy_path/ipaddress
    echo "# ${VALIDATORS_NAME_PREFIX}$v" >> $DEPLOYMENT_ROOT/bootnodes.txt
    echo "enode://$pubkey@${bootnode_fixed_ip}:30303?discport=30303" >> $DEPLOYMENT_ROOT/bootnodes.txt
    bootnodes_list="$bootnodes_list\"enode://$pubkey@${bootnode_fixed_ip}:30303?discport=30303\", "
  done
  echo Bootnode addresses: $bootnodes_addrs
  echo bootnodes list: $bootnodes_list
  echo $bootnodes_list > $DEPLOYMENT_ROOT/bootnodes.list

 #generating the genesisFile
 sed -e "s/\${CHAIN_ID}/${CHAIN_ID}/g" \
     -e "s/\${BOOTNODE1_ADDRESS}/$bootnodes_addrs/g" \
    ${TEMPLATE_DIR}/cliqueGenesis-template.json > ${DEPLOYMENT_ROOT}/network-genesis.json

 # copy genesis file to all validators
  for v in "${bootnodes_ids[@]}";
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/${VALIDATORS_NAME_PREFIX}$v
    mkdir -p $local_deploy_path/config
    val_ip_addr=$(cat $local_deploy_path/ipaddress)
    cp ${DEPLOYMENT_ROOT}/network-genesis.json $local_deploy_path/config/network-genesis.json
    sed -e "s/\${VALNAME}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s/\${PROMJOB}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s#\${BOOTNODES}#${bootnodes_list}#g" \
        $TEMPLATE_DIR/config-template.toml > $local_deploy_path/config/config.toml
    sed -e "s/\${VALNAME}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s#\${LOCAL_BESU_DEPLOY_PATH}#${local_deploy_path}#g" \
        -e "s#\${IPADDR}#${val_ip_addr}#g" \
        $TEMPLATE_DIR/bootnode-validator-template.yml > $local_deploy_path/validator-service.yml

  done

  
}

function generate_validators_config ()
{
  start_id=$1
  nvals=$2
  end_id=$(($start_id+$nvals))
  #echo "${bootnodes_ids[@]}"

  bootnodes_addrs=""
  for v in $(seq $start_id 1 $end_id);
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/${VALIDATORS_NAME_PREFIX}$v
    generate_validator_keys $v
    #nodeAddr=$(cat $local_deploy_path/nodeaddress  | python3 -c 'import sys; a=input(); print(a[2:])')
  done
  bootnodes_list=$(cat $DEPLOYMENT_ROOT/bootnodes.list)
 # copy genesis file to all validators
  for v in $(seq $start_id 1 $end_id);
  do
    echo $v
    local_deploy_path=${DEPLOYMENT_ROOT}/${VALIDATORS_NAME_PREFIX}$v
    mkdir -p $local_deploy_path/config
    cp ${DEPLOYMENT_ROOT}/network-genesis.json $local_deploy_path/config/network-genesis.json
    sed -e "s/\${VALNAME}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s/\${PROMJOB}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s#\${BOOTNODES}#${bootnodes_list}#g" \
        $TEMPLATE_DIR/config-template.toml > $local_deploy_path/config/config.toml
    sed -e "s/\${VALNAME}/${VALIDATORS_NAME_PREFIX}$v/g" \
        -e "s#\${LOCAL_BESU_DEPLOY_PATH}#${local_deploy_path}#g" \
        $TEMPLATE_DIR/validator-template.yml > $local_deploy_path/validator-service.yml

  done

}


function generate_network_configs()
{
  nbootvals=$1
  nvals=$2
  echo "Generating network configuration for $nbootvals bootnodes and $nvals validators..."
  mkdir -p ${DEPLOYMENT_ROOT} 
  generate_bootnodes_config $(seq 0 1 $(($nbootvals-1)))
  generate_validators_config $nbootvals $nvals
  valdirs=$(find ${DEPLOYMENT_ROOT} -name "validator-service.yml")
  cp $TEMPLATE_DIR/docker-compose-testnet-template.yml ${COMPOSE_FILENAME}
  for v in "${valdirs[@]}"; do
    echo $v
    cat $v >> ${COMPOSE_FILENAME}
  done
#  dockercompose_testnet_generator ${nvals} ${OUTPUT_DIR}
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

  TESTNET_NAME=${TESTNET_NAME} MONITORING_NET=${MONITORING_NET}  CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${COMPOSE_FILENAME} up -d

  echo "Waiting for everything goes up..."
  sleep 10
  echo "  network started!"
}

function stop_network()
{
  echo "Stopping network..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml down
  TESTNET_NAME=${TESTNET_NAME}   MONITORING_NET=${MONITORING_NET}  CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${COMPOSE_FILENAME} down
  echo "  stopped!"
}

function print_status()
{
  echo "Printing status of the  network..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml status
  TESTNET_NAME=${TESTNET_NAME}  MONITORING_NET=${MONITORING_NET}  CONFIGFILES=${OUTPUT_DIR} IMAGE_TAG=${IMAGE_TAG} docker-compose -f ${COMPOSE_FILENAME} ps

  echo "  Finished!"
}

function do_cleanup()
{
  echo "Cleaning up network configuration..."
#  echo ${DEPLOYMENT_ROOT}
  echo ${OUTPUT_DIR}
  #rm -rf ${DEPLOYMENT_DIR}/*
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
      start_network
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
      generate_network_configs $BOOT_VAL_NUM $VAL_NUM
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
