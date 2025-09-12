import os


class Config:
    """Application configuration"""

    AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
    if AWS_REGION is None:
        raise Exception("AWS_REGION is required")

    # AWS Configuration
    AGENT_RUNTIME = os.environ.get("AGENT_RUNTIME", "")
    if AGENT_RUNTIME == "":
        raise Exception("AGENT_RUNTIME is required")

    MEMORY_ID = os.environ.get("MEMORY_ID", "")
    if MEMORY_ID == "":
        raise Exception("MEMORY_ID is required")
