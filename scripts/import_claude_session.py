#!/usr/bin/env python3
"""
Claude to Silicogen Session Importer

Imports Claude session history into Silicogen while preserving source attribution.
Creates a NEW session rather than modifying existing ones.

Provenance fields added to each imported message:
- source: "claude"
- original_session: Claude session ID
- imported_by: "silicogen-importer"
- imported_at: ISO timestamp

Usage:
    python import_claude_session.py --help
    python import_claude_session.py --dry-run /path/to/claude_session.jsonl
    python import_claude_session.py /path/to/claude_session.jsonl
"""

import argparse
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

CLAUDE_SESSION_FILE = "/tmp/claude_asa-tech-specification_session.jsonl"
SILICOGEN_DB_PATH = "/home/silicogen/.local/share/silicogen/storage/silicogen.db"

def parse_args():
    parser = argparse.ArgumentParser(
        description="Import Claude session to Silicogen with provenance tracking"
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        default=CLAUDE_SESSION_FILE,
        help="Path to Claude session JSONL file"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be imported without writing to database"
    )
    parser.add_argument(
        "--db-path",
        default=SILICOGEN_DB_PATH,
        help="Path to Silicogen database"
    )
    parser.add_argument(
        "--session-title",
        default="asa spec test",
        help="Title for the new Silicogen session"
    )
    return parser.parse_args()

def generate_silicogen_id(prefix: str) -> str:
    """Generate a Silicogen-style ID"""
    return f"{prefix}{uuid.uuid4().hex[:24]}"

def parse_claude_timestamp(ts: str) -> int:
    """Parse Claude timestamp to milliseconds since epoch"""
    if not ts:
        return int(datetime.now(timezone.utc).timestamp() * 1000)
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        return int(dt.timestamp() * 1000)
    except:
        return int(datetime.now(timezone.utc).timestamp() * 1000)

def extract_claude_messages(claude_file: str) -> list:
    """Extract user/assistant messages from Claude session"""
    messages = []
    
    with open(claude_file, 'r') as f:
        for line in f:
            try:
                data = json.loads(line)
                msg_type = data.get('type')
                
                if msg_type == 'user' and 'message' in data:
                    msg_data = data['message']
                    role = msg_data.get('role', 'user')
                    if role == 'user':
                        content = msg_data.get('content', '')
                        if isinstance(content, list):
                            text_parts = []
                            for part in content:
                                if isinstance(part, dict):
                                    if part.get('type') == 'text':
                                        text_parts.append(part.get('text', ''))
                            content = '\n'.join(text_parts)
                        
                        # Skip local command messages and empty content
                        if '<local-command-caveat>' in content or '<command-name>' in content:
                            continue
                        if '<local-command-stdout>' in content:
                            continue
                        if not content or not content.strip():
                            continue
                        
                        messages.append({
                            'role': 'user',
                            'content': content,
                            'timestamp': parse_claude_timestamp(data.get('timestamp', '')),
                            'original_uuid': data.get('uuid', ''),
                            'claude_session_id': data.get('sessionId', '')
                        })
                
                elif msg_type == 'assistant' and 'message' in data:
                    msg_data = data['message']
                    role = msg_data.get('role', 'assistant')
                    if role == 'assistant':
                        content = msg_data.get('content', [])
                        text_content = ''
                        if isinstance(content, list):
                            for part in content:
                                if isinstance(part, dict):
                                    if part.get('type') == 'text':
                                        text_content += part.get('text', '')
                                    elif part.get('type') == 'thinking':
                                        text_content += f"[Thinking]\n{part.get('thinking', '')}"
                        
                        # Skip empty messages
                        if not text_content or not text_content.strip():
                            continue
                        
                        messages.append({
                            'role': 'assistant',
                            'content': text_content,
                            'timestamp': parse_claude_timestamp(data.get('timestamp', '')),
                            'original_uuid': data.get('uuid', ''),
                            'model': msg_data.get('model', ''),
                            'claude_session_id': data.get('sessionId', '')
                        })
            except json.JSONDecodeError:
                continue
    
    return messages

def create_silicogen_session(conn, session_title: str, original_claude_session: str) -> str:
    """Create a new session in Silicogen database"""
    session_id = generate_silicogen_id('ses_')
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    
    session_data = {
        "id": session_id,
        "version": 0,
        "projectID": "global",
        "directory": "/home/silicogen/projects/siliconp/docpdfmd",
        "title": session_title,
        "time": {
            "created": now_ms,
            "updated": now_ms
        },
        "summary": {
            "title": session_title,
            "diffs": []
        },
        "_provenance": {
            "source": "claude",
            "original_session": original_claude_session,
            "imported_by": "silicogen-importer",
            "imported_at": datetime.now(timezone.utc).isoformat()
        }
    }
    
    conn.execute("""
        INSERT INTO session (id, project_id, parent_id, title, version, data, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        session_id,
        'global',
        None,
        session_title,
        0,
        json.dumps(session_data),
        now_ms,
        now_ms
    ))
    
    conn.commit()
    return session_id

def insert_message(conn, session_id: str, role: str, content: str, timestamp: int, 
                  original_claude_session: str, original_uuid: str, model: str = None):
    """Insert a message into Silicogen database with provenance"""
    msg_id = generate_silicogen_id('msg_')
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    
    info = {
        "id": msg_id,
        "sessionID": session_id,
        "role": role,
        "time": {
            "created": timestamp
        },
        "_provenance": {
            "source": "claude",
            "original_session": original_claude_session,
            "original_message_id": original_uuid,
            "imported_by": "silicogen-importer",
            "imported_at": datetime.now(timezone.utc).isoformat()
        }
    }
    
    if role == 'user':
        info['summary'] = {
            "title": content[:100] if content else "",
            "diffs": []
        }
        info['agent'] = "silicogen"
        info['model'] = {
            "providerID": "openai",
            "modelID": "gpt-5.4"
        }
    else:
        info['parentID'] = ""
        info['modelID'] = model or "gpt-5.4"
        info['providerID'] = "openai"
        info['mode'] = "normal"
        info['agent'] = "silicogen"
        info['path'] = {
            "cwd": "/home/silicogen/projects/siliconp/docpdfmd",
            "root": "/home/silicogen/projects/siliconp"
        }
        info['cost'] = 0
        info['tokens'] = {
            "input": 0,
            "output": 0,
            "reasoning": 0,
            "cache": {"read": 0, "write": 0}
        }
        info['finish'] = "stop"
    
    parts = []
    if content:
        parts = [{
            "id": generate_silicogen_id('prt_'),
            "type": "text",
            "text": content
        }]
    
    conn.execute("""
        INSERT INTO message (id, session_id, role, info, parts, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        msg_id,
        session_id,
        role,
        json.dumps(info),
        json.dumps(parts),
        timestamp
    ))

def main():
    args = parse_args()
    
    print(f"=== Claude to Silicogen Importer ===")
    print(f"Input file: {args.input_file}")
    print(f"Database: {args.db_path}")
    print(f"Dry run: {args.dry_run}")
    print()
    
    # Check input file exists
    if not Path(args.input_file).exists():
        print(f"ERROR: Input file not found: {args.input_file}")
        return 1
    
    # Extract messages from Claude session
    print("Parsing Claude session...")
    messages = extract_claude_messages(args.input_file)
    print(f"Found {len(messages)} messages to import")
    print()
    
    # Show sample
    print("=== Sample Messages ===")
    for i, msg in enumerate(messages[:5]):
        preview = msg['content'][:80].replace('\n', ' ') if msg['content'] else '(empty)'
        print(f"{i+1}. [{msg['role']}] {preview}...")
    print()
    
    if args.dry_run:
        print("=== DRY RUN - No changes will be made ===")
        print(f"Would create new session with {len(messages)} messages")
        return 0
    
    # Get original Claude session ID from first message
    original_session = messages[0].get('claude_session_id', 'unknown') if messages else 'unknown'
    
    # Connect to database
    print(f"Connecting to database...")
    conn = sqlite3.connect(args.db_path)
    
    # Create new session
    print(f"Creating new Silicogen session...")
    session_id = create_silicogen_session(
        conn, 
        args.session_title,
        original_session
    )
    print(f"Created session: {session_id}")
    
    # Insert messages
    print(f"Inserting {len(messages)} messages...")
    for i, msg in enumerate(messages):
        insert_message(
            conn,
            session_id,
            msg['role'],
            msg['content'],
            msg['timestamp'],
            original_session,
            msg.get('original_uuid', ''),
            msg.get('model', '')
        )
        if (i + 1) % 10 == 0:
            print(f"  Inserted {i + 1}/{len(messages)} messages...")
    
    conn.commit()
    conn.close()
    
    print()
    print(f"=== Import Complete ===")
    print(f"New session ID: {session_id}")
    print(f"Session title: {args.session_title}")
    print(f"Messages imported: {len(messages)}")
    print()
    print(f"Provenance fields added to all messages:")
    print(f"  - source: 'claude'")
    print(f"  - original_session: '{original_session}'")
    print(f"  - imported_by: 'silicogen-importer'")
    print(f"  - imported_at: <current timestamp>")
    
    return 0

if __name__ == "__main__":
    exit(main())
