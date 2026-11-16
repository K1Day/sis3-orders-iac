FROM public.ecr.aws/docker/library/python:3.13-slim
WORKDIR /app
# dependencies first: editing app.py does not reinstall boto3 (layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --create-home --uid 10001 appuser
USER appuser
EXPOSE 8080
CMD ["python", "-u", "app.py"]
