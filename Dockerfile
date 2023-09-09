FROM python:3.10-slim

WORKDIR /
COPY rinha.py /
COPY requirements.txt /
COPY fib.json /var/rinha/source.rinha.json
CMD ["sh", "-c", "python3 /rinha.py < /var/rinha/source.rinha.json"]