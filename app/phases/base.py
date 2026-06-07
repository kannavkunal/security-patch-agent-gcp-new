"""Base Phase class for the 7-phase methodology"""
from abc import ABC, abstractmethod
from typing import Dict, Any
import logging

class Phase(ABC):
    """Base class for all phases"""

    def __init__(self, context: Dict[str, Any]):
        self.context = context
        self.logger = logging.getLogger(self.__class__.__name__)

    @abstractmethod
    def execute(self) -> Dict[str, Any]:
        """Execute phase and return results"""
        pass

    def update_context(self, data: Dict[str, Any]) -> None:
        """Update shared context"""
        self.context.update(data)
