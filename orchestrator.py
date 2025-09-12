import os
import json
import logging
import log
import boto3
from config import Config
from chat_message import ChatMessage

runtime = boto3.client("bedrock-agentcore")


def orchestrate(conversation_history, new_question):
    """Orchestrates RAG workflow based on conversation history
    and a new question. Returns an answer and a list of
    source documents."""

    payload_data = {
        "input": {
            "user_id": conversation_history["userId"],
            "prompt": new_question,
        }
    }
    payload = json.dumps(payload_data)

    request = {
        "agentRuntimeArn": Config.AGENT_RUNTIME,
        "payload": payload,
        "runtimeUserId": conversation_history["userId"],
        "runtimeSessionId": conversation_history["conversationId"],
        "contentType": "application/json",
    }
    log.info(request)

    # Call invoke_agent_runtime
    response = runtime.invoke_agent_runtime(**request)

    # Handle the response
    status_code = response["statusCode"]
    logging.info(f"Status Code: {status_code}")
    if status_code != 200:
        raise Exception(f"Agent runtime returned an http {status_code}")

    # The response body is a StreamingBody object
    response_body = response["response"].read().decode("utf-8")
    logging.info(f"Response Body: {response_body}")

    msg = ChatMessage.from_json(response_body)
    return msg.get_text_content(), []
