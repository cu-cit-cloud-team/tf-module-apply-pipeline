# /bin/bash
#
# Drift check Terraform resources, but ignore drift in specific resources
# as defined in the .driftignore file.

export TF_IN_AUTOMATION=true
export TF_RECREATE_MISSING_LAMBDA_PACKAGE=false
export LOG_JSON_FILE=plan.log.json
export ALL_RESOURCES_FILE=plan.all-resources.txt
export DRIFTED_RESOURCES_FILE=plan.drifted-resources.txt
export IGNORE_FILE=plan.ignore-resources.txt
export FINAL_RESOURCES_FILE=plan.final-resources.txt

# Don't exit on non-zero exit codes from terraform plan
set +e

terraform plan \
    -detailed-exitcode \
    -lock=false \
    -input=false \
    -no-color \
    -json > $LOG_JSON_FILE
exitcode=$?

# Switch back to exiting on errors
set -e

if [ $exitcode -eq 0 ]; then

  msg="No drift detected."

elif [ $exitcode -eq 1 ]; then

  msg="Error encountered while running Terraform drift check."

elif [ $exitcode -eq 2 ]; then

  # Terraform plan detected changes
  RESOURCE_COUNT=$(/tmp/scripts/drift-resource-count.sh)
  if [ $RESOURCE_COUNT -gt 0 ]; then
    msg="Terraform configuration drift detected on $RESOURCE_COUNT resources."
    # Leave the exit code as 2 to indicate drift detected on non-ignored resources
  else
    # Set the exit code to 0 since the only drift was on ignored resources
    msg="No drift detected, excluding ignored resources."
    exitcode=0
  fi

else
  msg="Unknown exit code encountered."
fi

echo $msg
exit $exitcode
