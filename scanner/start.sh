#!/bin/bash
cd "$(dirname "$0")"
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app --host 0.0.0.0 --port 8082
