import os
import log
import logging
import json
import boto3
from bedrock_agentcore.memory import MemoryClient
from chat_message import ChatMessage

memory_client = MemoryClient(region_name=os.getenv("AWS_REGION"))
memory_id = os.getenv("MEMORY_ID")
memory_data_client = boto3.client("bedrock-agentcore")


class Database():
    """Memory database abstraction"""

    def get(self, conversation_id, user_id):
        """fetch a conversation by id and user"""

        events = memory_client.list_events(memory_id, user_id, conversation_id)
        logging.info(f"found {len(events)} events")
        log.info(events)

        # translate list of events into a conversation with question/answer groupings
        # iterate the list of events backwards
        questions = []
        current_question = None
        current_answer = None

        # Process events in reverse chronological order (oldest first)
        for event in reversed(events):
            if 'payload' in event and event['payload']:
                for payload_item in event['payload']:
                    if 'conversational' in payload_item:
                        conv = payload_item['conversational']
                        role = conv.get('role')
                        content = conv.get('content', {}).get('text', '')

                        # content is json encoded in memory
                        msg = ChatMessage.from_json(content)

                        # Skip tool related messages as they're intermediate
                        if msg.is_tool_message():
                            continue

                        content_text = msg.get_text_content()

                        if role == 'USER':
                            # If we have a complete Q&A pair, save it
                            if current_question and current_answer:
                                questions.append({
                                    "q": current_question,
                                    "a": current_answer
                                })

                            # Start new question
                            current_question = content_text
                            current_answer = None

                        elif role == 'ASSISTANT':
                            # Set the answer for current question
                            current_answer = content_text

        # Add the last Q&A pair if it exists
        if current_question and current_answer:
            questions.append({
                "q": current_question,
                "a": current_answer
            })

        # For now, return empty sources array - this could be enhanced
        # to extract source information from tool calls or other metadata
        result = {
            "conversationId": conversation_id,
            "user_id": user_id,
            "questions": questions,
            "sources": []
        }
        log.info("translated data...")
        log.info(result)
        return result

    def list_by_user(self, user_id, top):
        """fetch a list of conversations by user, sorted by latest activity"""

        try:
            response = memory_data_client.list_sessions(
                memoryId=memory_id,
                actorId=user_id,
            )
        except:
            return []

        sessions_with_events = []
        logging.info(
            f"Found {len(response['sessionSummaries'])} total sessions")

        for session in response["sessionSummaries"]:
            session_id = session['sessionId']
            logging.info(f"Processing session: {session_id}")

            events_response = memory_data_client.list_events(
                memoryId=memory_id,
                actorId=user_id,
                sessionId=session_id,
                includePayloads=True,
                maxResults=100,
            )
            events = events_response.get('events', [])
            logging.info(f"Session {session_id} has {len(events)} events")

            if events:
                # Sort events by eventTimestamp (convert to datetime for proper sorting)
                from datetime import datetime

                def parse_timestamp(event):
                    ts = event['eventTimestamp']
                    if isinstance(ts, str):
                        # Parse ISO format timestamp
                        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
                    return ts

                sorted_events = sorted(events, key=parse_timestamp)

                latest_ts = parse_timestamp(sorted_events[-1])

                # Add session with first and latest events
                sessions_with_events.append({
                    'session': session,
                    'first_event': sorted_events[0],
                    'latest_event': sorted_events[-1],
                    'latest_timestamp': latest_ts
                })

        # Sort sessions by latest event timestamp (most recent first)
        sessions_with_events.sort(
            key=lambda x: x['latest_timestamp'], reverse=True)

        # Convert to the requested format
        chat_history = []
        for session_data in sessions_with_events[:top]:
            first_event = session_data['first_event']

            # Extract initial question from first event
            initial_question = "No question found"
            if 'payload' in first_event and first_event['payload']:
                payload = first_event['payload'][0]
                if 'conversational' in payload:
                    content = payload['conversational'].get('content', {})
                    if 'text' in content:
                        initial_question = content['text']

                        # memory stores the raw message json
                        # parse the text
                        msg = ChatMessage.from_json(initial_question)
                        initial_question = msg.get_text_content()

            # Format timestamp as M/D/YY H:MM AM/PM
            created_dt = session_data['latest_timestamp']

            # Manual 12-hour format conversion
            hour = created_dt.hour
            am_pm = "AM" if hour < 12 else "PM"
            hour_12 = hour if hour == 0 or hour == 12 else hour % 12
            if hour_12 == 0:
                hour_12 = 12

            created = f"{created_dt.month}/{created_dt.day}/{created_dt.year} {hour_12}:{created_dt.minute:02d} {am_pm}"

            chat_history.append({
                "conversationId": session_data['session']['sessionId'],
                "initial_question": initial_question,
                "created": created
            })

        return chat_history
