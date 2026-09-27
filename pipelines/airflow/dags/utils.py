import logging
from airflow.operators.python import get_current_context

def alert_on_failure(context):
    """
    Custom callback function triggered when an Airflow task fails.
    In production, this would send a payload to a Slack webhook or Email API.
    """
    task_instance = context.get('task_instance')
    dag_id = task_instance.dag_id
    task_id = task_instance.task_id
    execution_date = context.get('execution_date')
    exception = context.get('exception')
    
    error_message = (
        f"🚨 DATA PIPELINE ALERT 🚨\n"
        f"DAG: {dag_id}\n"
        f"Task: {task_id}\n"
        f"Execution Date: {execution_date}\n"
        f"Error: {str(exception)}\n"
        f"Action: Pipeline halted. Data Science team notified."
    )
    
    # Log the alert (In production: requests.post(SLACK_WEBHOOK_URL, json={"text": error_message}))
    logging.error(error_message)
    print(error_message) # Ensures it shows up in local console/Airflow logs