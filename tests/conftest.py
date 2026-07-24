"""Test bootstrap.

The Glue scripts create boto3 clients at import time, which need a region and credentials even though no AWS call is made in these unit tests.
"""
import os
import sys

import boto3

# The Glue scripts build boto3 clients at import time and only need a region
# (no AWS call is made in these unit tests). Set it on the default session
# directly rather than via the AWS_DEFAULT_REGION env var.
boto3.setup_default_session(region_name="eu-west-1")

# Dummy creds so no real local profile is picked up during client construction.
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")

_root = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(_root, "glue_scripts"))
sys.path.insert(0, os.path.join(_root, "lambda"))
