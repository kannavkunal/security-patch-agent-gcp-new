FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all application code into app/ subdirectory
# This preserves the module structure for imports like "from app.phases import ..."
COPY . ./app/

# Run as non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /workspace
USER appuser

# Expose port
EXPOSE 8080

# Default command (can be overridden in deployment)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
