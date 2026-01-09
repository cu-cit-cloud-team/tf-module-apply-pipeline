# /bin/bash
#
# Post-process the results of a Terraform plan (drift) to determine if there are
# any changes to be applied. If no changes, stop the CodePipeline execution.
#

echo "Plan exit code: $PLAN_EXIT"

if [ $PLAN_EXIT -eq 0 ]; then
    echo "No changes to be applied. Stopping pipeline execution."
    PIPELINE_NAME=${CODEBUILD_INITIATOR#codepipeline/}

    echo "Pipeline name is $PIPELINE_NAME"

    QUERY="stageStates[?actionStates[?latestExecution.externalExecutionId=='${CODEBUILD_BUILD_ID}']].latestExecution.pipelineExecutionId"
    EXECUTION_ID=$(aws codepipeline get-pipeline-state --name ${PIPELINE_NAME} --query "$QUERY" --output text)

    echo "Execution ID is $EXECUTION_ID"

    aws codepipeline stop-pipeline-execution \
        --pipeline-name $PIPELINE_NAME \
        --pipeline-execution-id $EXECUTION_ID \
        --no-abandon \
        --reason "No changes to be applied. Stopping pipeline execution."

elif [ $PLAN_EXIT -eq 2 ]; then
    echo "Changes need to be applied."
    exit 0
else
    echo "Error"
    exit $PLAN_EXIT
fi
