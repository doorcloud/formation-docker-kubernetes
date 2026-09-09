# Image "mauvaise" volontairement : grosse base, COPY . en premier, root.
FROM python:3.12

RUN apt-get update && apt-get install -y vim curl

COPY . /app
WORKDIR /app

RUN pip install -r requirements.txt

CMD ["python", "app.py"]
