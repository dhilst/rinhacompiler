FROM python:3.10-slim

WORKDIR /
COPY setup.py _crinha.pyx crinha.py /
COPY fib.json /var/rinha/source.rinha.json
RUN apt-get update && apt-get install -y gcc
RUN pip install Cython
RUN python3 setup.py build_ext --inplace
CMD ["sh", "-c", "python3 /crinha.py < /var/rinha/source.rinha.json"]