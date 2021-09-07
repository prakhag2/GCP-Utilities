# Load balancers in GCP have a lot of moving parts such as
# backend services, target pools, proxies etc. 
# This script cpnsolidates information across all the
# channels and outputs a JSON response that's inline 
# with the consolidated output users see on GCP UI Console.

#!/bin/bash

log="/tmp/log"
GCLOUD_FWD_RULES=$(gcloud compute forwarding-rules list --format json)

# Create a simple JSON object
createLBRecord(){
  jq -n --arg target "$1" \
        --arg name "$2" \
        --arg loadbalancingScheme "$3" \
        --arg protocol "$4" \
        '{"target": $target, "name": $name, "loadbalancingScheme": $loadbalancingScheme, "protocol": $protocol}'
}

# Consolidate results
# Find duplicate proxies/backend services and 
# merge them under a common parent object
mergeAndGetLBs(){
  jq 'group_by( [.name, .loadbalancingScheme])
                | map((.[0]|del(.target, .protocol))
                + { target: (map(.target)) }
                + { protocol: (map(.protocol)) })
                | [.[]|{name, loadbalancingScheme, target, "protocol": [.protocol[]] | unique}]' $log
}

# Get http proxies
echo "Collecting information from HTTP Proxies..."
gcloud compute target-http-proxies list > $log
tmp1=$(while IFS=$'\t' read -r LINE ; do
         target=$(echo $LINE | awk -F " " '{print $1}')
         lbName=$(echo $LINE | awk -F " " '{print $2}')
         fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.target != null) | select(.target | endswith("'${target}'"))')
         echo $fwdRules | jq -c '.'  | while read RULE; do
	   target=$(echo $RULE | jq '.target')
           loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
           protocol="HTTP"
	   createLBRecord $target $lbName $loadbalancingScheme $protocol
         done
       done < <(sed '1d' $log) | jq -n '. |= [inputs]')

# Get https proxies
echo "Collecting information from HTTPS Proxies..."
gcloud compute target-https-proxies list > $log
tmp2=$(while IFS=$'\t' read -r LINE ; do
         target=$(echo $LINE | awk -F " " '{print $1}')
         lbName=$(echo $LINE | awk -F " " '{print $3}')
         fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.target != null) | select(.target | endswith("'${target}'"))')
         echo $fwdRules | jq -c '.' | while read RULE; do
	   target=$(echo $RULE | jq '.target')
           loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
           protocol="HTTPS"
	   createLBRecord $target $lbName $loadbalancingScheme $protocol
	 done
       done < <(sed '1d' $log) | jq -n '. |= [inputs]')

# Consolidate results
echo $tmp1 $tmp2 | jq -s add > $log
lb1=$(mergeAndGetLBs)

# Get TCP proxies
echo "Collecting information from TCP Proxies..."
gcloud compute target-tcp-proxies list > $log
tmp1=$(while IFS=$'\t' read -r LINE ; do
          target=$(echo $LINE | awk -F " " '{print $1}')
          lbName=$(echo $LINE | awk -F " " '{print $3}')
          fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.target != null) | select(.target | endswith("'${target}'"))')
          echo $fwdRules | jq -c '.' | while read RULE; do
	    target=$(echo $RULE | jq '.target')
            loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
	    protocol="TCP(Proxy)"
	    createLBRecord $target $lbName $loadbalancingScheme $protocol
          done  
        done < <(sed '1d' $log) | jq -n '. |= [inputs]')

# Get SSL proxies
echo "Collecting information from SSL Proxies..."
gcloud compute target-ssl-proxies list > $log
tmp2=$(while IFS=$'\t' read -r LINE ; do
         target=$(echo $LINE | awk -F " " '{print $1}')
         lbName=$(echo $LINE | awk -F " " '{print $3}')
         fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.target != null) | select(.target | endswith("'${target}'"))')
         echo $fwdRules | jq -c "." | while read RULE; do
	   target=$(echo $RULE | jq '.target')
           loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
	   protocol="SSL(Proxy)"
	   createLBRecord $target $lbName $loadbalancingScheme $protocol
	 done
       done < <(sed '1d' $log) | jq -n '. |= [inputs]')

# Consolidate results
echo $tmp1 $tmp2 | jq -s add > $log
lb2=$(mergeAndGetLBs)

# Get target pools
echo "Collecting information from Target Pools..."
gcloud compute target-pools list > $log
tmp=$(while IFS=$'\t' read -r LINE ; do
        target=$(echo $LINE | awk -F " " '{print $1}')
        lbName=$(echo $LINE | awk -F " " '{print $1}')
        fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.target != null) | select(.target | endswith("'${target}'"))')
	echo $fwdRules | jq -c '.'  | while read RULE; do
	  target=$(echo $RULE | jq '.target')
          loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
	  protocol=$(echo $RULE | jq '.IPProtocol')
	  createLBRecord $target $lbName $loadbalancingScheme $protocol
        done
      done < <(sed '1d' $log) | jq -n '. |= [inputs]')

# Consolidate results
echo $tmp > $log
lb3=$(mergeAndGetLBs)

# Get backend services
echo "Collecting information from Backend Services..."
cat /dev/null > $log
fwdRules=$(echo $GCLOUD_FWD_RULES | jq '.[] | select(.backendService != null)')
echo $fwdRules | jq -c '.' | while read RULE; do
    target=$(echo $RULE | jq '.backendService')
    lbName=$(echo $target | awk -F "/" '{print $NF}')
    loadbalancingScheme=$(echo $RULE | jq '.loadBalancingScheme')
    protocol=$(echo $RULE | jq '.IPProtocol')
    createLBRecord $target $lbName $loadbalancingScheme $protocol >> $log
done 

# Consolidate results
echo $(cat $log | jq -s '.') > $log 
lb4=$(mergeAndGetLBs)

# Join all lbs and return result
echo $lb1 $lb2 $lb3 $lb4 | jq -s add
