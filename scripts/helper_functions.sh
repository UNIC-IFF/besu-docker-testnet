#!/bin/bash

VAL_NAME_PREFIX_DEFAULT="validator-"
OUTPUT_DIR_DEFAULT="./validators-config/"

IPS_FILENAME="ips_fixed.lst"
VALIDATORS_MAP_FILENAME="validators-map.json"

WORKING_DIR=${WORKING_DIR:-$(realpath ./)}
TEMPLATES_DIR=${TEMPLATES_DIR:-$(realpath ./templates/)}
COMPOSE_FILENAME=${COMPOSE_FILENAME:-"docker-compose.yml"}
#PEER_PORT=${PEER_PORT:-51235}
VAL_NAME_PREFIX=${VAL_NAME_PREFIX:-VAL_NAME_PREFIX_DEFAULT}
OUTPUT_DIR=${OUTPUT_DIR:-${OUTPUT_DIR_DEFAULT}}

function validator_service()
{
	valnum=$1
        val_deploy_path=${OUTPUT_DIR}/${VAL_NAME_PREFIX}${valnum}
	sed -e "s/\${VAL_ID}/$valnum/g" \
            -e "s/\${VAL_NAME_PREFIX}/${VAL_NAME_PREFIX}/g" \
            -e "s#\${LOCAL_BESU_DEPLOY_PATH}#$val_deploy_path#g" \
		${TEMPLATES_DIR}/validator-template.yml | sed -e $'s/\\\\n/\\\n    /g'

#    -e "s/\${PEER_PORT}/${PEER_PORT}/g" 

}

function dockercompose_testnet_generator ()
{
	num_of_validators=$1
	configfiles_root_path=$2

	# cp ${TEMPLATES_DIR}/docker-compose-genesis-template.yml ${WORKING_DIR}/${COMPOSE_FILE}
  # replace peer-port and validator name prefix in template file
#    -e "s/\${PEER_PORT}/${PEER_PORT}/g" \
#  sed  -e "s/\${VAL_NAME_PREFIX}/${VAL_NAME_PREFIX}/g" \

	cat ${TEMPLATES_DIR}/docker-compose-testnet-template.yml  > ${WORKING_DIR}/${COMPOSE_FILENAME}

	for (( i=0;i<${num_of_validators};i++ ))
	do
		echo "$(validator_service $i)" >> ${WORKING_DIR}/${COMPOSE_FILENAME}
	done
}


function check_and_create_output_dirs(){
	if [[ ! -d $OUTPUT_DIR ]] ; then
		echo "Output director does not exist. Creating....";
		mkdir -p $OUTPUT_DIR
	fi;
}

function generate_validator_configuration() {
	DOCKER_OUTPUT_DIR="./$(basename $OUTPUT_DIR)/"
  # Arguments
	val_id=$1
	set -x;

	# It is running in local machine, so no use of DOCKER_OUTPUT_DIR
	out_keys="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/validator-keys.json"
	out_token="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/validator-token.txt"
	out_cfg="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/rippled.cfg"
	out_inetd_cfg="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/inetd.conf"
	out_validators="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/validators.txt"

	# echo statsd ip: $(docker container inspect statsd_graphite | jq -r .[0].NetworkSettings.Networks.${TESTNET_NAME}.IPAddress):8125

	# Read all validator keys and list them
	all_validator_keys=$(cat  ${OUTPUT_DIR}/${VALIDATORS_MAP_FILENAME} | jq '.[]' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\"//g')
	
	if [[ "$val_id" == "genesis" ]]; then
		#It's genesis node
		# replace  ips_fixed and validator token in cfg file
		sed -e "s#\${VALIDATOR_TOKEN}#$(tail -n 12 ${out_token} | sed -e ':a;N;$!ba;s/\n/\\n/g;s/\#/\\#/g')#" \
			-e "s#\${IPS_FIXED}#$(cat ${OUTPUT_DIR}/${IPS_FILENAME} | sed -e ':a;N;$!ba;s/\n/\\n/g')#" \
	        -e "s#\${PEER_PORT}#${PEER_PORT}#g" \
            -e "s#\${VALIDATOR_NAME}#${VAL_NAME_PREFIX:: -1}_${val_id}#g" \
            ${CONFIG_TEMPLATE_DIR}/rippled_genesis_template.cfg > ${out_cfg}
		    # -e "s#\${PRIVATE_IP}#${PRIV_IP}#g" \

#		sed -e "s#\${MONITORING_STATSD_ADDRESS}#${MONITORING_STATSD_ADDRESS}#g" \
#            ${CONFIG_TEMPLATE_DIR}/inetd-template.conf > ${out_inetd_cfg}

		sed -e "s#\${VALIDATORS_PUBLIC_KEYS}#${all_validator_keys}#" \
			${CONFIG_TEMPLATE_DIR}/validators_txt_template.txt > ${out_validators}
	else
		#It's validator node
		# replace  validator key and validator token in cfg file
		sed -e "s#\${VALIDATOR_TOKEN}#$(tail -n 12 ${out_token} | sed -e ':a;N;$!ba;s/\n/\\n/g;s/\#/\\#/g')#" \
			-e "s#\${IPS_FIXED}#$(cat ${OUTPUT_DIR}/${IPS_FILENAME} | sed -e ':a;N;$!ba;s/\n/\\n/g')#" \
            -e "s#\${PEER_PORT}#${PEER_PORT}#g" \
            -e "s#\${VALIDATOR_NAME}#${VAL_NAME_PREFIX:: -1}_${val_id}#g" \
			${CONFIG_TEMPLATE_DIR}/rippled_template.cfg > ${out_cfg}
            #-e "s#\${PRIVATE_IP}#${PRIV_IP}#g" \
        
#		sed -e "s#\${MONITORING_STATSD_ADDRESS}#${MONITORING_STATSD_ADDRESS}#g" \
#            ${CONFIG_TEMPLATE_DIR}/inetd-template.conf > ${out_inetd_cfg}
			
		sed -e "s#\${VALIDATORS_PUBLIC_KEYS}#${all_validator_keys}#" \
			${CONFIG_TEMPLATE_DIR}/validators_txt_template.txt > ${out_validators}
	fi;
	set +x;
}

function update_global_files()
{
	val_id=$1
	out_keys="${OUTPUT_DIR}/${VAL_NAME_PREFIX}${val_id}/validator-keys.json"

	# append ips in ips_fixed file
	echo "${VAL_NAME_PREFIX}${val_id}  ${PEER_PORT}" >> ${OUTPUT_DIR}/${IPS_FILENAME}

	# recreate the validators_map file
	cat ${OUTPUT_DIR}/${VALIDATORS_MAP_FILENAME} | jq ". + {\"${VAL_NAME_PREFIX}${val_id}\": $(cat ${out_keys} | jq '.public_key')}" > ${OUTPUT_DIR}/${VALIDATORS_MAP_FILENAME}

}

function update_global_files_for_all()
{
        VAL_NUM=$1
        echo "Updating global files for all the validators..."
	update_global_files "genesis"
 
	for ((i=0 ; i < ${VAL_NUM} ; i++)); do
		update_global_files $i
	done

}


function generate_keys_and_configs()
{
        check_and_create_output_dirs

	#clean up
	#rm -f ${OUTPUT_DIR}/${IPS_FILENAME}
	echo "" > ${OUTPUT_DIR}/${IPS_FILENAME}
	#rm -f ${OUTPUT_DIR}/${VALIDATORS_MAP_FILENAME}
	echo {} > ${OUTPUT_DIR}/${VALIDATORS_MAP_FILENAME}
	VAL_NUM=$1
#################
        # keys are generated on first boot of BESU client without a key in the data path
#        echo "Generating keys for genesis"
#	generate_validator_keys "genesis"
#	update_global_files "genesis"
 
#	echo "Generating keys for validators..."
#	for ((i=0 ; i < ${VAL_NUM} ; i++)); do
#		echo "    Generating keys for validator $i"
#		generate_validator_keys $i
#		update_global_files $i
#	done
###########

       echo "Generating configuration files for the genesis..."
	generate_validator_configuration "genesis"

	echo "Generating configuration files for the validators..."

	for ((i=0 ; i < ${VAL_NUM} ; i++)); do
		echo "    Generating configuration for validator $i"
		generate_validator_configuration $i
	done

       
}
