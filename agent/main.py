from os import getenv
import logging
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from typing import Dict, Any
from datetime import datetime
from strands import Agent
from strands_tools import retrieve
from botocore.config import Config
from bedrock_agentcore.memory import MemoryClient
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager


# Enables Strands debug log level
logging.getLogger("strands").setLevel(logging.DEBUG)

# Sets the logging format and streams logs to stderr
logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s | %(name)s | %(message)s",
    handlers=[logging.StreamHandler()]
)

# print envvars
region = getenv("AWS_REGION")
logging.warning(f"AWS_REGION = {region}")

app_name = getenv("APP_NAME")
logging.warning(f"APP_NAME = {app_name}")

kb_id = getenv("KNOWLEDGE_BASE_ID")
logging.warning(f"KNOWLEDGE_BASE_ID = {kb_id}")

memory_id = getenv("MEMORY_ID")
logging.warning(f"MEMORY_ID = {memory_id}")

retry_config = Config(
    region_name=region,
    retries={
        "max_attempts": 10,  # Increase from default 4 to 10
        "mode": "adaptive"
    }
)

memory_client = MemoryClient(region_name=region)

app = FastAPI(title="AI Agent Accelerator", version="0.1.0")


system_prompt = """
Your name as the AI is "AI Chatbot" and you have been created by AnyCompany as an expert in their business.
Use only the knowledge base tool when answering the user's questions.
If the knowledge base does provide information about a question, you should say you do not know the answer.
You should try to completely avoid outputting bulleted lists and sub lists, unless it's absolutely necessary.
"""

# we have a single stateful agent per container session id
strands_agent = None


class InvocationResponse(BaseModel):
    message: Dict[str, Any]


@app.post("/invocations", response_model=InvocationResponse)
async def invoke_agent(request: Request):
    global strands_agent
    result = None

    # validate input
    req = await request.json()
    invoke_input = req["input"]
    prompt = invoke_input["prompt"]
    user_id = invoke_input["user_id"]
    logging.info(f"user_id = {user_id}")
    session_id = request.headers.get(
        "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id")

    if not all([prompt, user_id, session_id]):
        error_msg = ""
        if not prompt:
            error_msg = "No prompt found in input. Please provide a 'prompt' key in the input."
        elif not user_id:
            error_msg = "No user_id found in input. Please provide a 'user_id' key in the input."
        else:
            error_msg = "Missing header X-Amzn-Bedrock-AgentCore-Runtime-Session-Id"
        logging.error(error_msg)
        raise HTTPException(status_code=400, detail=error_msg)

    if strands_agent is None:

        # initialize a new agent once for each runtime container session.
        # conversation state will be persisted in both local memory
        # and remote agentcore memory. for resumed sessions,
        # AgentCoreMemorySessionManager will rehydrate state from agentcore memory

        logging.info("initializing session manager")
        config = AgentCoreMemoryConfig(
            memory_id=memory_id,
            session_id=session_id,
            actor_id=user_id
        )
        session_manager = AgentCoreMemorySessionManager(
            boto_client_config=retry_config,
            agentcore_memory_config=config
        )

        logging.info("agent initializing")
        try:
            strands_agent = Agent(
                model="us.anthropic.claude-3-5-haiku-20241022-v1:0",
                system_prompt=system_prompt,
                tools=[retrieve],
                session_manager=session_manager,
            )
        except Exception as e:
            logging.error(f"Agent initialization failed: {str(e)}")
            raise HTTPException(
                status_code=500, detail=f"Agent initialization failed: {str(e)}")

    try:
        # invoke the agent
        logging.info("invoking agent")
        result = strands_agent(prompt=prompt)
        logging.info("agent invocation completed successfully")

        # send response to client
        return InvocationResponse(message=result.message)

    except Exception as e:
        logging.error(f"Agent processing failed: {str(e)}")
        raise HTTPException(
            status_code=500, detail=f"Agent processing failed: {str(e)}")


class NoHealthCheckFilter(logging.Filter):
    """disable health check logging"""

    def filter(self, record):
        return "GET /ping" not in record.getMessage()


logging.getLogger("uvicorn.access").addFilter(NoHealthCheckFilter())


@app.get("/ping")
async def ping():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
