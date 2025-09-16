import boto3
import json
import argparse
import uuid
import base64

parser = argparse.ArgumentParser(description="Create an agent runtime")
parser.add_argument("--agent_runtime_arn", required=True, help="Agent runtime arn")
args = parser.parse_args()
agent_runtime_arn = args.agent_runtime_arn
if len(agent_runtime_arn) == 0:
    raise Exception("--agent_runtime_arn is missing")

# Get AWS account ID and region
sts_client = boto3.client("sts")
region = boto3.session.Session().region_name
account = sts_client.get_caller_identity()["Account"]

agent_core_client = boto3.client("bedrock-agentcore")

# Encode user_id with base64 for AgentCore compatibility
user_id = base64.b64encode("test-user".encode()).decode().rstrip('=')

payload = json.dumps({
    "input": {
        "user_id": user_id,
        "prompt": "Who are you and what can you do?"
    }
})

session_id = str(uuid.uuid4())

print(f"invoking agent with session id: {session_id}")
response = agent_core_client.invoke_agent_runtime(
    agentRuntimeArn=agent_runtime_arn,
    runtimeSessionId=session_id,
    runtimeUserId=user_id,
    payload=payload,
)

response_body = response["response"].read()
response_data = json.loads(response_body)
print("Agent Response:", response_data)
