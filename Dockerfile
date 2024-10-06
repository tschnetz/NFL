FROM python:3.12-slim

WORKDIR /app

COPY . /app

RUN pip install --no-cache-dir -r requirements.txt
RUN pip install gunicorn

# Non-root user for security
RUN useradd -m -d /app appuser
USER appuser

EXPOSE $PORT

# Command to start Gunicorn with your app
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 dash_app:server
