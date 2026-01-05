#!/bin/bash
#
# This script scans a Terraform plan log file in json format and 
# returns the number of resources that require changes, excluding 
# those that are listed in the plan.ignore-resources.txt file.
#

LOG_JSON_FILE="${LOG_JSON_FILE:-plan.log.json}"
ALL_RESOURCES_FILE="${ALL_RESOURCES_FILE:-plan.all-resources.txt}"
DRIFTED_RESOURCES_FILE="${DRIFTED_RESOURCES_FILE:-plan.drifted-resources.txt}"
IGNORE_FILE="${IGNORE_FILE:-plan.ignore-resources.txt}"
FINAL_RESOURCES_FILE="${FINAL_RESOURCES_FILE:-plan.final-resources.txt}"

# List all resources in the plan
jq -r -c ".hook.resource.addr" $LOG_JSON_FILE | sort | uniq | sed '/null/d' > $ALL_RESOURCES_FILE

# List all resources that require changes
JQ_QUERY='select(.change.actions[0] != "no-op" and .change.actions[0] != "read" and .type == "planned_change") | .change.resource.addr'
jq -r -c "$JQ_QUERY" $LOG_JSON_FILE > $DRIFTED_RESOURCES_FILE

# If IGNORE_FILE doesn't exist, create an empty one
if [ ! -f $IGNORE_FILE ]; then
  touch $IGNORE_FILE
fi

# Remove resources that are listed in the ignore file
grep \
  --fixed-strings \
  --invert-match \
  --file=$IGNORE_FILE $DRIFTED_RESOURCES_FILE \
  > $FINAL_RESOURCES_FILE

# Count and output the remaining resources
cat $FINAL_RESOURCES_FILE | wc --lines
