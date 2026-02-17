FROM python:3.14-slim

WORKDIR /app

# Create the virtual environment (mirrors local_launch_with_aws_profile.sh)
RUN python3 -m venv .venv

# Activate the venv for all subsequent RUN, CMD, and ENTRYPOINT instructions
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install dependencies into the virtual environment
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

ENTRYPOINT ["python", "main.py"]