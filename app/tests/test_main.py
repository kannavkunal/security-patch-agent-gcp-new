import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
import os
import json
import sys

# Set environment variables before importing app
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["GCP_LOCATION"] = "us-central1"
os.environ["API_KEYS"] = "test-key-123,test-key-456"
os.environ["PUBSUB_TOPIC"] = "test-topic"
os.environ["TESTING"] = "true"  # Disable GCP client initialization

from app.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_health_endpoint(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["model"] == "gemini-2.5-pro"


def test_root_endpoint(client):
    """Test root endpoint returns HTML dashboard"""
    response = client.get("/")
    assert response.status_code == 200
    # Root now serves HTML UI, not JSON
    assert response.headers["content-type"].startswith("text/html")


def test_api_endpoint(client):
    """Test API info endpoint"""
    response = client.get("/api")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "Security Patch Agent"
    assert data["version"] == "1.0.0"
    assert data["status"] == "running"


def test_analyze_without_api_key(client):
    """Test analyze endpoint without API key"""
    response = client.post(
        "/analyze",
        json={"code": "print('hello')", "language": "python"}
    )
    assert response.status_code == 401
    assert "Missing API Key" in response.json()["detail"]


def test_analyze_with_invalid_api_key(client):
    """Test analyze endpoint with invalid API key"""
    response = client.post(
        "/analyze",
        headers={"X-API-Key": "invalid-key"},
        json={"code": "print('hello')", "language": "python"}
    )
    assert response.status_code == 401
    assert "Invalid API Key" in response.json()["detail"]


def test_analyze_missing_code(client):
    """Test analyze endpoint with missing code"""
    response = client.post(
        "/analyze",
        headers={"X-API-Key": "test-key-123"},
        json={"language": "python"}
    )
    assert response.status_code == 422  # Validation error


def test_analyze_missing_language_uses_default(client):
    """Test analyze endpoint with missing language uses auto-detect"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "No issues found"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={"code": "print('hello')"}
        )
        # Should work - language is optional with default "auto-detect"
        assert response.status_code == 200


def test_analyze_sql_injection(client):
    """Test SQL injection detection"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": True,
        "vulnerabilities": [
            {
                "type": "SQL Injection",
                "description": "Direct string concatenation with user input in SQL query",
                "line_numbers": "1",
                "severity": "Critical"
            }
        ],
        "severity": "Critical",
        "recommendations": ["Use parameterized queries"],
        "summary": "SQL injection vulnerability detected"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={
                "code": 'def get_user(id): return "SELECT * FROM users WHERE id = " + id',
                "language": "python"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["is_vulnerable"] == True
        assert data["severity"] == "Critical"
        assert len(data["vulnerabilities"]) > 0


def test_analyze_safe_code(client):
    """Test analysis of safe code"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "No vulnerabilities detected"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={
                "code": 'def get_user(db, id): return db.execute("SELECT * FROM users WHERE id = ?", (id,))',
                "language": "python"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["is_vulnerable"] == False
        assert data["severity"] == "None"


def test_analyze_xss_vulnerability(client):
    """Test XSS vulnerability detection"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": True,
        "vulnerabilities": [
            {
                "type": "Cross-Site Scripting (XSS)",
                "description": "User input rendered without sanitization",
                "line_numbers": "1",
                "severity": "High"
            }
        ],
        "severity": "High",
        "recommendations": ["Sanitize user input before rendering"],
        "summary": "XSS vulnerability detected"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={
                "code": 'return "<div>" + user_input + "</div>"',
                "language": "javascript"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["is_vulnerable"] == True
        assert data["severity"] == "High"


def test_rate_limiting(client):
    """Test that endpoint is accessible multiple times"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "Test"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        # Make 5 requests - all should succeed (rate limiting would be handled by Istio)
        for i in range(5):
            response = client.post(
                "/analyze",
                headers={"X-API-Key": "test-key-123"},
                json={"code": "print('hello')", "language": "python"}
            )
            assert response.status_code == 200


def test_empty_code(client):
    """Test with empty code string"""
    response = client.post(
        "/analyze",
        headers={"X-API-Key": "test-key-123"},
        json={"code": "", "language": "python"}
    )
    # Empty string is valid, but Gemini might not like it
    # Should be 200 or 500, not 422 (validation passes)
    assert response.status_code in [200, 500]


def test_supported_languages(client):
    """Test various supported languages"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "Test"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    languages = ["python", "javascript", "java", "go", "rust", "typescript"]

    with patch('app.main.get_model', return_value=mock_model_instance):
        for lang in languages:
            response = client.post(
                "/analyze",
                headers={"X-API-Key": "test-key-123"},
                json={"code": "sample code", "language": lang}
            )
            # Should not return 422 (validation error) for any language
            assert response.status_code == 200


def test_analyze_with_context(client):
    """Test analyze with optional context field"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "Test"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={
                "code": "print('test')",
                "language": "python",
                "context": "This is a web application handler"
            }
        )
        assert response.status_code == 200


def test_multiple_api_keys(client):
    """Test that multiple API keys work"""
    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "is_vulnerable": False,
        "vulnerabilities": [],
        "severity": "None",
        "recommendations": [],
        "summary": "Test"
    })

    mock_model_instance = MagicMock()
    mock_model_instance.generate_content.return_value = mock_response

    with patch('app.main.get_model', return_value=mock_model_instance):
        # Test first key
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-123"},
            json={"code": "print('test')", "language": "python"}
        )
        assert response.status_code == 200

        # Test second key
        response = client.post(
            "/analyze",
            headers={"X-API-Key": "test-key-456"},
            json={"code": "print('test')", "language": "python"}
        )
        assert response.status_code == 200
