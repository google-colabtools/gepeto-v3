"""ASGI wrapper for Flask application to work with Uvicorn"""
from asgiref.wsgi import WsgiToAsgi
from keep_running import app

# Wrap Flask WSGI app to ASGI
asgi_app = WsgiToAsgi(app)
