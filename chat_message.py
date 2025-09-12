import json
from dataclasses import dataclass
from typing import List, Optional, Dict


@dataclass
class ToolUse:
    """Represents the use of a tool in a message."""
    toolUseId: str
    name: str
    input: Dict[str, str]


@dataclass
class ToolResult:
    """Represents the result of a tool use in a message."""
    toolUseId: str
    status: str
    content: List[Dict[str, str]]


@dataclass
class MessageContent:
    """Represents the content of a message, which can be text, a tool use, or a tool result."""
    text: Optional[str] = None
    toolUse: Optional[ToolUse] = None
    toolResult: Optional[ToolResult] = None


@dataclass
class ChatMessage:
    """Represents a chat message, which has a role and a list of content items."""
    role: str
    content: List[MessageContent]

    @classmethod
    def from_json(cls, json_data: str):
        """
        Constructs a ChatMessage object from a JSON string.

        Args:
            json_data (str): The JSON string containing the chat message data.

        Returns:
            ChatMessage: The constructed ChatMessage object.
        Raises:
            ValueError: If the JSON data is invalid or cannot be parsed.
        """
        try:
            data = json.loads(json_data)
        except (json.JSONDecodeError, ValueError) as e:
            raise ValueError("Invalid JSON data") from e

        content = []
        for item in data['message']['content']:
            if 'text' in item:
                content.append(MessageContent(text=item['text']))
            elif 'toolUse' in item:
                tool_use = item['toolUse']
                content.append(MessageContent(toolUse=ToolUse(
                    toolUseId=tool_use['toolUseId'],
                    name=tool_use['name'],
                    input=tool_use['input']
                )))
            elif 'toolResult' in item:
                tool_result = item['toolResult']
                content.append(MessageContent(toolResult=ToolResult(
                    toolUseId=tool_result['toolUseId'],
                    status=tool_result['status'],
                    content=tool_result['content']
                )))

        return cls(
            role=data['message']['role'],
            content=content,
        )

    def is_tool_message(self) -> bool:
        """
        Checks if the message contains information about a tool use or a tool result.

        Returns:
            bool: True if the message contains a tool use or a tool result, False otherwise.
        """
        for content in self.content:
            if content.toolUse is not None or content.toolResult is not None:
                return True
        return False

    def get_text_content(self) -> str:
        """
        Returns the text content of the first message content item.

        Returns:
            str: The text content of the first message content item.

        Raises:
            IndexError: If the message content list is empty or the first item does not have a 'text' property.
        """
        if not self.content:
            raise IndexError("Message content list is empty")
        if self.content[0].text is None:
            raise IndexError(
                "First message content item does not have a 'text' property")
        return self.content[0].text
