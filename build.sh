#!/bin/sh
docker build -t myapp:v1 . -f Dockerfile-blue
docker build -t myapp:v2 . -f Dockerfile-green
