from pydantic import BaseModel
from typing import List, Optional

class TajweedErrorResponse(BaseModel):
    rule: str
    severity: str
    explanation: str
    suggestion: str

class WordResultResponse(BaseModel):
    word_index: int
    expected_word: str
    recognized_word: str
    confidence: float
    is_correct: bool
    tajweed_errors: List[TajweedErrorResponse]
