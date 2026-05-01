from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict

@dataclass
class Event:
    user_id:    str
    event_type: str
    payload:    Dict[str, Any] = field(default_factory=dict)
    timestamp:  str            = field(default_factory=lambda: datetime.now().isoformat())
