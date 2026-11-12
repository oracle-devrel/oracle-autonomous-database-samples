import os
import sys
import json
try:
  from configparser import ConfigParser
except ImportError:
  from ConfigParser import ConfigParser
import string
import glob
import subprocess
import requests
from requests.auth import HTTPBasicAuth
import socket
import tarfile
import shutil
from urllib.parse import urlparse, quote
import math
import getpass
import functools
from datetime import datetime
import re
import base64
import hashlib
import tempfile
import shlex


print = functools.partial(print, flush=True)
print_stderr = functools.partial(print, file=sys.stderr, flush=True)

# stdin key value
# input : ['DBPASSWORD':'value1','TDE_WALLET_STORE_PASSWORD':'value2','DVREALM_PASSWORD':'value3']
# TODO : Encrypt and Decrypt the password
def parse_stdin_kv(line):
    data = {}
    line = line.strip("[]")
    for item in line.split(","):
        if ":" in item:
            k, v = item.split(":", 1)
            data[k.strip("'").upper()] = v.strip("'")
    return data

def secure_input(prompt):
  # Interactive shell (e.g., manual input)
  if sys.stdin.isatty():
    return getpass.getpass(prompt)
  # Non-interactive (e.g., piped from echo or file)
  else:
    return sys.stdin.readline().strip()

def get_tts_tool_version(filename):
  """
    Reads the first line of the version file and returns the version number.
    Returns 'unknown' if the file is missing.
  """
  try:
    with open(filename, "r") as f:
        first_line = f.readline().strip()
    return first_line.split()[0]
  except (FileNotFoundError, IndexError):
    return "unknown"

# Check if the current Python version meets the minimum requirement.
def check_python_version(min_version):
  if sys.version_info < min_version:
    raise EnvironmentError(f"This script requires Python version 3.6 or higher.")

# Return the absolute path of the directory containing the script.
def scriptpath():
  return os.path.dirname(os.path.realpath(__file__))

def log_start_time():
    """
    Logs the start time
    """
    start_time = datetime.utcnow()
    print(f"Start Time (UTC): {start_time}")
    return start_time

def log_end_time(start_time):
    """
    Logs the end time
    """
    end_time = datetime.utcnow()
    elapsed = end_time - start_time
    print(f"Complete Time (UTC): {end_time}")
    print(f"Elapsed Time: {elapsed}\n")

# Return the single quotes comma-seperated item_list as string
def split_into_lines(items, to_upper=True, chunk_size=10):
  """
  Join list of strings into comma-separated lines with line breaks every chunk_size items.
  Optionally convert items to uppercase.
  
  Returns:
    str: Joined string with commas and newlines.
  """
  if to_upper:
    item_array = [item.strip().upper() for item in items.split(',') if item.strip()]
  else:
    item_array = [item.strip() for item in items.split(',') if item.strip()]
  chunk_size = 10
  chunks = []
  for i in range(0, len(item_array), chunk_size):
    chunk = item_array[i:i+chunk_size]
    chunks.append("'" + "','".join(chunk) + "'")
  item_list = ",\n".join(chunks)
  return item_list

# Escape '$' in table names for shell safety (TABLE$1 --> TABLE\$1)
def escape_dollar(raw):
    tables = []
    for tbl in raw.split(','):
      tbl = re.sub(r'(?<!\\)\$', r'\$', tbl.strip())
      tables.append(tbl)
    return ",".join(tables)

def normalize_backup_level(backup_level):
  if isinstance(backup_level, int):
    return 0 if backup_level == 0 else f"1_{backup_level}"

  backup_level_str = str(backup_level).strip()
  if backup_level_str == "0":
    return 0

  if backup_level_str.isdigit():
    return f"1_{backup_level_str}"

  return backup_level_str.replace(".", "_")

def next_backup_level(backup_level):
  backup_level = normalize_backup_level(backup_level)
  if backup_level == 0:
    return "1_1"

  major_level, minor_level = str(backup_level).split("_", 1)
  return f"{major_level}_{int(minor_level) + 1}"

def _parse_common_user_remap(common_user_remap):
  mappings = {}
  raw_value = common_user_remap.strip()
  if not raw_value:
    return mappings
  
  for entry in raw_value.split(','):
    if not entry:
      continue
    
    parts = entry.split(':')
    if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
      raise ValueError(f"Invalid common-user remap entry : {entry}. Expected source:target.")
    
    source = parts[0].strip().upper()
    target = parts[1].strip().upper()

    if source in mappings:
      raise ValueError(f"Duplicate common-user remap source schema {source}.")
    
    if source == target:
      raise ValueError(f"Common-user remap source and target must be different: {source}.")
    
    mappings[source] = target
  
  return mappings

def _normalize_schema_input(schemas):
  schema_list = []
  common_user_remap_entries = []

  for entry in schemas.split(','):
    entry = entry.strip()
    if not entry:
      continue

    if ':' in entry:
      common_user_remap_entries.append(entry.upper())
    else:
      schema_list.append(entry.upper())

  return ",".join(schema_list), ",".join(common_user_remap_entries)  

class OCI_CURL_SIGNER:
  """
  Helper class to call OCI Object Storage REST APIs without importing OCI SDK.

  What it does:
  1. Parses the Object Storage URL
  2. Builds the OCI signing string
  3. Uses openssl with full path to sign it
  4. Sends the request using curl
  5. Passes headers through curl stdin config, not curl -H CLI args
  """
  def __init__(self, env):
    self._env = env
    self._openssl_path = os.environ.get("OPENSSL_PATH", "/usr/bin/openssl")

    if not os.path.isfile(self._openssl_path) or not os.access(self._openssl_path, os.X_OK):
      print_stderr(
          f"openssl not found or not executable at {self._openssl_path}. "
          "Set OPENSSL_PATH to the absolute path of the openssl binary."
      )
      raise FileNotFoundError(f"openssl not found or not executable at {self._openssl_path}")

  def _parse_object_storage_url(self, url):
    """
    Accept any endpoint host. Only require path format like:
      /n/<namespace>/b/<bucket>
      /n/<namespace>/b/<bucket>/o/<object>
    """
    parsed = urlparse(url)

    if not parsed.scheme or not parsed.netloc:
      raise ValueError(f"Invalid Object Storage URL: {url}")

    parts = parsed.path.strip("/").split("/")

    if len(parts) < 4 or parts[0] != "n" or parts[2] != "b":
      raise ValueError(f"Invalid Object Storage path: {url}")

    endpoint = f"{parsed.scheme}://{parsed.netloc}"
    namespace = parts[1]
    bucket_name = parts[3]
    return endpoint, namespace, bucket_name

  def build_bucket_url(self, base_url):
    """
    Build bucket-level URL for validation.
    """
    endpoint, namespace, bucket_name = self._parse_object_storage_url(base_url)
    return f"{endpoint}/n/{namespace}/b/{bucket_name}"

  def build_object_url(self, base_url, object_name):
    """
    Build object-level URL for upload.
    """
    endpoint, namespace, bucket_name = self._parse_object_storage_url(base_url)
    encoded_object_name = quote(object_name, safe="/")
    return f"{endpoint}/n/{namespace}/b/{bucket_name}/o/{encoded_object_name}"

  def _sha256_base64_file(self, file_path):
    """
    Compute base64-encoded SHA256 of file content.
    OCI expects this for PUT object uploads.
    """
    digest = hashlib.sha256()
    with open(file_path, "rb") as fh:
      for chunk in iter(lambda: fh.read(1024 * 1024), b""):
        digest.update(chunk)
    return base64.b64encode(digest.digest()).decode("utf-8")

  def _request_target(self, parsed_url):
    """
    Return path + query, which OCI expects in the signing string.
    """
    return parsed_url.path + (f"?{parsed_url.query}" if parsed_url.query else "")

  def _sign_with_private_key(self, signing_string):
    """
    Sign the OCI canonical request string using the private key from config.
    """
    proc = subprocess.run(
        [self._openssl_path, "dgst", "-sha256", "-sign", self._env.KEY_FILE],
        input=signing_string.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False
    )

    if proc.returncode != 0:
      raise RuntimeError(
          f"openssl signing failed: {proc.stderr.decode('utf-8', errors='replace').strip()}"
      )

    return base64.b64encode(proc.stdout).decode("utf-8")

  def _build_signed_headers(self, method, url, body_file=None,
                            content_type="application/octet-stream"):
    """
    Build OCI Signature auth headers.

    For GET:
      sign (request-target), host, x-date

    For PUT:
      also include content-type, content-length, x-content-sha256
    """
    parsed = urlparse(url)
    x_date = datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S GMT")

    signed_header_names = ["(request-target)", "host", "x-date"]
    signing_lines = [
      f"(request-target): {method.lower()} {self._request_target(parsed)}",
      f"host: {parsed.netloc}",
      f"x-date: {x_date}",
    ]

    headers = {
      "host": parsed.netloc,
      "x-date": x_date,
    }

    if body_file:
      content_length = str(os.path.getsize(body_file))
      x_content_sha256 = self._sha256_base64_file(body_file)

      signed_header_names.extend(["content-type", "content-length", "x-content-sha256"])
      signing_lines.extend([
        f"content-type: {content_type}",
        f"content-length: {content_length}",
        f"x-content-sha256: {x_content_sha256}",
      ])

      headers["content-type"] = content_type
      headers["content-length"] = content_length
      headers["x-content-sha256"] = x_content_sha256

    signing_string = "\n".join(signing_lines)
    signature = self._sign_with_private_key(signing_string)
    key_id = f"{self._env.TENANCY}/{self._env.USER}/{self._env.FINGERPRINT}"

    headers["Authorization"] = (
        f'Signature version="1",'
        f'keyId="{key_id}",'
        f'algorithm="rsa-sha256",'
        f'headers="{" ".join(signed_header_names)}",'
        f'signature="{signature}"'
    )

    return headers

  def _escape_curl_config_value(self, value):
    """
    Escape values before passing them to curl --config - through stdin.
    """
    return value.replace("\\", "\\\\").replace('"', '\\"')

  def request(self, method, url, body_file=None,
              content_type="application/octet-stream",
              expected_status=(200,)):
    """
    Send signed request through curl.

    Important:
    - Authorization header is not passed in curl CLI args
    - Headers go through curl --config - over stdin
    """
    headers = self._build_signed_headers(method, url, body_file, content_type)

    cfg_lines = [
        "silent",
        "show-error",
        f'request = "{method}"',
        f'url = "{self._escape_curl_config_value(url)}"',
    ]

    if self._env.OCI_PROXY_HOST and self._env.OCI_PROXY_PORT:
      proxy = f"{self._env.OCI_PROXY_HOST}:{self._env.OCI_PROXY_PORT}"
      cfg_lines.append(f'proxy = "{self._escape_curl_config_value(proxy)}"')

    for key, value in headers.items():
      header_line = f"{key}: {value}"
      cfg_lines.append(f'header = "{self._escape_curl_config_value(header_line)}"')

    if body_file:
      cfg_lines.append('header = "expect:"')
      cfg_lines.append(f'upload-file = "{self._escape_curl_config_value(body_file)}"')

    curl_cfg = "\n".join(cfg_lines) + "\n"

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
      response_file = tmp.name

    try:
      proc = subprocess.run(
        ["curl", "--config", "-", "-o", response_file, "-w", "%{http_code}"],
        input=curl_cfg,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False
      )

      if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip())

      http_code_text = proc.stdout.strip()
      if not http_code_text.isdigit():
        raise RuntimeError(f"Unexpected curl status output: {http_code_text}")

      status = int(http_code_text)

      with open(response_file, "r", errors="replace") as fh:
        response_body = fh.read()

      if status not in expected_status:
        raise RuntimeError(f"HTTP {status}: {response_body}")

      return status, response_body

    finally:
      try:
        os.remove(response_file)
      except OSError:
        pass

class ConsoleLogger:
  """
  A class to send Python output simultaneously to the terminal and a log file.
  """
  def __init__(self, logfile):
    self.logfile = open(logfile, "a", buffering=1)
    self.stdout = sys.stdout
    self.stderr = sys.stderr

  def write(self, data):
    self.stdout.write(data)
    self.logfile.write(data)

  def flush(self):
    self.stdout.flush()
    self.logfile.flush()
    
  def fileno(self):
    return self.stdout.fileno()

class Environment:
  """
  A class to load environment variables from a config file (tts-backup-env.txt) and expose them as attributes.
  """

  def __init__(self, env_file: str, cleanup_only=False):
    self.env_file = env_file
    self._cleanup_only = cleanup_only
    self._env = ConfigParser()
    self._defaults = {}

    # Validate and load environment file
    self._validate_env_file()
    self._load_env_variables()
    self._preprocess()

  def __str__(self):
    """Return a string representation of the loaded environment variables."""
    return "\n".join([f"{key}: {value}" for key, value in self.__dict__.items()])

  def __getattr__(self,item):
    """Handle missing attributes dynamically."""
    if item in self.__dict__:
      return self.__dict__[item]
    else:
      raise AttributeError(f"{item} is not a valid attribute in the environment configuration.")

  def _validate_env_file(self):
    """Validate the presence of the environment file."""
    if not os.path.isfile(self.env_file):
      raise FileNotFoundError(f"Environment file '{self.env_file}' not found.")
  
  def usage(self):
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("configuration file     : tts-backup-env.txt")
    print_stderr("runtime required inputs: DBPASSWORD")
    print_stderr("runtime optional inputs: TDE_WALLET_STORE_PASSWORD, DVREALM_PASSWORD")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("Provide runtime inputs manually:")
    print_stderr("        Usage: python3 " + sys.argv[0])
    print_stderr("")
    print_stderr("Or provide runtime inputs via standard input, for automation:")
    print_stderr("        (TDE and DV applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n<TDE_WALLET_STORE_PASSWORD>\\n<DVREALM_PASSWORD>\" | python3 " + sys.argv[0])
    print_stderr("        (TDE applicable, DV not applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n<TDE_WALLET_STORE_PASSWORD>\" | python3 " + sys.argv[0])
    print_stderr("        (TDE not applicable, DV applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n\\n<DVREALM_PASSWORD>\" | python3 " + sys.argv[0])
    print_stderr("        (TDE and DV not applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\" | python3 " + sys.argv[0])
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("        CONFIGURATION INPUTS       ")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("Set optional inputs in tts-backup-env.txt:")
    print_stderr("IGNORE_NON_FATAL_ERRORS=<TRUE/FALSE>")
    print_stderr("JDK8_PATH=<optional path to JDK8 used to download objstore bucket wallet>")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    sys.exit(1)
   
  def _load_env_variables(self):
    """Load environment variables from the config file and set them as class attributes."""
    self._env.read(self.env_file)
    self._defaults = self._env['DEFAULT']
    
    # Define and load required variables
    value_fss = self._defaults.get('TTS_FSS_CONFIG', '').strip()
    value_objs = self._defaults.get('TTS_BACKUP_URL', '').strip()
    if self._cleanup_only:
      required_vars = [
        'PROJECT_NAME', 'DATABASE_NAME', 
        'HOSTNAME', 'LSNR_PORT', 'DB_SVC_NAME', 'ORAHOME',
        'DBUSER', 'DB_VERSION'
      ]
    elif value_fss:
      required_vars = [
        'PROJECT_NAME', 'DATABASE_NAME', 
        'HOSTNAME', 'LSNR_PORT', 'DB_SVC_NAME', 'ORAHOME',
        'DBUSER', 'TTS_FSS_CONFIG', 'TTS_FSS_MOUNT_DIR',
        'FINAL_BACKUP', 'DB_VERSION'
      ]
    elif value_objs:
      required_vars = [
        'PROJECT_NAME', 'DATABASE_NAME',
        'HOSTNAME', 'LSNR_PORT', 'DB_SVC_NAME', 'ORAHOME',
        'DBUSER', 'TTS_BACKUP_URL', 'TTS_BUNDLE_URL',
        'FINAL_BACKUP', 'DB_VERSION',
        'CONFIG_FILE', 'COMPARTMENT_OCID'
      ]
    else:
      raise ValueError(f"Missing required environment variables related to file storage service or object storage service.")

    for var in required_vars:
      value = self._defaults.get(var, '').strip()
      if not value:
        raise ValueError(f"Missing required environment variable: {var}")
      setattr(self, var, value)

    # Limit project name to 128 characters
    if len(self.PROJECT_NAME) > 128:
      print_stderr("PROJECT_NAME exceeds the 128-character limit.")
      exit(1)
      
    if (self.PROJECT_NAME in ('.', '..')
      or os.path.isabs(self.PROJECT_NAME)
      or '/' in self.PROJECT_NAME
      or '\\' in self.PROJECT_NAME):
      print_stderr("PROJECT_NAME must be a single project directory name.")
      exit(1)

    # Set one varable which defines customer choosen storage type disk ot objs
    if value_fss:
      setattr(self, 'STORAGE_TYPE', 'FSS')
    elif value_objs:
      setattr(self, 'STORAGE_TYPE', 'OBJECT_STORAGE')

    if value_objs and not self._cleanup_only:
      if not os.path.isfile(self.CONFIG_FILE):
        raise FileNotFoundError(f"CONFIG_FILE path '{self.CONFIG_FILE}' does not exist or is not a file.")

      # Read the OCI config file and set fingerprint, user, tenancy, region, and key_file attributes.
      oci_config = ConfigParser()
      oci_config.read(self.CONFIG_FILE)
      if 'DEFAULT' not in oci_config:
        raise ValueError(f"OCI config file {self.CONFIG_FILE} missing [DEFAULT] section.")
      default_config = oci_config['DEFAULT']
      required_oci_keys = ['user', 'fingerprint', 'tenancy', 'region', 'key_file']
      for key in required_oci_keys:
        value = default_config.get(key, '').strip()
        if not value:
          raise ValueError(f"Missing required key '{key}' in OCI config file {self.CONFIG_FILE}.")
        # Set as USER, FINGERPRINT, TENANCY, REGION, KEY_FILE
        setattr(self, key.upper(), value)

    # Load optional variables; set to empty if not found
    optional_vars = ['SCHEMAS', 'TABLESPACES', 'EXCLUDE_TABLESPACES', 'EXCLUDE_SCHEMAS',
                     'OCI_INSTALLER_PATH', 'OCI_PROXY_HOST', 'OCI_PROXY_PORT', 'CLUSTER_MODE',
                     'DRCC_REGION', 'DRY_RUN', 'EXCLUDE_TABLES', 'INCLUDE_STATISTICS', 
                     'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES',
                     'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT','DVREALM_USER',
                     'ZDM_BASED_TRANSPORT', 'IGNORE_NON_FATAL_ERRORS', 'JDK8_PATH']
    for var in optional_vars:
      value = self._defaults.get(var, '').strip()
      if value and var in ('TABLESPACES', 'SCHEMAS', 'EXCLUDE_TABLESPACES', 'EXCLUDE_SCHEMAS'):
        value = value.replace(" ", "")
      # if value and (var == 'EXCLUDE_TABLES'):
        # value = escape_dollar(value)
      setattr(self, var, value)
    
    # Cleanup needs database authentication only. Do not request TDE or
    # Database Vault credentials because it does not access protected data.
    if self._cleanup_only:
      if getattr(self, 'ZDM_BASED_TRANSPORT').strip():
        stdin_line = sys.stdin.readline().strip()
        parsed = parse_stdin_kv(stdin_line) if stdin_line else {}
        dbpassword = parsed.get("DBPASSWORD", "")
      else:
        dbpassword = secure_input("Enter database password: ").strip()
      
      if not dbpassword:
        print("Missing required variable: DBPASSWORD")
        self.usage()
      setattr(self, 'DBPASSWORD', dbpassword)
      return

    self.SCHEMAS, self.COMMON_USER_REMAP = _normalize_schema_input(self.SCHEMAS)

    if self.TABLESPACES and self.EXCLUDE_TABLESPACES:
      raise ValueError(
        "TABLESPACES and EXCLUDE_TABLESPACES are mutually exclusive; specify only one."
      )

    if self.SCHEMAS and self.EXCLUDE_SCHEMAS:
      raise ValueError(
        "SCHEMAS and EXCLUDE_SCHEMAS are mutually exclusive; specify only one."
      )
    
    if getattr(self, 'ZDM_BASED_TRANSPORT').strip():
      # Intialise Runtime Input vars... (ZDM Transport)
      stdin_line = sys.stdin.readline().strip()
      parsed = parse_stdin_kv(stdin_line) if stdin_line else {}
      runtime_vars = ['DBPASSWORD', 'TDE_WALLET_STORE_PASSWORD', 'DVREALM_PASSWORD']
      for key in runtime_vars:
        if key == "DBPASSWORD":
          value = parsed.get("DBPASSWORD", "")
          if not value:
            print(f"Missing required variable: {key}")
        elif key == "TDE_WALLET_STORE_PASSWORD":
          value = parsed.get("TDE_WALLET_STORE_PASSWORD", "")
        else:
          value = parsed.get("DVREALM_PASSWORD", "")
        
        setattr(self, key, value)
    else:
      # Intialise Runtime Input vars... (NON-ZDM Transport)
      runtime_vars = ['DBPASSWORD', 'TDE_WALLET_STORE_PASSWORD']
      if getattr(self, 'DVREALM_USER').strip():
        runtime_vars.append('DVREALM_PASSWORD')
      for key in runtime_vars:
        if key == "DBPASSWORD":
          value = secure_input(f"Enter database password: ").strip()
          if not value:
            print(f"Missing required variable: {key}")
            self.usage()
        elif key == "TDE_WALLET_STORE_PASSWORD":
          value = secure_input(
                  f"Enter TDE wallet store password (optional) \n"
                  f"Required only if any of the tablespaces are TDE encrypted "
                  f"(leave empty and press Enter if not applicable): "
              ).strip()
        else:
          value = secure_input("Enter Database Vault password: ").strip()

        setattr(self, key, value)

    # Load optional int variables; set to 0 if not found
    numeric_vars = ['PARALLELISM']
    for var in numeric_vars:
      try:
        value = self._defaults.get(var, '').strip()
        if not value:
          raise ValueError(f"Missing required environment variable: {var}")
        else:
          setattr(self, var, int(value))
      except ValueError as e:
        print(f"Value Error for {var}: {e}. Expected an integer.")

    # Initialise CPU_COUNT  
    setattr(self, 'CPU_COUNT', 0)

  def _preprocess(self):
    """Perform preprocessing tasks, removing files and setting default values."""
    project_dir = getattr(self, 'PROJECT_NAME')
    project_dir_path = os.path.join(scriptpath(), project_dir)
    setattr(self, 'PROJECT_DIR_PATH', project_dir_path)
    setattr(self, 'TTS_DIR_NAME', 'TTS_DUMP_DIR')
    if self._cleanup_only:
      return

    # Set default values
    setattr(self, 'BACKUP_LEVEL', 0)
    setattr(self, 'INCR_SCN', 0)
    setattr(self, 'FINAL_BACKUP', getattr(self, 'FINAL_BACKUP', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES', getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT', getattr(self, 'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT', 'FALSE') or 'FALSE')
    setattr(self, 'ZDM_BASED_TRANSPORT', getattr(self, 'ZDM_BASED_TRANSPORT', 'FALSE') or 'FALSE')

    setattr(self, 'IGNORE_NON_FATAL_ERRORS', getattr(self, 'IGNORE_NON_FATAL_ERRORS', 'FALSE') or 'FALSE')
    setattr(self, 'JDK8_PATH', getattr(self, 'JDK8_PATH', '') or '')

    ignore_non_fatal_errors = self.IGNORE_NON_FATAL_ERRORS.strip().upper()
    if ignore_non_fatal_errors not in ['TRUE', 'FALSE']:
      print_stderr("IGNORE_NON_FATAL_ERRORS must be TRUE or FALSE.")
      exit(1)
    setattr(self, 'IGNORE_NON_FATAL_ERRORS', ignore_non_fatal_errors)

    final_backup = getattr(self, 'FINAL_BACKUP').strip().upper()
    if final_backup not in ['TRUE', 'FALSE']:
      raise ValueError(f"FINAL_BACKUP value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {final_backup}.")

    #todo for redaction and ols
    redaction_policies = getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES').strip().upper()
    if redaction_policies not in ['TRUE', 'FALSE']:
      raise ValueError(f"TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {redaction_policies}.")
    
    ols_policies = getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES').strip().upper()
    if ols_policies not in ['TRUE', 'FALSE']:
      raise ValueError(f"TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {ols_policies}.")
    
    dvops_protection = getattr(self, 'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT').strip().upper()
    if dvops_protection not in ['TRUE', 'FALSE']:
      raise ValueError(f"TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {dvops_protection}.")
    
    zdm_transport = getattr(self, 'ZDM_BASED_TRANSPORT').strip().upper()
    if zdm_transport not in ['TRUE', 'FALSE']:
      raise ValueError(f"ZDM_BASED_TRANSPORT value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {zdm_transport}.")


    db_version = getattr(self, 'DB_VERSION').strip().lower()
    if db_version not in ['11g', '12c', '19c', '23ai']:
      raise ValueError(f"DB_VERSION value should be one of ['11g', '12c', '19c', '23ai'] but value is {db_version}.")

    setattr(self, 'CLUSTER_MODE', getattr(self, 'CLUSTER_MODE', 'TRUE') or 'TRUE')
    cluser_mode = getattr(self, 'CLUSTER_MODE').strip().upper()
    if cluser_mode not in ['TRUE', 'FALSE']:
      raise ValueError(f"CLUSTER_MODE value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {cluser_mode}.")

    # Set optional var's 
    opt_vars = ['DRCC_REGION', 'DRY_RUN', 'INCLUDE_STATISTICS']
    for var in opt_vars:
      setattr(self, var, getattr(self, var, 'FALSE') or 'FALSE')
      value = getattr(self, var).strip().upper()
      if value not in ['TRUE', 'FALSE']:
        raise ValueError(f"{var} value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {value}.")

    # Other default settings
    setattr(self, 'OCI_INSTALLER_PATH', getattr(self, 'OCI_INSTALLER_PATH', '') or scriptpath())
    setattr(self, 'TTS_WALLET_CRED_ALIAS', '')
    setattr(self, 'TDE_KEYS_FILE', "tde_keys.exp")
    setattr(self, 'NEXT_SCN', 0)
    setattr(self, 'MAX_CHANNELS', 200)
    setattr(self, 'RMAN_LOGFILES', [])
    setattr(self, 'DRY_RUN_ERRORS', [])

    # Create project manifest JSON file
    self._create_manifest_file()

    # Create directories and bundle files
    self._setup_backup_directories()

    # Setup log file to send all Python output to console and log file in real-time
    self._setup_log_file()

    #create directories needed if the storage type is fss
    if getattr(self, 'STORAGE_TYPE') == "FSS":
      path = os.path.join(getattr(self, 'TTS_FSS_MOUNT_DIR'), getattr(self,'PROJECT_NAME'))
      os.makedirs(path, exist_ok=True)
      os.makedirs(f"{path}/datafile", exist_ok=True)
      os.makedirs(f"{path}/metadata", exist_ok=True)

  def is_dry_run(self):
    return getattr(self, 'DRY_RUN').strip().upper() == "TRUE"

  def _create_manifest_file(self):
    """Create or load the project manifest file."""
    
    # Retrieve project directory path
    project_dir_path = getattr(self, 'PROJECT_DIR_PATH')
    if project_dir_path and not os.path.exists(project_dir_path):
      os.makedirs(project_dir_path)
      print(f"Created project directory: {project_dir_path} \n")

    # Load project manifest JSON file and process it if already exists
    tts_project_file = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}.json")
    setattr(self, 'TTS_PROJECT_FILE', tts_project_file)

    # No need for manifest json in case of dry run
    if self.is_dry_run():
      if os.path.isfile(tts_project_file):
        with open(tts_project_file, 'r') as f:
          project_data = json.load(f)
          setattr(self, 'BACKUP_LEVEL', normalize_backup_level(project_data.get('backup_level')))
          setattr(self, 'INCR_SCN', project_data.get('incr_scn'))
          setattr(self, 'level0_tablespaces', project_data.get('tablespaces', []))
        print(f"DRY_RUN : Loaded existing project manifest file: {tts_project_file} \n")
      else:
        print("DRY_RUN : No existing project manifest found. Using level 0 dry run.\n")
      return

    # Create a new manifest file if it doesn't exist
    if not os.path.isfile(tts_project_file):
      project_data = {
        "project_name": getattr(self, 'PROJECT_NAME'),
        "backup_level": getattr(self, 'BACKUP_LEVEL'),
        "incr_scn": getattr(self, 'INCR_SCN')
      }
      with open(tts_project_file, 'w') as f:
        json.dump(project_data, f, indent=2)
        print(f"Created project manifest file: {tts_project_file} \n")
    else:
      # Load existing backup level and incr_scn from the manifest file
      with open(tts_project_file, 'r') as f:
        project_data = json.load(f)
        setattr(self, 'BACKUP_LEVEL', normalize_backup_level(project_data.get('backup_level')))
        setattr(self, 'INCR_SCN', project_data.get('incr_scn'))
        setattr(self, 'level0_tablespaces', project_data.get('tablespaces'))
      print((f"Loaded existing project manifest file: {tts_project_file} \n"))

  def _setup_backup_directories(self):
    """Set up backup directories and bundle files."""
    
    # Create project directory based on backup level
    project_dir_path = getattr(self, 'PROJECT_DIR_PATH')

    if self.is_dry_run():
      tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN")
      log_file_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN.log")
      
    else:
      tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}")
      log_file_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}.log")

    # Check if the directory exists
    if os.path.exists(tts_dir_path):
      if self.is_dry_run():
        old_dir = f"{tts_dir_path}_OLD"
        counter = 1
        while os.path.exists(old_dir):
          old_dir = f"{tts_dir_path}_OLD_{counter}"
          counter += 1
        shutil.move(tts_dir_path, old_dir)
        shutil.move(log_file_path, old_dir)
        print(f"Moved existing dry-run directory '{tts_dir_path}' to '{old_dir}'")
        print(f"Moved existing dry-run logfile '{log_file_path}' to '{old_dir}'")
      else:
        failed_dir = f"{tts_dir_path}_FAILED"
        # Ensure the failed directory name is unique to avoid overwriting old failures
        counter = 1
        while os.path.exists(failed_dir):
          failed_dir = f"{tts_dir_path}_FAILED_{counter}"
          counter += 1
        # Move the directory
        shutil.move(tts_dir_path, failed_dir)
        shutil.move(log_file_path, failed_dir)
        print(f"Moved existing failed directory '{tts_dir_path}' to '{failed_dir}'")
        print(f"Moved existing logfile '{log_file_path}' to '{failed_dir}'")

    # Create bundle file for transport of backup files
    if self.is_dry_run():
      bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN.tgz"
    else:
      bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}.tgz"
    tts_bundle_file = os.path.join(project_dir_path, bundle_file_name)
    if os.path.isfile(tts_bundle_file):
      now = subprocess.check_output("date +%d-%b-%Y_%H_%M_%S", shell=True).decode().strip()
      if self.is_dry_run():
        bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN_{now}.tgz"
      else:
        bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_{now}.tgz"
      tts_bundle_file = os.path.join(os.path.dirname(tts_dir_path), bundle_file_name)
      if self.is_dry_run():
        tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN_{now}")
      else:
        tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_{now}")
      
    os.makedirs(tts_dir_path, exist_ok=True)
    setattr(self, 'TTS_DIR_PATH', tts_dir_path)
    print(f"Created project directory with backup level {getattr(self, 'BACKUP_LEVEL')} : {tts_dir_path}.")

    setattr(self, 'BUNDLE_FILE_NAME', bundle_file_name)
    setattr(self, 'TTS_BUNDLE_FILE', tts_bundle_file)

  def _setup_log_file(self):
    """Set up log file"""
    project_dir_path = getattr(self, 'PROJECT_DIR_PATH')

    if self.is_dry_run():
      log_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN.log"
    else:
      log_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}.log"
    log_file_path = os.path.join(project_dir_path, log_file_name)
    if os.path.isfile(log_file_path):
      now = subprocess.check_output("date +%d-%b-%Y_%H_%M_%S", shell=True).decode().strip()
      if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
        log_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN_{now}.log"
      else:
        log_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_{now}.log"
      log_file_path = os.path.join(project_dir_path, log_file_name)
    
    setattr(self, 'TTS_LOG_FILE', log_file_name)
    
    log_output = ConsoleLogger(log_file_path)
    sys.stdout = log_output
    sys.stderr = log_output

    print(f"Overall TTS backup log file: {log_file_path}")

  def add_dry_run_error(self, err_msg, log_file=None):
    if not self.is_dry_run():
      return

    if log_file:
      err_msg = f"{err_msg} Review: {log_file}"

    if err_msg not in self.DRY_RUN_ERRORS:
      self.DRY_RUN_ERRORS.append(err_msg)

  def add_dry_run_log_errors(self, err_msg, log_file):
    try:
      with open(log_file, 'r') as file:
        lines = [line.strip() for line in file.readlines() if line.strip()]
    except FileNotFoundError:
      lines = []
    if lines:
      err_msg = f"{err_msg}\n" + "\n".join([f"  {line}" for line in lines])
    self.add_dry_run_error(err_msg, log_file)

  def report_dry_run_result(self):
    if len(self.DRY_RUN_ERRORS) == 0:
      print("TTS BACKUP TOOL : Dry Run Completed Successfully...")
      return 0

    print("\nTTS BACKUP TOOL : Dry Run Failed.")
    print("Dry Run validation errors:")
    for index, err_msg in enumerate(self.DRY_RUN_ERRORS, 1):
      print(f"{index}. {err_msg}")
    return 1

  def use_orahome_libopc(self):
    return self.DB_VERSION.strip().lower() in ['19c', '23ai']

  def get_libopc_path(self):
    if self.use_orahome_libopc():
      return os.path.join(self.ORAHOME, 'lib', 'libopc.so')
    return os.path.join(self.PROJECT_DIR_PATH, 'libopc.so')

class SqlPlus:
  """
  A class to run SQL commands using Oracle's SQL*Plus command-line tool.
  """
  def __init__(self, dbuser, dbpassword, hostname, port, service_name, orahome):
    """Initialize with database connection details."""
    self.dbuser = dbuser
    self.dbpassword = dbpassword
    self.hostname = hostname
    self.port = port
    self.service_name = service_name
    self.orahome = orahome

    if not os.path.isdir(self.orahome):
      raise ValueError(f"Invalid ORAHOME/ORACLE_HOME directory: {self.orahome}")
    self.sqlplus_path = os.path.join(self.orahome, "bin", "sqlplus")

    if not os.path.isfile(self.sqlplus_path):
      raise FileNotFoundError(f"SQL*Plus not found at {self.sqlplus_path}")

  def run_sql(self, sql_script, log_file=None, dv_user=False, append_log=False):
    """Run SQL*Plus with SQL and credentials supplied through stdin."""
    if dv_user:
      conn_string = f"{self.dbuser}/{self.dbpassword}@{self.hostname}:{self.port}/{self.service_name}"
    else:
      conn_string = f"{self.dbuser}/{self.dbpassword}@{self.hostname}:{self.port}/{self.service_name} as SYSDBA"

    if not sql_script.strip():
      raise ValueError("Empty SQL query provided.")

    command = [self.sqlplus_path, "-s", "/nolog"]
    sqlplus_input = "whenever oserror exit 1;\n"
    sqlplus_input += "whenever sqlerror exit 1;\n"
    sqlplus_input += f"connect {conn_string}\n"
    sqlplus_input += "set heading off\nset feedback off\nset pagesize 0\nset serveroutput on\n"

    if log_file:
      spool_mode = "append" if append_log else ""
      sqlplus_input += f"spool {log_file} {spool_mode};\n"

    sqlplus_input += sql_script
    
    if log_file:
      sqlplus_input += "\nspool off;"
    sqlplus_input += "\nexit;\n"

    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    stdout, stderr = process.communicate(sqlplus_input)

    # Check for ORA- errors even if returncode is 0
    failed = False
    for line in stdout.splitlines():
      if "ORA-" in line or "SP2-" in line:
        print(f"[SQL*Plus ERROR] {line.strip()}")
        failed = True

    if process.returncode != 0 or failed:
        print("SQL execution failed with the following details:\n")
        if stdout.strip():
            print(f"STDOUT (SQL*Plus Output):\n {stdout.strip()}\n")
        if stderr.strip():
            print(f"STDERR (Additional Errors):\n {stderr.strip()}\n")
        return False
    
    return True


class TTS_SRC_RUN_VALIDATIONS:
  """
  A class to run schema and tablespace validations for transportable tablespaces.
  """
  def __init__(self, env):
    self._env = env
    self._schemas_provided = bool(self._env.SCHEMAS.strip())
    self._tablespaces_provided = bool(self._env.TABLESPACES.strip())
    self._sqlplus = SqlPlus(
        dbuser=self._env.DBUSER,
        dbpassword=self._env.DBPASSWORD,
        hostname=self._env.HOSTNAME,
        port=self._env.LSNR_PORT,
        service_name=self._env.DB_SVC_NAME,
        orahome=self._env.ORAHOME
    )
    self.log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_validate.log")

  def _raise_or_record_validation_error(self, err_msg):
    if self._env.is_dry_run():
      print(err_msg)
      self._env.add_dry_run_error(err_msg)
    else:
      raise ValueError(err_msg)

  def _filter_excluded_values(self, values, exclude_csv, value_type):
    exclude_set = {item.strip().upper() for item in exclude_csv.split(',') if item.strip()}
    if not exclude_set:
      return values

    filtered_values = [value for value in values if value.strip().upper() not in exclude_set]

    if values and not filtered_values:
      raise ValueError(f"All discovered {value_type} were excluded. Please update EXCLUDE_{value_type.upper()}.")

    return filtered_values

  def _get_tablespaces(self, template):
    """Return all tablespaces if not given"""
    if self._env.TABLESPACES:
      return self._env.TABLESPACES

    try:
      if self._env.BACKUP_LEVEL != 0:
        print(f"Tablespaces not provided. Fetching level-0 specified tablespaces...")  
        tbs = [ts.strip().upper() for ts in self._env.level0_tablespaces if ts.strip()]
      else:
        print(f"Tablespaces not provided. Fetching all tablespaces...")
        _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_get_tablespaces.log")
        if not self._sqlplus.run_sql(template.get('get_tablespaces'), _log_file):
          raise ValueError(f"Failed to fetch user tablespaces.")

        # Read the log file to get the SQL*Plus output
        with open(_log_file, "r") as file:
          lines = file.readlines()
          tbs = [line.strip().upper() for line in lines if line.strip()]
      tbs = self._filter_excluded_values(tbs, self._env.EXCLUDE_TABLESPACES, "tablespaces")
      self._env.TABLESPACES = ",".join(tbs)
      return self._env.TABLESPACES
    except Exception as e:
      print(f"Error while fetching tablespaces : {e}")
      raise
  
  def _get_xml_index_path_tables(self, template):
    try:
      _log_file = os.path.join(
        self._env.TTS_DIR_PATH,
        f"{self._env.PROJECT_NAME}_get_xml_index_path_tables.log")
      if not self._sqlplus.run_sql(
          template.get('get_xml_index_path_tables'), _log_file):
        raise ValueError(f"Failed to fetch XMLIndex path tables.")

      with open(_log_file, "r") as file:
        lines = file.readlines()
        xml_index_path_tables = list(
          dict.fromkeys(line.strip() for line in lines if line.strip()))
      return ",".join(xml_index_path_tables)
    except Exception as e:
      print(f"Error while fetching XMLIndex path tables : {e}")
      raise
  
  def _get_xml_export_tables(self, template):

    print("Fetching XML tables...")
    ts_list = split_into_lines(self._env.TABLESPACES)
    sc_list = split_into_lines(self._env.SCHEMAS)

    exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)
    exc_tbl_filter = f"and t.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_seg = f"and c.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_t = f"and x.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    
    Configuration.substitutions = {
        'ts_list': ts_list.upper(),
        'sc_list': sc_list.upper(),
        'exc_tbl_filter': exc_tbl_filter,
        'exc_tbl_filter_seg': exc_tbl_filter_seg,
        'exc_tbl_filter_t': exc_tbl_filter_t
    }

    try:
      _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_get_xml_export_tables.log")
      if not self._sqlplus.run_sql(template.get('get_xml_export_tables'), _log_file):
        raise ValueError(f"Failed to fetch xml tables.")

      # Read the log file to get the SQL*Plus output
      with open(_log_file, "r") as file:
        lines = file.readlines()
        xml_export_tables = list(dict.fromkeys(line.strip() for line in lines if line.strip()))
      self._env.xml_export_tables = ",".join(xml_export_tables)
      
      if(len(self._env.xml_export_tables)) > 0:
        print("XML tables exist. Fetching XMLIndex path tables...")
        self._env.table_with_xml_type = 'true'
        self._env.xml_index_path_tables = self._get_xml_index_path_tables(
        template)
      else:
        self._env.table_with_xml_type = 'false'
        self._env.xml_index_path_tables = ''
      return self._env.xml_export_tables
    except Exception as e:
      print(f"Error while fetching xml tables : {e}")
      raise

  def _get_schemas(self, template, user_type=None):
    """Return Local/Common users"""
    if user_type == "get_all_local_schemas":
      if self._env.DB_VERSION == '11g':
        sql_script = template.get('get_all_local_schemas_dbversion_11g')
      else: 
        sql_script = template.get('get_all_local_schemas')
    elif user_type == "get_common_schemas":
      if self._env.DB_VERSION == '11g':
        sql_script = template.get('get_common_schemas_dbversion_11g')
      else: 
        sql_script = template.get('get_common_schemas')
    elif user_type == "get_required_local_schemas":
      ts_list = split_into_lines(self._env.TABLESPACES)
      if self._env.DB_VERSION == '11g':
        l_user_list_clause = "username not in ('SYS','SYSTEM')"
      else:
        l_user_list_clause = "username not in ('SYS','SYSTEM') and common='NO' and oracle_maintained='N'"
      Configuration.substitutions = {
        'ts_list': ts_list.upper(),
        'l_user_list_clause': l_user_list_clause,
      }
      sql_script = template.get('get_required_local_schemas')
    elif user_type == "get_tablespace_owners":
      ts_list = split_into_lines(self._env.TABLESPACES)
      exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)
      exc_tbl_filter = f"and segment_name not in ({exc_tbl_list}) "  if exc_tbl_list.strip() else ""

      Configuration.substitutions = {
        'ts_list': ts_list.upper(),
        'exc_tbl_filter': exc_tbl_filter,
      }
      sql_script = template.get('get_tablespace_owners')
    else:
      if not self._env.SCHEMAS:
        if not self._tablespaces_provided:
          print("No schemas/tablespaces provided. Returning a list of all schemas.")
          self._env.SCHEMAS = self._get_schemas(template, "get_all_local_schemas")
        else:
          print("No schemas provided. Returning a list of required local schemas for the provided tablespace list.")
          self._env.SCHEMAS = self._get_schemas(template, "get_required_local_schemas")
      return self._env.SCHEMAS
    
    print(f"Fetching {user_type} users...")
    try:
      _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_get_{user_type}_schemas.log")
      if not self._sqlplus.run_sql(sql_script, _log_file):
        raise ValueError(f"Failed to fetch {user_type} users.")

      # Read the log file to get the SQL*Plus output
      with open(_log_file, "r") as file:
        lines = file.readlines()
        users = [line.strip().upper() for line in lines if line.strip()]
      
      if user_type in ("get_all_local_schemas", "get_required_local_schemas", "get_tablespace_owners"):
        users = self._filter_excluded_values(users, self._env.EXCLUDE_SCHEMAS, "schemas")

      return ",".join(users)
    except Exception as e:
      print(f"Error while fetching {user_type} users: {e}")
      raise

  def _validate_schemas(self, template):
    """Validate schemas"""
    print("Validating schemas...")
    # Validate schemas for common users
    common_users = self._get_schemas(template, "get_common_schemas")
    tbs_owners = self._get_schemas(template, "get_tablespace_owners")
    
    sc_list = [s.strip().upper() for s in self._env.SCHEMAS.split(',') if s.strip()]
    common_user_remap = _parse_common_user_remap(self._env.COMMON_USER_REMAP)
    
    common_user_list = [u.strip().upper() for u in common_users.split(',') if u.strip()]
    tbs_owner_list = [s.strip().upper() for s in tbs_owners.split(',') if s.strip()]
    
    _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_schema_validations.log")
    if os.path.isfile(_log_file):
      os.remove(_log_file)

    def run_schema_validation(schema, template_name, err_msg):
      exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)
      exc_tbl_filter_t = f"and t.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""

      Configuration.substitutions = {
        'schema': schema,
        'ts_list': split_into_lines(self._env.TABLESPACES).upper(),
        'dry_run': self._env.DRY_RUN.strip().upper(),
        'exc_tbl_filter_t': exc_tbl_filter_t,
      }

      if not self._sqlplus.run_sql(template.get(template_name), _log_file, append_log=True):
        print(f"{err_msg}\n")
        if self._env.is_dry_run():
          self._env.add_dry_run_log_errors(err_msg, _log_file)
          return
        self._print_log_and_exit(_log_file)

    for schema in sc_list:
      if schema in common_user_list:
        self._raise_or_record_validation_error(
          f"Schema validation failed: {schema} is a common or Oracle-maintained user and "
          "cannot be listed directly in SCHEMAS. SCHEMAS must contain only local schemas. "
          f"If {schema} owns physical data in selected TABLESPACES [{self._env.TABLESPACES}], "
          f"provide a remap entry '{schema}:<LOCAL_TARGET_SCHEMA>' so the transported "
          "physical data is imported into a local target schema."
        )
        continue

      run_schema_validation(
        schema,
        'validate_schemas',
        f"Schema {schema} validations failed."
      )

    for source, target in common_user_remap.items():
      source_valid_for_sql_check = True

      if source not in common_user_list:
        source_valid_for_sql_check = False
        self._raise_or_record_validation_error(
          f"Invalid common-user remap '{source}:{target}': source schema {source} is not "
          "a common or Oracle-maintained user. Common-user remap is only for supported "
          "common or Oracle-maintained source users. Remove this remap and list the schema "
          "in SCHEMAS if it is a required local schema."
        )

      if source not in tbs_owner_list:
        source_valid_for_sql_check = False
        self._raise_or_record_validation_error(
          f"Invalid common-user remap '{source}:{target}': source schema {source} does not "
          f"own physical data in selected TABLESPACES [{self._env.TABLESPACES}]. No data "
          "will be transported for this source, so this remap is not required. Remove this "
          "remap entry."
        )

      if target in common_user_list:
        self._raise_or_record_validation_error(
          f"Invalid common-user remap '{source}:{target}': target schema {target} is common "
          "or Oracle-maintained. The target must be a local, non-Oracle-maintained schema "
          "name because transported physical data cannot be remapped back into a common "
          "or Oracle-maintained user."
        )

      if source_valid_for_sql_check:
        run_schema_validation(
          source,
          'validate_common_user_remap_source',
          f"Common-user remap source {source} validations failed."
        )

    if os.path.isfile(_log_file) and os.path.getsize(_log_file) > 0:
      self._env.add_dry_run_log_errors("Schema validations failed.", _log_file)
      self._print_log_and_exit(_log_file, 0)

    for schema in tbs_owner_list:
      if schema in common_user_list:
        if schema in common_user_remap:
          continue

        self._raise_or_record_validation_error(
          f"Schema validation failed: {schema} owns physical data in selected TABLESPACES "
          f"[{self._env.TABLESPACES}] and is a common or Oracle-maintained user. Common "
          "or Oracle-maintained users are not exported/imported as schemas. Provide "
          f"'{schema}:<LOCAL_TARGET_SCHEMA>' so only the transported physical data is "
          "imported into a local target schema."
        )
        continue

      if schema not in sc_list:
        self._raise_or_record_validation_error(
          f"Schema validation failed: {schema} owns physical data in selected TABLESPACES "
          f"[{self._env.TABLESPACES}], but it is not included in SCHEMAS [{self._env.SCHEMAS}]. "
          "Add this schema to SCHEMAS, or remove/exclude its physical objects from the "
          "selected tablespaces."
        )
  
  def _validate_tablespaces(self, template):
    """Tablespace validation"""
    print("Validating tablespaces...")
    if self._env.BACKUP_LEVEL != 0:
      print("Check if tablespace list is changed during incremental backups")
      self._validate_tablespaces_list()

    ts_array = self._env.TABLESPACES.split(',')
    ts_list = split_into_lines(self._env.TABLESPACES)
    ts_count = len(ts_array)

    sc_list = split_into_lines(self._env.SCHEMAS)

    exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)

    Configuration.substitutions = {
      'ts_list': ts_list.upper(),
      'final_backup': self._env.FINAL_BACKUP.upper(),
    }

    if not self._sqlplus.run_sql(template.get('purge_dba_recyclebin')):
      err_msg = "Validation failed: Found BIN$ objects in one or more tablespaces from tbs list. Please purge dba_recyclebin to avoid move failures at ADBS."
      print(f"{err_msg}\n")
      self._env.add_dry_run_error(err_msg)
    
    for tablespace in ts_array:
      tablespace = tablespace.strip().upper()
      log_size_before = (os.path.getsize(self.log_file) if os.path.isfile(self.log_file) else 0)
      print(f"Validate if tablespace {tablespace} is ready for transport...")
      self._run_tablespace_validation_script(template, tablespace, sc_list, exc_tbl_list, append_log=True)
      log_size_after = (os.path.getsize(self.log_file) if os.path.isfile(self.log_file) else 0)
      if log_size_after > log_size_before:
        print(f"Tablespace validations failed.")
        self._env.add_dry_run_log_errors(f"Tablespace {tablespace} validations failed.", self.log_file)
        self._print_log_and_exit(self.log_file, 0)

    # TODO : perform TRANSPORT_SET_CHECK for platform_id=13 and dbversion <19.21 (no "for transport" clause)
    if self._env.is_dry_run() or self._env.BACKUP_LEVEL == 0 or self._env.DB_VERSION == '11g':
      ts_list = "'{}'".format(",".join(self._env.TABLESPACES.split(',')))
      Configuration.substitutions = {
        'ts_list': ts_list,
        'dry_run': self._env.DRY_RUN.strip().upper(),
      }
      print(f"Running DBMS_TTS.TRANSPORT_SET_CHECK for tablespaces: {self._env.TABLESPACES}")
      if not self._sqlplus.run_sql(template.get('tts_transport_set_check'), f"{self.log_file} append"):
        print(f"Tablespace validations failed. Please review {self.log_file} for details\n")
        if self._env.is_dry_run():
          self._env.add_dry_run_log_errors("Tablespace validations failed.", self.log_file)
          self._print_log_and_exit(self.log_file, 0)
        else:
          self._print_log_and_exit(self.log_file)
      if os.path.isfile(self.log_file) and os.path.getsize(self.log_file) > 0:
        print(f"Tablespace validations failed.")
        self._env.add_dry_run_log_errors("Tablespace validations failed.", self.log_file)
        self._print_log_and_exit(self.log_file, 0)

    print("Finding plsql objects that are not transported due to owner not in transported schema_list")
    self._run_logical_object_validation(template, ts_list, sc_list)

  def _run_logical_object_validation(self, template, ts_list, sc_list):
    """Run SQL object validation for all tablespaces."""
    if self._env.DB_VERSION == '11g':
      l_user_list_clause = "username not in ('SYS','SYSTEM')"
    else:
      l_user_list_clause = "username not in ('SYS','SYSTEM') and common='NO' and oracle_maintained='N'"

    Configuration.substitutions = {
        'sc_list': sc_list.upper(),
        'ts_list': ts_list.upper(),
        'l_user_list_clause': l_user_list_clause,
      }
      
    if self._env.is_dry_run():
      _log_file = os.path.join(self._env.PROJECT_DIR_PATH, f"{self._env.PROJECT_NAME}_LEVEL_{self._env.BACKUP_LEVEL}_dry_run_logical_object_validations.log")
    else:
      _log_file = os.path.join(self._env.PROJECT_DIR_PATH, f"{self._env.PROJECT_NAME}_LEVEL_{self._env.BACKUP_LEVEL}_object_validations.log")
    
    if not self._sqlplus.run_sql(template.get('logical_object_validation'), _log_file):
      print(f"\n Logical Object validations failed. Please review:")
      print(f"{_log_file}\n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors("Failed to run logical object validations on tablespaces.", _log_file)
        return
      else:
        raise RuntimeError(f"Failed to run logical object validations on tablespaces.")

    print(f"Logical Object validations complete.\n")

    if os.path.isfile(_log_file) and os.path.getsize(_log_file) > 0:
      print(f" Please review: {_log_file}\n")
      print("This file contains a list of database objects that will NOT be transported.\n")
      if self._env.IGNORE_NON_FATAL_ERRORS and self._env.IGNORE_NON_FATAL_ERRORS.upper() == 'TRUE':
        print("Errors Ignored proceeding...\n")
      else:
        print("Set IGNORE_NON_FATAL_ERRORS=TRUE in tts-backup-env.txt to ignore non fatal errors...\n")
        print("IGNORE_NON_FATAL_ERRORS is not TRUE, exiting...")
        print(f" Review: {_log_file}\n")
        self._env.add_dry_run_error("Logical Object validations found, database objects that will NOT be transported :", _log_file)
        if not self._env.is_dry_run():
          sys.exit(1)
  
  def _validate_tablespaces_list(self):
    ts_array = self._env.TABLESPACES.split(',')
    level0_ts_array = self._env.level0_tablespaces

    ts_set = {ts.strip().upper() for ts in ts_array if ts.strip()}
    level0_ts_set = {ts.strip().upper() for ts in level0_ts_array if ts.strip()}
    missing_ts = sorted(level0_ts_set - ts_set)
    new_ts = sorted(ts_set - level0_ts_set)

    if not missing_ts and not new_ts:
      return
    if missing_ts:
      print(f"Missing tablespaces from level_{self._env.BACKUP_LEVEL}_backup: {missing_ts}")
    if new_ts:
      print(f"New tablespaces added in level_{self._env.BACKUP_LEVEL}_backup: {new_ts}")
    print(
    "WARNING: The tablespace list specified during the level 0 backup must not be altered.")
    print(f"Proceeding with the list specified during level 0: {level0_ts_set}")
    self._env.TABLESPACES = ",".join(level0_ts_array)

  def _run_tablespace_validation_script(self, template, tablespace, sc_list, exc_tbl_list, append_log=False):
    """Run SQL validation for a single tablespace."""
    exc_tbl_filter_dt = f"and atc.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_xml = f"and x.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_xml_cont = f"and xm.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""

    Configuration.substitutions = {
        'tablespace': tablespace.upper(),
        'final_backup': self._env.FINAL_BACKUP.upper(),
        'sc_list': sc_list.upper(),
        'exc_tbl_filter_dt': exc_tbl_filter_dt,
        'dry_run': self._env.DRY_RUN.strip().upper(),
        'exc_tbl_filter_xml': exc_tbl_filter_xml,
        'exc_tbl_filter_xml_cont': exc_tbl_filter_xml_cont,
        'ignore_non_fatal_errors': self._env.IGNORE_NON_FATAL_ERRORS.strip().upper(), 
      }
    
    if not self._sqlplus.run_sql(template.get('validate_tablespaces'), self.log_file, append_log=append_log):
      print(f"Tablespace {tablespace} validations failed. \n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors(f"Tablespace {tablespace} validations failed.", self.log_file)
        self._print_log_and_exit(self.log_file, 0)
      else:
        self._print_log_and_exit(self.log_file)
    
  def _validate_tablespace_count(self, ts_list, ts_count):  
    """Validate that the number of tablespaces does not exceed limits."""
    print("Validating tablespaces count...")
    # check if tablespaces count will exceed 30 on ADWCS
    # ADWCS will have 5 necessary tablespaces (SYSTEM, SYSAUX, UNDO, TEMP, DATA)
    # ADWCS might have 2 more tablespace (SAMPLESCHEMA, DBFS_DATA)
    # ADWCS will create one datafile for each of the transported tablespaces
    # Maximum number of tablespaces that can be transported is (30 - 7 = 23)
    if self._env.DRCC_REGION.upper() == 'TRUE':
      # DRCC regions we allow tablespace limit upto 100
      # 100 - 7 (default) = 93
      ts_limit = 93
    else:
      # NON DRCC regions we allow tablespace limit upto 30
      # 30 - 7 (default) = 23
      ts_limit = 23
    if ts_count > ts_limit:
      err_msg = f"ERROR : Total number of specified tablespaces are : {ts_count}. Max allowed tablespace count of 30 will be exceeded in ADWCS."
      print(f"Tablespaces count validation failed. \n")
      print(err_msg)
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        exit(1)
  
  def _validate_redaction_policies(self, template):
    """Redaction Policy validation"""
    print("Validating Redaction policies...")
    sc_list = split_into_lines(self._env.SCHEMAS)

    Configuration.substitutions = {
        'sc_list': sc_list.upper(),
      }

    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_redaction.log")
    if not self._sqlplus.run_sql(template.get('validate_redaction_policies'), log_file):
      print("Redaction Policies validation failed. \n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors("Redaction Policies validation failed.", log_file)
        self._print_log_and_exit(log_file, 0)
        return ''
      else:
        self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      redaction_pls = log.read().strip()
    
    if redaction_pls and self._env.TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES.upper() == "FALSE":
      print("Redaction Policies found in the database. You have to create the redaction policies in ADB-S database. Redacted data will be unprotected in ADB-S database otherwise. \n")
      err_msg = f"[ERROR] Please provide consent to transport tables protected by redaction policies by specifying TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES=TRUE. Redaction policies found are : {redaction_pls}"
      print(err_msg)
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        exit(1)
    return redaction_pls

  def _validate_ols_policies(self, template):
    """OLS Policies validation"""
    print("Validating OLS policies...")
    sc_list = split_into_lines(self._env.SCHEMAS)
    ols_pls = ''
    Configuration.substitutions = {
        'sc_list': sc_list.upper(),
      }
    
    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_ols.log")
    if not self._sqlplus.run_sql(template.get('validate_ols_policies'), log_file):
      print("OLS Policies validation failed. \n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors("OLS Policies validation failed.", log_file)
        self._print_log_and_exit(log_file, 0)
        return ''
      else:
        self._print_log_and_exit(log_file)
    
    with open(log_file, 'r') as log:
      ols_output = log.read().strip()
    ols_array = ols_output.split(',')

    is_ols_enabled = all(int(x) > 0 for x in ols_array)

    if is_ols_enabled:
      print("Getting OLS policies in schema list")
      log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_ols_policies.log")
      if not self._sqlplus.run_sql(template.get('get_ols_policies_list'), log_file):
        print("Unable to get OLS policies\n")
        if self._env.is_dry_run():
          self._env.add_dry_run_log_errors("Get OLS Policies failed.", log_file)
          self._print_log_and_exit(log_file, 0)
          return ''
        else:
          self._print_log_and_exit(log_file)
      with open(log_file, 'r') as log:
        ols_pls = log.read().strip()
    
      if ols_pls and self._env.TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES.upper() == "FALSE":
        print("OLS Policies found in the database. You have to create the OLS policies in ADB-S database. Data protected by OLS will be unprotected in ADB-S otherwise.\n")
        err_msg = f"[ERROR] Please provide consent to transport tables protected by OLS policies by specifying TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES=TRUE. OLS policies found are : {ols_pls}"
        print(err_msg)
        self._env.add_dry_run_error(err_msg)
        if not self._env.is_dry_run():
          exit(1)
    return ols_pls
  
  def _validate_dvrealm(self, template):
    """DVREALM validation"""
    print("Checking Database Vault protection...")

    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_dvops.log")
    if not self._sqlplus.run_sql(template.get('validate_dvops_protection'), log_file):
      print("Database Vault protection check failed. \n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors("Database Vault protection check failed.", log_file)
        self._print_log_and_exit(log_file, 0)
        return
      else:
        self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      dvops_cnt = log.read().strip()

    if int(dvops_cnt) > 0 and self._env.TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT.upper() == "FALSE":
      print("Database Vault protection is enabled in the database. You have to re-enable database vault protection on the ADB-S database. Transported data will be unprotected otherwise \n")
      err_msg = "[ERROR] Please provide consent to transport Database Vault protected database by specifying TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT=TRUE."
      print(err_msg)
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        exit(1)

    print("Checking Database Vault realms...")
    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_dvrealm.log")
    if not self._sqlplus.run_sql(template.get('validate_dvrealm_policies'), log_file):
      print("Unable to check Database Vault realms. \n")
      if self._env.is_dry_run():
        self._env.add_dry_run_log_errors("Unable to check Database Vault realms.", log_file)
        self._print_log_and_exit(log_file, 0)
        return
      else:
        self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      dvrealm_output = log.read().strip()
    dvrealm_array = dvrealm_output.split(',')

    is_dv_enabled = all(int(x) > 0 for x in dvrealm_array)
    if is_dv_enabled: 
      if not self._env.DVREALM_USER.strip() or not self._env.DVREALM_PASSWORD.strip():
        err_msg = "[ERROR] Database Vault is enabled in the database. Please provide inputs for DVREALM_USER and DVREALM_PASSWORD."
        print(err_msg)
        self._env.add_dry_run_error(err_msg)
        if not self._env.is_dry_run():
          exit(1)

   
      print("Validating of schemas protected by Database Vault realms...")
      sqlplus = SqlPlus(
            self._env.DVREALM_USER,
            self._env.DVREALM_PASSWORD,
            self._env.HOSTNAME,
            self._env.LSNR_PORT,
            self._env.DB_SVC_NAME,
            self._env.ORAHOME
            )
      log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_dvschemas.log")
      if not sqlplus.run_sql(template.get('get_dv_protected_schemas'), log_file, True):
        print("Unable to check schemas protected by Database Vault realms \n")
        if self._env.is_dry_run():
          self._env.add_dry_run_log_errors("Unable to check schemas protected by Database Vault realms.", log_file)
          self._print_log_and_exit(log_file, 0)
          return
        else:
          self._print_log_and_exit(log_file)
      
      with open(log_file, 'r') as log:
        dvschemas_output = log.read().strip()

      print(dvschemas_output)
      if int(dvschemas_output) == 0:
        err_msg = "[ERROR]Please authorize sys as an Data Pump user to transport the Database Vault protected schemas and retry the export"
        print(f"{err_msg}\n")
        self._env.add_dry_run_error(err_msg)
        if not self._env.is_dry_run():
          exit(1)
  
  def _print_log_and_exit(self, _log_file, _exit=1):
    """Print log contents and exit."""
    with open(_log_file, 'r') as log:
      print(log.read())
    if _exit == 1:
      exit(1)


class TTS_SRC_CHECK_STORAGE_BUCKETS:
  """
  Class to check if storage bucket exists
  """
  def __init__(self, env):
    self._env = env
    self._oci_curl = OCI_CURL_SIGNER(env)
    self.tts_src_check_storage_buckets()

  def _validate_bucket(self, url):
    """
    Validate bucket by sending a signed GET request.
    """
    try:
      bucket_url = self._oci_curl.build_bucket_url(url)
      print(f"Validating storage bucket at URL: {url}...")

      self._oci_curl.request(
          method="GET",
          url=bucket_url,
          expected_status=(200,)
      )

      print(f"Successfully validated URI {url}.")
    except Exception as e:
      err_msg = f"Error occurred while checking the bucket {url}: {str(e)}"
      print(f"{err_msg}\n")
      print("Check if the storage bucket exists and credentials are correct. \n")
      self._env.add_dry_run_error(f"{err_msg}. Check if the storage bucket exists and credentials are correct.")
      if not self._env.is_dry_run():
        sys.exit(1)

  def _validate_distinct_bucket_urls(self):
    """
    Validate that backup and bundle buckets are not the same bucket URL.
    """
    try:
      backup_bucket_url = self._oci_curl.build_bucket_url(self._env.TTS_BACKUP_URL)
      bundle_bucket_url = self._oci_curl.build_bucket_url(self._env.TTS_BUNDLE_URL)
    except Exception as e:
      err_msg = f"Error occurred while validating storage bucket URLs: {str(e)}"
      print(f"{err_msg}\n")
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        sys.exit(1)
      return

    if backup_bucket_url == bundle_bucket_url:
      err_msg = "TTS_BACKUP_URL and TTS_BUNDLE_URL must point to different storage buckets."
      print(f"{err_msg}\n")
      print(f"TTS_BACKUP_URL: {self._env.TTS_BACKUP_URL}")
      print(f"TTS_BUNDLE_URL: {self._env.TTS_BUNDLE_URL}")
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        sys.exit(1)

  def tts_src_check_storage_buckets(self):
    """Function to check both backup and bundle storage buckets."""
    self._validate_distinct_bucket_urls()

    print("** Checking backup storage bucket... **")
    self._validate_bucket(self._env.TTS_BACKUP_URL)

    print("** Checking bundle storage bucket... **")
    self._validate_bucket(self._env.TTS_BUNDLE_URL)

    
class TTS_SRC_CREATE_WALLET:
  """
  Class to check if storage bucket exists
  """
  def __init__(self, env):
    self._env = env

  def tts_src_create_backup_wallet(self):
    # Check if the wallet file already exists
    wallet_file_path = os.path.join(self._env.TTS_DIR_PATH, 'cwallet.sso')
    if os.path.isfile(wallet_file_path):
      print("Wallet file already exists in project directory. \n")
      print("Please choose a different project name. \n")
      exit(1)

    # Set JAVA_HOME and update PATH
    os.environ['JAVA_HOME'] = os.path.join(self._env.ORAHOME, 'jdk')
    os.environ['PATH'] = f"{os.environ['JAVA_HOME']}/bin:{os.environ['PATH']}"

    java_path = os.path.join(self._env.ORAHOME, 'jdk', 'bin', 'java')
    # First attempt to run the Java command
    if not self.run_java_oci_installer(java_path):
      # If the first attempt fails, retry with configured JDK8_PATH
      if self._env.JDK8_PATH:
        print("Running with provided JDK8_PATH...")
        jdk8_path = self._env.JDK8_PATH
      else:
        print("\nSet JDK8_PATH=/path-to-jdk8 in tts-backup-env.txt to retry with jdk8...\n")
        print("JDK8_PATH not configured, exiting...")
        sys.exit(1)

      java_path = os.path.join(jdk8_path, 'bin', 'java')
        
      # Retry the Java command with JDK 8
      if not self.run_java_oci_installer(java_path):
          print("Failed to install Oracle Database Cloud Backup Module using JDK 8 also. \n")
          exit(1)

    print("Oracle Database Cloud Backup Module installed successfully. \n")

    oci_config_file = os.path.join(self._env.ORAHOME, 'dbs', f'opc{os.environ["ORACLE_SID"]}.ora')
    try:
      with open(oci_config_file, 'r') as file:
        for line in file:
          if "OPC_WALLET" in line:
            self._env.TTS_WALLET_CRED_ALIAS = line.split("CREDENTIAL_ALIAS=")[1].strip().strip("'")
            return self._env.TTS_WALLET_CRED_ALIAS
    except Exception as e:
        print(f"Error reading OPC config file: {e} \n")
        return None

  def run_java_oci_installer(self, java_path):
    command = [
        java_path, '-jar', self._env.OCI_INSTALLER_PATH,
        '-host', self._env.TTS_BACKUP_URL.split('/n')[0],
        '-pvtKeyFile', self._env.KEY_FILE,
        '-pubFingerPrint', self._env.FINGERPRINT,
        '-tOCID', self._env.TENANCY,
        '-uOCID', self._env.USER,
        '-cOCID', self._env.COMPARTMENT_OCID,
        '-bucket', self._env.TTS_BACKUP_URL.split('/')[-1],
        '-walletDir', self._env.TTS_DIR_PATH,
        '-configFile', os.path.join(self._env.ORAHOME, 'dbs', f'opc{os.environ["ORACLE_SID"]}.ora'),
        '-import-all-trustcerts'
    ]
    if not self._env.use_orahome_libopc():
      command.extend(['-libDir', self._env.PROJECT_DIR_PATH])
    if self._env.OCI_PROXY_HOST and self._env.OCI_PROXY_PORT:
      command.extend(['-proxyHost', self._env.OCI_PROXY_HOST])
      command.extend(['-proxyPort', self._env.OCI_PROXY_PORT])
      
    try:
      process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        bufsize=1
      )
      # Stream output line by line in real time
      for line in process.stdout:
        print(line.strip())

      process.wait()

      if process.returncode != 0:
        print(f"Failed to install Oracle Database Cloud Backup Module\n")
        return False
      print("OCI Backup Module installed successfully.")
      return True
    except Exception as e:
      print(f"An error occurred while running the OCI installer: {e}")
      return False

class TTS_SRC_GATHER_DATA:
  """
  Class to gather source database information
  """
  def __init__(self, env):
    self._env = env

  def tts_src_gather_data(self, template):
    """Function to gather database properties and store them in the db_props_array"""
    try:
      sqlplus = SqlPlus(
          self._env.DBUSER,
          self._env.DBPASSWORD,
          self._env.HOSTNAME,
          self._env.LSNR_PORT,
          self._env.DB_SVC_NAME,
          self._env.ORAHOME
      )
      
      if self._env.DB_VERSION == '11g':
        l_pdb_table = "database"
        l_pdb_type = "dbid"
        l_version_type = "version"
        l_common_clause = ""
      else:
        l_pdb_table = "pdbs"
        l_pdb_type = "guid"
        l_version_type = "version_full"
        l_common_clause = "where common='NO'"

      ts_list = split_into_lines(self._env.TABLESPACES)
      sc_list = split_into_lines(self._env.SCHEMAS)
      
      Configuration.substitutions = {
        'l_pdb_table': l_pdb_table,
        'l_pdb_type': l_pdb_type,
        'l_version_type': l_version_type,
        'ts_list': ts_list.upper(),
        'sc_list': sc_list.upper(),
        'database_name': self._env.DATABASE_NAME,
        'l_common_clause': l_common_clause,
      }
            
      log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_data.log")
      print(f"Executing SQL script to gather data into log file: {log_file}...")

      if not sqlplus.run_sql(template.get('tts_src_gather_data'), log_file):
        print("Data gathering failed. Check the log file for more details. \n")
        with open(log_file, 'r') as log:
          print(log.read())
        return None
      
      # Read log and store output into an array
      with open(log_file, 'r') as log:
        db_properties = log.read().strip()
      
      # Split the output into an array
      db_props_array = [prop.replace('\n', '').strip() for prop in db_properties.split(',')]
      print("Data gathering completed successfully.")
      return db_props_array

    except Exception as e:
      print(f"EXCEPTION : An error occurred during data gathering: {str(e)} \n")
      return None


class TTS_SRC_DIRECTORY_MANAGER:
  """
  Manage the source TTS directory object and validate database-role
  restrictions for directory DDL and Data Pump operations.

  Primary and snapshot standby allow directory DDL.
  Physical standby skips directory DDL and Data Pump.
  Logical standby is not supported.
  """  
  def __init__(self, env, template, create_directory=True):
    self._env = env
    self._database_role = None
    self._database_open_mode = None
    if create_directory:
      self.tts_src_create_directory(template)

  def tts_src_create_directory(self, template, dir_name=None, dir_path=None):
    """Function to create directory object in the database"""
    # Directory DDL is allowed only when the database role 
    # is PRIMARY or SNAPSHOT STANDBY
    if not self._directory_operation_allowed(template, 'create'):
      return False

    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)

    dir_name = dir_name or self._env.TTS_DIR_NAME
    dir_path = dir_path or self._env.TTS_DIR_PATH

    Configuration.substitutions = {
        'tts_dir_name': dir_name,
        'tts_dir_path': dir_path,
        'db_user': self._env.DBUSER,
      }
    
    log_file = os.path.join(self._env.TTS_DIR_PATH, f'{dir_name.lower()}.log')
    if not sqlplus.run_sql(template.get('tts_src_create_directory'), log_file):
      print(f"Failed to create directory {dir_name} \n")
      self._log_error(log_file)
      raise RuntimeError(f"Directory creation failed: {dir_name}\n")
      
    print(f"Directory {dir_name} created successfully.")
    return True
  
  def tts_src_drop_directory(self, template, dir_name=None):
    """Function to drop directory object in the database"""
    # Directory DDL is allowed only when the database role 
    # is PRIMARY or SNAPSHOT STANDBY
    if not self._directory_operation_allowed(template, 'drop'):
      return False

    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)

    dir_name = dir_name or self._env.TTS_DIR_NAME

    Configuration.substitutions = {
        'tts_dir_name': dir_name,
      }
    if not sqlplus.run_sql(template.get('tts_src_drop_directory')):
      print(f"Failed to drop directory {dir_name} \n")
      raise RuntimeError(f"Directory drop failed: {dir_name}\n")
    print(f"Directory {dir_name} dropped successfully.")
    return True
  
  def _log_error(self, log_file):
    """Helper function to log the error details from the log file."""
    if os.path.exists(log_file):
      with open(log_file, 'r') as log:
        error_details = log.read()
        print(f"Error details:\n{error_details} \n")
    else:
      print(f"Log file {log_file} does not exist. \n")

  def _get_database_role(self, template):
    """
    Return the source database role and open mode from v$database.

    The result is cached for the current backup run and shared through _env
    by wallet-copy and RMAN channel allocation.
    """
    if self._database_role is not None:
      self._env.DATABASE_ROLE = self._database_role
      self._env.DATABASE_OPEN_MODE = self._database_open_mode
      return self._database_role, self._database_open_mode

    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                    self._env.HOSTNAME, self._env.LSNR_PORT,
                    self._env.DB_SVC_NAME, self._env.ORAHOME)

    log_dir = getattr(self._env, 'TTS_DIR_PATH', None) or '/tmp'
    log_file = os.path.join(log_dir, f'{self._env.PROJECT_NAME}_tts_database_role.log')

    Configuration.substitutions = {}
    if not sqlplus.run_sql(template.get('tts_src_get_database_role'), log_file):
        self._log_error(log_file)
        raise RuntimeError('Unable to determine database role.')

    try:
        with open(log_file, 'r') as log:
            role_lines = [line.strip() for line in log if '|' in line]

        database_role, open_mode = role_lines[-1].split('|', 1)
        self._database_role = database_role.strip().upper()
        self._database_open_mode = open_mode.strip().upper()

        self._env.DATABASE_ROLE = self._database_role
        self._env.DATABASE_OPEN_MODE = self._database_open_mode

        return self._database_role, self._database_open_mode
    except (OSError, IndexError, ValueError) as err:
        raise RuntimeError(f'Unable to parse database role information: {err}') from err

  def _directory_operation_allowed(self, template, operation):
    """
    Check whether CREATE/DROP DIRECTORY is allowed for the current role.

    A physical standby must not run directory DDL. A logical standby is not
    supported. Primary and snapshot standby may create or drop the object.
    """
    database_role, _ = self._get_database_role(template)

    if database_role in ('PRIMARY', 'SNAPSHOT STANDBY'):
        return True

    if database_role == 'PHYSICAL STANDBY':
        print('\nINFO: Source database is a PHYSICAL STANDBY. Incremental TTS '
            'backup uses only PDB instances open READ ONLY. '
            'To run FINAL_BACKUP=TRUE, convert this standby to a SNAPSHOT '
            'STANDBY before triggering the final backup.\n')
        print(f'Skipping directory {operation}: database role is '
            'PHYSICAL STANDBY.')
        return False

    if database_role == 'LOGICAL STANDBY':
        raise RuntimeError(f'Directory {operation} is not supported on a logical standby. '
            'Contact Oracle Support.')

    raise RuntimeError(f'Directory {operation} is supported only on a primary or snapshot '
        f'standby. Current database role is {database_role}.')

  def tts_src_can_run_expdp(self, template, operation):
    """
    Check whether the requested Data Pump operation can run.

    expdp, including ESTIMATE_ONLY, needs a writable database. Therefore it
    is allowed only on primary or snapshot standby, never physical standby.
    """
    database_role, open_mode = self._get_database_role(template)

    if database_role in ('PRIMARY', 'SNAPSHOT STANDBY'):
        if open_mode != 'READ WRITE':
            raise RuntimeError(f'{operation} requires READ WRITE mode. Current role/open mode: '
                f'{database_role}/{open_mode}.')
        return True

    if database_role == 'PHYSICAL STANDBY':
        # Do not run expdp on physical standby. 
        # Customers must convert to snapshot standby 
        # for expdp validation or before triggering FINAL_BACKUP=TRUE.
        print(f'Skipping {operation}: expdp is not supported on a physical '
            'standby. Convert the standby to a snapshot standby and retry.')
        return False

    if database_role == 'LOGICAL STANDBY':
        raise RuntimeError(f'{operation} is not supported on a logical standby. '
            'Contact Oracle Support.')

    raise RuntimeError(f'{operation} is supported only on a primary or snapshot standby. '
        f'Current database role is {database_role}.')


class TTS_SRC_TDE_KEY_EXPORTER:
  """
  A class to export Transparent Data Encryption (TDE) keys.
  """
  def __init__(self, env, template):
    self._env = env
    self.tts_src_export_tde_keys(template)

  def tts_src_export_tde_keys(self, template):
    """Export TDE keys to the specified path."""
    # Check if TDE_WALLET_STORE_PASSWORD is empty
    if not self._env.TDE_WALLET_STORE_PASSWORD.strip():
      print("[ERROR] Please provide input for TDE_WALLET_STORE_PASSWORD. Encrypted tablespaces exists.")
      self._env.usage()
      exit(1)
      
    tde_keys_path = os.path.join(self._env.TTS_DIR_PATH, self._env.TDE_KEYS_FILE)
    
    if os.path.exists(tde_keys_path):
      os.remove(tde_keys_path)
    
    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)

    Configuration.substitutions = {
        'secret_code': self._env.DB_PROPS_ARRAY[0],
        'tde_keys_path': tde_keys_path,
        'tde_wallet_password': self._env.TDE_WALLET_STORE_PASSWORD
      }
    
    try:
      # if not sqlplus.run_sql(template.get('tts_src_export_tde_keys')) or not os.path.exists(tde_keys_path):
      if not sqlplus.run_sql(template.get('tts_src_export_tde_keys')):
        print("Export TDE Keys failed. \n")
        raise RuntimeError("TDE key export command failed.")
      print(f"TDE keys exported successfully to {tde_keys_path}.")
    except Exception as e:
      print(f"An error occurred while exporting TDE keys: {e}. \n")
      exit(1)

  def tts_src_export_tde_current_key(self, template):
    """Export the current TDE key."""
    tde_keys_path = os.path.join(self._env.TTS_DIR_PATH, self._env.TDE_KEYS_FILE)

    if os.path.exists(tde_keys_path):
        os.remove(tde_keys_path)

    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)
    
    Configuration.substitutions = {
        'secret_code': self._env.DB_PROPS_ARRAY[0],
        'tde_keys_path': tde_keys_path,
        'tde_wallet_password': self._env.TDE_WALLET_STORE_PASSWORD,
        'dst_name': self._env.DB_PROPS_ARRAY[1]
      }
    
    try:
      if not sqlplus.run_sql(template.get('tts_src_export_tde_current_keys')):
        print("Export TDE Current Key failed. \n")
        raise RuntimeError("Current TDE key export command failed.")
      print(f"Current TDE key exported successfully to {tde_keys_path}.")
    except Exception as e:
      print(f"An error occurred while exporting the current TDE key: {e} \n")
      exit(1)


class TTS_SRC_WALLET_COPIER:
  """
  A class to copy Oracle wallet files to specified hosts.
  """
  def __init__(self, env):
    self._env = env

    # Use READ ONLY PDB instances for a physical standby.
    # primay and snapshot continue to use READ WRITE PDB instances.
    database_role = str(getattr(self._env, 'DATABASE_ROLE', '')).upper()
    
    # Read Write host list
    self.hosts = self.parse_hosts(self._env.DB_PROPS_ARRAY[13])
    
    if database_role == 'PHYSICAL STANDBY':
      # Read Only host list
      self.hosts = self.parse_hosts(self._env.DB_PROPS_ARRAY[26])

    self.tts_src_copy_wallet()

  def parse_hosts(self, host_string):
    """Parse host string into a list of hostnames."""
    print(f"Parsing host string: {host_string}.")
    return [host.strip() for host in host_string.split(';') if host.strip()]
  
  def tts_src_copy_wallet(self):
    """Copy the wallet to the specified hosts."""
    current_host = socket.gethostname()
    print(f"Copy wallet into the host list : {self.hosts}.")

    for host in self.hosts:
      host_name = host.split(':')[0]  # Extract hostname
      if current_host == host_name:
        print(f"Skipping wallet copy to current host: {current_host}.")
        continue
      
      if self._env.CLUSTER_MODE.upper() == 'TRUE':
        self.copy_to_host(host_name)    

  def copy_to_host(self, host_name):
    """Copy wallet to the specified host using SSH and SCP."""
    try:
      # Create the remote directory
      cmd_mkdir = f"ssh -oStrictHostKeyChecking=no {host_name} 'mkdir -p {self._env.TTS_DIR_PATH}'"
      print(f"Creating remote directory on {host_name}...")
      subprocess.run(cmd_mkdir, shell=True, check=True)

      # Use SCP to copy the wallet file to other instance
      local_wallet_path = os.path.join(self._env.TTS_DIR_PATH, "cwallet.sso")
      remote_wallet_path = os.path.join(self._env.TTS_DIR_PATH, "cwallet.sso")
      cmd_scp = f"scp -oStrictHostKeyChecking=no {local_wallet_path} {host_name}:{remote_wallet_path}"
      print(f"Copying {local_wallet_path} to {host_name}:{remote_wallet_path}...")
      subprocess.run(cmd_scp, shell=True, check=True)
      print(f"Successfully copied wallet to {host_name}.")

      # Use SCP to copy the libopc.so file to other instance
      if not self._env.use_orahome_libopc():
        local_lipopc_path = os.path.join(self._env.PROJECT_DIR_PATH, "libopc.so")
        remote_lipopc_path = os.path.join(self._env.PROJECT_DIR_PATH, "libopc.so")
        cmd_scp = f"scp -oStrictHostKeyChecking=no {local_lipopc_path} {host_name}:{remote_lipopc_path}"
        print(f"Copying {local_lipopc_path} to {host_name}:{remote_lipopc_path}...")
        subprocess.run(cmd_scp, shell=True, check=True)
        print(f"Successfully copied libopc.so to {host_name}.")
    except subprocess.CalledProcessError as e:
      print(f"Failed to copy wallet to {host_name}: {e} \n")
    except Exception as e:
      print(f"An unexpected error occurred while copying wallet to {host_name}: {e} \n")


class TTS_SRC_RMAN_BACKUP:
  """
  Class to perform RMAN Backup, export schema and tablespaces, and create manifest
  """
  def __init__(self, env):
    self._env = env
    self.SCNS_ARRAY = []
    self.host_array = []

  def get_cpu_count(self):
    """Get the number of processors available."""
    try:
      process = subprocess.run("nproc", shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      cpu_count = int(process.stdout.decode().strip())
      print(f"CPU Count: {cpu_count}")
      return cpu_count
    except subprocess.CalledProcessError as e:
      print(f"Failed to get CPU count: {e.stderr.decode()}\n")
      return 1  # Fallback to 1 CPU if unable to determine

  def _execute_command_args(self, command, command_type):
    """Executes the given command arguments and handles errors."""
    try:
      process = subprocess.Popen(command, stdout=sys.stdout, stderr=sys.stderr, universal_newlines=True)
      process.communicate()

      if process.returncode == 0 or process.returncode == 5:
        print(f"{command_type} executed successfully.")
        return 0
      else:
        print(f"{command_type} failed with return code {process.returncode} \n")
        return 1
    except Exception as e:
        print(f"{command_type} execution encountered an error: {str(e)} \n")
        return 1
  
  def _write_expdp_parfile(self, parfile_name, parfile_content):
    """Create a Data Pump parfile in the project directory."""
    parfile_path = os.path.join(self._env.PROJECT_DIR_PATH, parfile_name)
  
    if os.path.exists(parfile_path):
      os.remove(parfile_path)
  
    with open(parfile_path, "w") as parfile:
      for line in parfile_content.splitlines():
        line = line.strip()
        if line:
          parfile.write(f"{line}\n")
  
    os.chmod(parfile_path, 0o600)
    return parfile_path

  def _execute_expdp_parfile(self, parfile_path):
    """Run expdp using the supplied parfile."""
    expdp_bin = os.path.join(self._env.ORAHOME, "bin", "expdp")
    return self._execute_command_args([expdp_bin, f"parfile={parfile_path}"], "EXPDP")

  def _format_bytes(self, size_bytes):
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    size = float(size_bytes)
    for unit in units:
      if size < 1024 or unit == units[-1]:
        if unit == 'B':
          return f"{int(size)} {unit}"
        return f"{size:.1f} {unit}"
      size /= 1024

  def _parse_expdp_estimate_bytes(self, log_file):
    estimate_pattern = re.compile(
      r'Total estimation using .* method: ([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?B)',
      re.IGNORECASE
    )
    unit_map = {
      'B': 1,
      'KB': 1024,
      'MB': 1024 ** 2,
      'GB': 1024 ** 3,
      'TB': 1024 ** 4,
    }

    with open(log_file, 'r') as log:
      for line in log:
        match = estimate_pattern.search(line)
        if match:
          size = float(match.group(1))
          unit = match.group(2).upper()
          return int(size * unit_map[unit])
    return None

  def tts_src_estimate_xml_dump_space(self, template):
    if self._env.table_with_xml_type.upper() != 'TRUE':
      return

    l_conn_str = (
      f"{self._env.HOSTNAME}:{self._env.LSNR_PORT}/"
      f"{self._env.DB_SVC_NAME} AS SYSDBA"
    )
    job_name_str = ""
    if self._env.ZDM_BASED_TRANSPORT.upper() == "TRUE":
      job_name_str = f'JOB_NAME={self._env.PROJECT_NAME}_ZDM_XML_ESTIMATE'

    exclude_clauses = [
      'EXCLUDE=INDEX:"IN (SELECT index_name FROM dba_xml_indexes '
      f'WHERE upper(index_type) <> \'STRUCTURED\' '
      f'AND table_owner IN ({split_into_lines(self._env.SCHEMAS).upper()}))"'
    ]

    if self._env.INCLUDE_STATISTICS.strip().upper() != "TRUE":
      exclude_clauses.append(
        "EXCLUDE=STATISTICS,INDEX_STATISTICS,TABLE_STATISTICS")
    
    exclude_clause = "\n".join(exclude_clauses)

    Configuration.substitutions = {
        'oracle_home': self._env.ORAHOME,
        'db_user': self._env.DBUSER,
        'db_password': self._env.DBPASSWORD,
        'xml_export_tables': self._env.xml_export_tables,
        'l_conn_str': l_conn_str,
        'tts_dir_name': self._env.TTS_DIR_NAME,
        'xml_dump_file_clause': '',
        'exclude_clause': exclude_clause,
        'xml_estimate_clause': 'ESTIMATE_ONLY=YES\nESTIMATE=BLOCKS',
        'xml_expdp_log_file': 'estimate_xml.log',
        'job_name_str': job_name_str.upper(),
      }

    parfile_path = self._write_expdp_parfile(
        'expdp_xml_estimate.par',
        template.get('tts_src_export_xml_tables')
    )
    log_file = os.path.join(self._env.TTS_DIR_PATH, 'estimate_xml.log')
    try:
      return_val = self._execute_expdp_parfile(parfile_path)
      if return_val == 1:
        err_msg = (
          'Failed to estimate xml_tables.dmp size ' +
          'for local staging validation.'
        )
        self._env.add_dry_run_error(err_msg)
        if not self._env.is_dry_run():
          print(err_msg)
        return 1
    finally:
      if os.path.exists(parfile_path):
        os.remove(parfile_path)

    estimate_bytes = self._parse_expdp_estimate_bytes(log_file)
    if estimate_bytes is None:
      err_msg = (
        'Unable to parse XML dump estimate from ' +
        f"estimate_xml.log. Review: {log_file}"
      )
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        print(err_msg)
      return 1

    required_bytes = estimate_bytes + (2 * 1024 * 1024 * 1024)
    free_bytes = shutil.disk_usage(self._env.TTS_DIR_PATH).free

    print(
      'XML dump estimate using ESTIMATE=BLOCKS: ' +
      f"{self._format_bytes(estimate_bytes)}; " +
      'extra safety buffer: 2.0 GB; ' +
      'required free space for local staging validation: ' +
      f"{self._format_bytes(required_bytes)}; " +
      f"available: {self._format_bytes(free_bytes)}"
    )

    if free_bytes < required_bytes:
      err_msg = (
        'Insufficient local space for xml_tables.dmp staging ' +
        'on this source when ' +
        'using OBJECT_STORAGE. ' +
        f"Estimated dump size={self._format_bytes(estimate_bytes)}, " +
        f"required free space={self._format_bytes(required_bytes)}, " +
        f"available={self._format_bytes(free_bytes)}."
      )
      self._env.add_dry_run_error(err_msg)
      if not self._env.is_dry_run():
        print(err_msg)
      return 1

    return 0

  def _get_object_storage_xml_dump_url(self):
    object_name = f"{os.path.splitext(self._env.BUNDLE_FILE_NAME)[0]}_xml_tables.dmp"
    return OCI_CURL_SIGNER(self._env).build_object_url(
        self._env.TTS_BACKUP_URL,
        object_name
    )

  def _upload_xml_dump_to_object_storage(self, xml_dump_path):
    url = self._get_object_storage_xml_dump_url()
    OCI_CURL_SIGNER(self._env).request(
        method="PUT",
        url=url,
        body_file=xml_dump_path,
        content_type="application/octet-stream",
        expected_status=(200,)
    )
    print(f"XML dump uploaded successfully to {url}.")

  def _execute_rman_script(self, rman_script, log_file, command_type):
    """Run RMAN with script supplied through stdin."""
    rman_bin = os.path.join(self._env.ORAHOME, "bin", "rman")

    try:
      with open(log_file, "w") as outfile:
        process = subprocess.Popen(
          [rman_bin],
          stdin=subprocess.PIPE,
          stdout=subprocess.PIPE,
          stderr=subprocess.STDOUT,
          universal_newlines=True,
          bufsize=1
        )
        process.stdin.write(rman_script)
        if not rman_script.endswith("\n"):
          process.stdin.write("\n")
        process.stdin.close()

        for line in process.stdout:
          sys.stdout.write(line)
          sys.stdout.flush()
          outfile.write(line)
          outfile.flush()

        process.wait()

      if process.returncode == 0 or process.returncode == 5:
        print(f"{command_type} executed successfully.")
        return 0

      print(f"{command_type} failed with return code {process.returncode} \n")
      return 1
    except Exception as e:
      print(f"{command_type} execution encountered an error: {str(e)} \n")
      return 1
  
  def _append_log_to_backup(self, log_filename):
    """Appends the specified log file to backup.log."""
    log_path = os.path.join(self._env.TTS_DIR_PATH, log_filename)
    backup_log_path = os.path.join(self._env.TTS_DIR_PATH, "backup.log")

    if os.path.exists(log_path):
      with open(log_path, 'r') as log_file:
        log_content = log_file.read()
      with open(backup_log_path, 'a') as backup_file:
        backup_file.write(log_content)

  def _append_to_tts_log(self, log_filename):
    """Appends the RMAN/expdp logs to tts.log."""
    log_file_path = os.path.join(self._env.TTS_DIR_PATH, log_filename)
    tts_log_path = os.path.join(self._env.PROJECT_DIR_PATH, self._env.TTS_LOG_FILE)

    if os.path.exists(log_file_path):
      with open(log_file_path, 'r') as log_file:
        log_content = log_file.read()
      with open(tts_log_path, 'a') as tts_file:
        tts_file.write(log_content)

  def tts_src_get_scn(self, template):
    """Get the scn for the next backup"""
    ts_list = split_into_lines(self._env.TABLESPACES)
    
    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD, 
                      self._env.HOSTNAME, self._env.LSNR_PORT, 
                      self._env.DB_SVC_NAME, self._env.ORAHOME)
    Configuration.substitutions = {
        'ts_list': ts_list.upper(),
        'incr_scn': self._env.INCR_SCN, 
      }
    
    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_scn.log")
    if not sqlplus.run_sql(template.get('tts_src_get_scn'), log_file):
      print("SCN gathering failed. \n")
      with open(log_file, 'r') as log:
        print(log.read())
      exit(1)
    
    # Read log and store output into an array
    with open(log_file, 'r') as log:
      scn_output = log.read().strip()
    
    # Split the output into an array
    self.SCNS_ARRAY = scn_output.split(',')
    print(f"SCNs gathered: {self.SCNS_ARRAY}.")

    return True

  def tts_src_get_channel(self):
    """Construct the Channel string"""
    # Physical standby RMAN channels must use only instances where the PDB is
    # open READ ONLY. Primary and snapshot standby use READ WRITE instances.
    database_role = str(getattr(self._env, 'DATABASE_ROLE', '')).upper()

    if database_role == 'PHYSICAL STANDBY':
      self.host_array = self._env.DB_PROPS_ARRAY[26].split(';')
      expected_open_mode = 'READ ONLY'
    else:
      self.host_array = self._env.DB_PROPS_ARRAY[13].split(';')  
      expected_open_mode = 'READ WRITE'

    self._env.CPU_COUNT = self.calculate_cpu_count()

    if not self.host_array:
      if database_role == 'PHYSICAL STANDBY':
        print(f'ERROR: No PDB instance open {expected_open_mode} was found for '
            f'{self._env.DATABASE_NAME} on the physical standby. '
            'Open the PDB READ ONLY on at least one standby RAC instance '
            'before running an incremental TTS backup. '
            'FINAL_BACKUP=TRUE requires conversion to a snapshot standby.')
      else:
        print(f'ERROR: No PDB instance open {expected_open_mode} was found for '
            f'{self._env.DATABASE_NAME}. Ensure the PDB is open READ WRITE '
            'on at least one RAC instance before running TTS backup.')
      sys.exit(1)

    if not self.host_array or self._env.CPU_COUNT <= 0:
      print("No instances or CPUs to construct channel string. Exiting...")
      sys.exit(1)

    rman_parms = ""
    if self._env.STORAGE_TYPE == "FSS":
      rman_parms = f"""
      parms='SBT_LIBRARY=oracle.disksbt,
      ENV=(BACKUP_DIR={self._env.TTS_FSS_MOUNT_DIR}/{self._env.PROJECT_NAME}/datafile)';
      """
    else:
      rman_parms = f"""
      parms='SBT_LIBRARY={self._env.get_libopc_path()}, 
      ENV=(OPC_WALLET="LOCATION=file:{self._env.TTS_DIR_PATH} CREDENTIAL_ALIAS={self._env.TTS_WALLET_CRED_ALIAS}",
      OPC_HOST={self._env.TTS_BACKUP_URL.split('/b/')[0]}, 
      OPC_CONTAINER={self._env.TTS_BACKUP_URL.split('/b/')[1]}, 
      OPC_AUTH_SCHEME=BMC,
      OPC_CHUNK_SIZE=524288000, 
      _OPC_BUFFER_WRITE=TRUE, 
      _OPC_BUFFER_READ=TRUE, 
      _OPC_TAG_METERING=FALSE)';
      """

    if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
      libopc_path = self._env.get_libopc_path()
      if not os.path.isfile(libopc_path):
        raise FileNotFoundError(
          f"libopc.so not found at {libopc_path}")
      
    count = 0
    current_host = socket.gethostname()
    for c in range(1, self._env.CPU_COUNT + 1):
      for ele in self.host_array:
        if count >= self._env.MAX_CHANNELS:
            break
        host_name, instance_name = ele.split(':')
        # Skip allocating channel in other racn instances
        # if CLUSTER_MODE is set to FALSE
        if self._env.CLUSTER_MODE.upper() == 'FALSE':
          if host_name != current_host:
            continue
        
        count += 1
       
        l_dedicated_clause = ""
        connection_mode = self._env.DB_PROPS_ARRAY[25].strip().upper()
        if connection_mode in ("SHARED", "POOLED"):
          l_dedicated_clause = ":dedicated"
        if self._env.DB_VERSION == '11g':
          l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}{l_dedicated_clause}"
        else:
          l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}{l_dedicated_clause} as sysdba"

        self._env.CHANNEL_STRING += f"""
        allocate channel c_{instance_name}_{c} device type sbt 
        connect '{self._env.DBUSER}/{self._env.DBPASSWORD}@{l_conn_str}' 
        {rman_parms}
        """
    
    print(f"Channel string constructed with {count} channels.")
    return True

  def calculate_cpu_count(self):
    """Calculate the CPU count based on the environment configuration."""
    if self._env.PARALLELISM == 0:
      cpu_count = self._env.CPU_COUNT
      if cpu_count <= 0:
        cpu_count = self.get_cpu_count()
      # We use 25% of cpu processors with a cap of 4
      cpu_count = (cpu_count + 4 - 1) // 4
      return min(cpu_count, 4)
    else:
      # We adjust parallelism = instances * cpu_count
      if self._env.CLUSTER_MODE.upper() == 'FALSE':
        return self._env.PARALLELISM
      else:
        return (self._env.PARALLELISM + len(self.host_array) - 1) // len(self.host_array)

  def check_log_for_errors(self, log_file, require_rman_backup_completion=False):
    """Checks the RMAN/EXPDP log file for errors and raises an exception if any are found."""
    try:
      with open(log_file, 'r') as log:
        log_contents = log.read()
        rman_backup_started = False
        rman_backup_finished = False

        for line in log_contents.splitlines():
          if "Starting backup at" in line:
            rman_backup_started = True
          if "Finished backup at" in line:
            rman_backup_finished = True
          if "RMAN-" in line.upper() and "WARNING" not in line.upper():
            print(f"RMAN errors found. {line}")
            print(f"Please check logs at {log_file}.")
            return False
          if "EXPORT" in line and "stopped due to fatal error" in line:
            print(f"EXPDP errors found. {line}")
            print(f"Please check logs at {log_file}.")
            return False
        if require_rman_backup_completion:
          if not rman_backup_started:
            print("RMAN backup start marker not found.")
            print(f"Please check logs at {log_file}.")
            return False
          if not rman_backup_finished:
            print("RMAN backup did not complete successfully. Missing 'Finished backup at' marker.")
            print(f"Please check logs at {log_file}.")
            return False
      return True
    except Exception as e:
      print(f"Error reading RMAN/EXPDP log file {log_file}: {str(e)}")
      return False

  def tts_src_backup_tablespaces(self, backup_type, template):
    """Perform RMAN BACKUP"""
    if not self.host_array:
      print("No host array available for backup. \n")
      return False

    ele = self.host_array[0]
    host_name, instance_name = ele.split(':')
    compressed = ""
    allow_inconsistent = ""
    tablespace_dump_clause = ""
    backup_string = ""
    encryption_on_clause = "set encryption on;"
    backup_set_transport = ""
    encryption_off_clause = ""
    command_id_clause = ""
    tablespace_clause = self._env.encrypted_tablespaces
    section_size_clause = ""
    
    if backup_type == "unencrypted":
      encryption_on_clause = f'set encryption on identified by "{self._env.DB_PROPS_ARRAY[0]}" only;'
      tablespace_clause = self._env.unencrypted_tablespaces

    if self._env.FINAL_BACKUP.upper() == "TRUE":
      if self._env.DB_VERSION != '11g':
        tablespace_dump_clause = (
            f"datapump format '{self._env.PROJECT_NAME}_DATAPUMP_%d_%U' "
            f"dump file 'tablespace.dmp' "
            f"destination '{self._env.TTS_DIR_PATH}'"
        )
    else:
      compressed = "compressed"
      if self._env.DB_VERSION != '11g':
        allow_inconsistent = "allow inconsistent"

    # Remove DATAPUMP Clause from rman restore
    tablespace_dump_clause = ""

    # 11g -> for transport not supported, add section size clause
    # 12c/19c : 
    #   if src_platform = 13 : no need of for transport, add section size clause
    #   else : for transport is required and
    #     if version < 19.21 : section size not supported along with for transport
    #     else : section size supported with for transport along with for transport
    version_full_list = self._env.version_full.split('.')
    if self._env.platform_id != 13 or (int(version_full_list[0]), int(version_full_list[1])) >= (19, 21):
      backup_set_transport = "for transport "
    
    if self._env.platform_id == 13 or (int(version_full_list[0]), int(version_full_list[1])) >= (19, 21):
      section_size_clause = "section size 200G "

    if self._env.DB_VERSION == '11g':
      backup_set_transport = ""
      section_size_clause = "section size 200G "

    if section_size_clause == "":
      print(
          "WARNING: RMAN SECTION SIZE is not supported for cross-platform "
          "transportable tablespace operations on this database version "
          f"({self._env.version_full}). Proceeding without SECTION SIZE; "
          "backup and restore performance may be impacted."
      )

    # TODO
    # Generate dynamic section size based on parallelism
    # section_size = size_of_largest_tbs // parallelism
    # It generates # of backuppieces = parallelism
    # Round off to next hundred
    # retrieve the largest tbs size (datafile size)
    # largest_tbs_size = max(float(self._env.DB_PROPS_ARRAY[19]),float(self._env.DB_PROPS_ARRAY[20]))
    # calculate section size
    # section_size = largest_tbs_size // self._env.PARALLELISM
    # round off the section_size to next 100
    # section_size = math.ceil(section_size / 100) * 100
    # 200 <= section_size <= 500
    # section_size = max(section_size, 200) 
    # section_size = min(section_size, 500)
    # section_size = int(section_size)
    
    # Use level backup for 11G database to utilise section size
    if self._env.DB_VERSION == '11g':  
      if self._env.BACKUP_LEVEL == 0:
        incremental_clause = "incremental level 0"
      else:
        incremental_clause = "incremental level 1"
    else:
      if self._env.BACKUP_LEVEL == 0:
        incremental_clause = ""
      else:
        incremental_clause = f"incremental from scn {self._env.INCR_SCN}"

    backup_string += (
      f"backup as {compressed} backupset {backup_set_transport}"
      f"{allow_inconsistent} {incremental_clause} "
      f"{section_size_clause}"
      f"tablespace {tablespace_clause.upper()} "
      f"format '{self._env.PROJECT_NAME}_%d_%U' "
      f"{tablespace_dump_clause};"
    )
    
    l_dedicated_clause = ""
    connection_mode = self._env.DB_PROPS_ARRAY[25].strip().upper()
    if connection_mode in ("SHARED", "POOLED"):
      l_dedicated_clause = ":dedicated"
    if self._env.DB_VERSION == '11g':
      l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}{l_dedicated_clause}"
    else:
      l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}{l_dedicated_clause} as sysdba"

    if self._env.STORAGE_TYPE == "FSS":
      encryption_off_clause = "set encryption off;"
      encryption_on_clause = ""
    
    if self._env.ZDM_BASED_TRANSPORT.upper() == "TRUE":
      command_id_clause = f'{self._env.PROJECT_NAME}_ZDM_level_{self._env.BACKUP_LEVEL}_{backup_type}'
    else:
      command_id_clause = f'{self._env.PROJECT_NAME}_{backup_type}'
    
    Configuration.substitutions = {
        'oracle_home': self._env.ORAHOME,
        'tts_dir_name': self._env.TTS_DIR_PATH,
        'backup_type': backup_type,
        'db_user': self._env.DBUSER,
        'db_password': self._env.DBPASSWORD,
        'l_conn_str': l_conn_str,
        'encryption_on_clause': encryption_on_clause,
        'encryption_off_clause': encryption_off_clause,
        'backup_string': backup_string,
        'channel_string': self._env.CHANNEL_STRING,
        'command_id_clause': command_id_clause.upper(),
      }
    
    log_file = f"{self._env.TTS_DIR_PATH}/backup_{backup_type}.log"
    return_val = self._execute_rman_script(
        template.get('tts_src_backup_tablespaces'),
        log_file,
        "RMAN"
    )

    # Check the log file for errors after execution
    log_file = f"{self._env.TTS_DIR_PATH}/backup_{backup_type}.log"

    if not self.check_log_for_errors(log_file, require_rman_backup_completion=True):
      print(f"Error found in RMAN log file: {log_file}. Backup failed.")
      return 1
    rman_log_file = ""
    if backup_type == "encrypted":
      rman_log_file = "backup_encrypted.log"
    if backup_type == "unencrypted":
      rman_log_file = "backup_unencrypted.log"

    self._env.RMAN_LOGFILES.append(rman_log_file)

    # Append schema RMAN logs to tts log file
    self._append_to_tts_log(rman_log_file)
    return return_val

  def tts_src_export_schema(self, template):
    """Export schemas"""
    schema_dump_path = os.path.join(self._env.TTS_DIR_PATH, 'schema.dmp')
    if os.path.exists(schema_dump_path):
      os.remove(schema_dump_path)
    
    l_conn_str = f"{self._env.HOSTNAME}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME} AS SYSDBA"

    job_name_str = ""
    if self._env.ZDM_BASED_TRANSPORT.upper() == "TRUE":
      job_name_str = f'JOB_NAME={self._env.PROJECT_NAME}_ZDM_schema_level_{self._env.BACKUP_LEVEL}'

    Configuration.substitutions = {
        'oracle_home': self._env.ORAHOME,
        'db_user': self._env.DBUSER,
        'db_password': self._env.DBPASSWORD,
        'l_conn_str': l_conn_str,
        'schemas': self._env.SCHEMAS.upper(),
        'tts_dir_name': self._env.TTS_DIR_NAME,
        'job_name_str': job_name_str.upper(),
      }
    parfile_path = self._write_expdp_parfile("expdp_schema.par", template.get("tts_src_export_schema"))
    try:
      return_val = self._execute_expdp_parfile(parfile_path)
      if return_val:
        print("EXPDP tablespace metadata export failed.")
        print(f"Generated EXPDP parfile ({parfile_path}) [USERID redacted]:")

        with open(parfile_path, "r") as parfile:
          for line in parfile:
            if line.strip().upper().startswith("USERID="):
              print("  USERID=<redacted>")
            else:
              print(f"  {line.rstrip()}")
    finally:
      if os.path.exists(parfile_path):
        os.remove(parfile_path)
    expdp_log_file = "export.log"
    
    # Append logs to expdp log file
    self._append_log_to_backup(expdp_log_file)
    
    # Append schema expdp logs to tts log file
    self._append_to_tts_log(expdp_log_file)

    # Check the log file for errors after execution
    log_file = f"{self._env.TTS_DIR_PATH}/{expdp_log_file}"

    if not self.check_log_for_errors(log_file):
      print(f"Error found in EXPDP log file: {log_file}. Export of Schema Metadata failed.")
      return 1
    return return_val

  def tts_src_export_xml_tables(self, template):
    """Export XML Tables"""
    xml_dir_name = self._env.TTS_DIR_NAME
    xml_dump_file = 'xml_tables.dmp'

    xml_expdp_log_file = 'export_xml.log'
    cleanup_dir_name = None
    local_xml_dump_path = None

    if self._env.STORAGE_TYPE == "FSS":
      xml_dir_name = "TTS_XML_DUMP_DIR"
      # Keep export_xml.log in TTS_DUMP_DIR while xml_tables.dmp goes to FSS.
      xml_expdp_log_file = f"{self._env.TTS_DIR_NAME}:export_xml.log"
      cleanup_dir_name = xml_dir_name
      local_xml_dump_path = os.path.join(
          self._env.TTS_FSS_MOUNT_DIR,
          self._env.PROJECT_NAME,
          'datafile',
          xml_dump_file
      )
      if os.path.exists(local_xml_dump_path):
        os.remove(local_xml_dump_path)
      directory_manager = TTS_SRC_DIRECTORY_MANAGER(
        self._env, template, create_directory=False
      )
      directory_manager.tts_src_create_directory(
          template,
          dir_name=xml_dir_name,
          dir_path=os.path.dirname(local_xml_dump_path)
      )
    else:
      local_xml_dump_path = os.path.join(self._env.TTS_DIR_PATH, xml_dump_file)
      if os.path.exists(local_xml_dump_path):
        os.remove(local_xml_dump_path)
    
    l_conn_str = (
      f"{self._env.HOSTNAME}:{self._env.LSNR_PORT}/"
      f"{self._env.DB_SVC_NAME} AS SYSDBA"
    )

    job_name_str = ""
    if self._env.ZDM_BASED_TRANSPORT.upper() == "TRUE":
      job_name_str = f'JOB_NAME={self._env.PROJECT_NAME}_ZDM_XML_EXPORT'

    exclude_clauses = [
      'EXCLUDE=INDEX:"IN (SELECT index_name FROM dba_xml_indexes '
      f'WHERE upper(index_type) <> \'STRUCTURED\' '
      f'AND table_owner IN ({split_into_lines(self._env.SCHEMAS).upper()}))"'
    ]

    if self._env.INCLUDE_STATISTICS.strip().upper() != "TRUE":
      exclude_clauses.append(
        "EXCLUDE=STATISTICS,INDEX_STATISTICS,TABLE_STATISTICS")
    
    exclude_clause = "\n".join(exclude_clauses)

    Configuration.substitutions = {
        'oracle_home': self._env.ORAHOME,
        'db_user': self._env.DBUSER,
        'db_password': self._env.DBPASSWORD,
        'xml_export_tables': self._env.xml_export_tables,
        'l_conn_str': l_conn_str,
        'tts_dir_name': xml_dir_name,
        'xml_dump_file_clause': f'DUMPFILE={xml_dump_file}',
        'xml_estimate_clause': '',
        'xml_expdp_log_file': xml_expdp_log_file,
        'exclude_clause': exclude_clause,
        'job_name_str': job_name_str.upper(),
      }

    parfile_path = self._write_expdp_parfile(
      "expdp_xml.par",
      template.get("tts_src_export_xml_tables")
    )
    try:
      return_val = self._execute_expdp_parfile(parfile_path)
      if return_val:
        print("EXPDP tablespace metadata export failed.")
        print(f"Generated EXPDP parfile ({parfile_path}) [USERID redacted]:")

        with open(parfile_path, "r") as parfile:
          for line in parfile:
            if line.strip().upper().startswith("USERID="):
              print("  USERID=<redacted>")
            else:
              print(f"  {line.rstrip()}")
    finally:
      if os.path.exists(parfile_path):
        os.remove(parfile_path)
      if cleanup_dir_name:
        directory_manager.tts_src_drop_directory(
            template,
            dir_name=cleanup_dir_name
        )
    expdp_log_file = "export_xml.log"
    
    # Append logs to expdp log file
    self._append_log_to_backup(expdp_log_file)
    
    # Append schema expdp logs to tts log file
    self._append_to_tts_log(expdp_log_file)

    # Check the log file for errors after execution
    log_file = f"{self._env.TTS_DIR_PATH}/{expdp_log_file}"

    if not self.check_log_for_errors(log_file):
      print(
        f"Error found in EXPDP log file: {log_file}. "
        "Export of XML tables Metadata failed."
      )
      return 1
    
    if return_val == 0 and self._env.STORAGE_TYPE == "OBJECT_STORAGE":
      self._upload_xml_dump_to_object_storage(local_xml_dump_path)
      if os.path.exists(local_xml_dump_path):
        os.remove(local_xml_dump_path)
    return return_val
  
  def _build_exclude_table_clauses(self, table_names, max_clause_len=3900):
    """
    Build one or more EXCLUDE=TABLE:"IN (...)" lines, keeping each line
    below the Data Pump parameter-size limit.
    """

    def quoted_name(table_name: str) -> str:
        return "'{0}'".format(table_name.replace("'", "''"))

    clause_prefix = 'EXCLUDE=TABLE:"IN ('
    clause_suffix = ')"'

    exclude_clauses = []
    current_chunk = []
    current_clause_length = len(clause_prefix) + len(clause_suffix)

    for table_name in table_names:
        quoted_table_name = quoted_name(table_name)
        additional_length = (
            len(quoted_table_name) + (1 if current_chunk else 0)
        )

        if (
            current_chunk
            and current_clause_length + additional_length > max_clause_len
        ):
            exclude_clauses.append(
                clause_prefix + ",".join(current_chunk) + clause_suffix
            )
            current_chunk = [quoted_table_name]
            current_clause_length = (
                len(clause_prefix)
                + len(clause_suffix)
                + len(quoted_table_name)
            )
        else:
            current_chunk.append(quoted_table_name)
            current_clause_length += additional_length

    if current_chunk:
        exclude_clauses.append(
            clause_prefix + ",".join(current_chunk) + clause_suffix
        )

    return exclude_clauses
  
  def tts_src_export_tablespaces(self, template, _validate=False):
    """Export tablespaces"""
    if _validate:
      tablespace_dump_path = os.path.join(self._env.TTS_DIR_PATH, 'validate_tablespace.dmp')
    else:
      tablespace_dump_path = os.path.join(self._env.TTS_DIR_PATH, 'tablespace.dmp')
    if os.path.exists(tablespace_dump_path):
        os.remove(tablespace_dump_path)  

    l_conn_str = f"{self._env.HOSTNAME}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME} AS SYSDBA"
      
    exclude_table_list = [
        tbl.strip()
        for tbl in self._env.EXCLUDE_TABLES.split(',')
        if tbl.strip()
    ]
    xml_table_list = [
        tbl.strip().split('.')[-1].replace('"', '')
        for tbl in self._env.xml_export_tables.split(',')
        if tbl.strip()
    ]
    xml_index_path_table_list = [
        tbl.strip()
        for tbl in self._env.xml_index_path_tables.split(',')
        if tbl.strip()
    ]
    tables_to_exclude = list(dict.fromkeys(
        exclude_table_list + xml_table_list + xml_index_path_table_list))

    exclude_clauses = self._build_exclude_table_clauses(tables_to_exclude)

    if self._env.INCLUDE_STATISTICS.strip().upper() != "TRUE":
        exclude_clauses.append(
            "EXCLUDE=STATISTICS,INDEX_STATISTICS,TABLE_STATISTICS"
        )

    exclude_clause = "\n".join(exclude_clauses) 
    
    job_name_str = ""
    if self._env.ZDM_BASED_TRANSPORT.upper() == "TRUE":
      job_name_str =  f'JOB_NAME={self._env.PROJECT_NAME}_ZDM_tablespace_level_{self._env.BACKUP_LEVEL}'

    expdp_log_file = 'validate_export_tablespace.log' if _validate else 'export_tablespace.log'
    Configuration.substitutions = {
        'oracle_home': self._env.ORAHOME,
        'db_user': self._env.DBUSER,
        'db_password': self._env.DBPASSWORD,
        'l_conn_str': l_conn_str,
        'tablespaces': self._env.TABLESPACES.upper(),
        'tts_dir_name': self._env.TTS_DIR_NAME,
        'exclude_clause': exclude_clause,
        'job_name_str': job_name_str.upper(),
        'dump_file': 'validate_tablespace.dmp' if _validate else 'tablespace.dmp',
        'expdp_log_file': expdp_log_file,
        'tts_closure_check': 'TTS_CLOSURE_CHECK=TEST_MODE' if _validate else '',
      }


    parfile_path = self._write_expdp_parfile("expdp_tablespace.par", template.get("tts_src_export_tablespaces"))
    try:
      return_val = self._execute_expdp_parfile(parfile_path)
      if return_val:
        print("EXPDP tablespace metadata export failed.")
        print(f"Generated EXPDP parfile ({parfile_path}) [USERID redacted]:")

        with open(parfile_path, "r") as parfile:
          for line in parfile:
            if line.strip().upper().startswith("USERID="):
              print("  USERID=<redacted>")
            else:
              print(f"  {line.rstrip()}")
    finally:
      if os.path.exists(parfile_path):
        os.remove(parfile_path)
      
    # Append logs to expdp log file
    self._append_log_to_backup(expdp_log_file)
    
    # Append tablespace expdp logs to tts log file
    self._append_to_tts_log(expdp_log_file)

    # Check the log file for errors after execution
    log_file = f"{self._env.TTS_DIR_PATH}/{expdp_log_file}"

    if not self.check_log_for_errors(log_file):
      print(f"Error found in EXPDP log file: {log_file}. Export of Tablespace Metadata failed.")
      return 1
    return return_val

  def tts_src_create_manifest(self):
    """Create manifest"""
    ts_list = self._env.TABLESPACES.split(',')
    schema_list = self._env.SCHEMAS.split(',')

    bf_ts_list = self._env.bigfile_tablespaces.split(',')
    sf_ts_list = self._env.smallfile_tablespaces.split(',')
    en_ts_list = self._env.encrypted_tablespaces.split(',')
    ue_ts_list = self._env.unencrypted_tablespaces.split(',')
    redaction_list = self._env.redaction_policies_list.split(',')
    ols_list = self._env.ols_policies_list.split(',')
    role_list = self._env.role_list.split(',')
    mview_schemas = self._env.mview_schemas.split(',')
    sched_cred_list = self._env.sched_cred_list.split(',')

    exclude_table_list = self._env.EXCLUDE_TABLES.split(',')
    common_user_remap = _parse_common_user_remap(self._env.COMMON_USER_REMAP)

    new_backup_level = next_backup_level(self._env.BACKUP_LEVEL)
    
    database_role = str(getattr(self._env, 'DATABASE_ROLE', '')).strip().upper()

    if self._env.TBS_READ_ONLY == "true" or database_role == 'PHYSICAL STANDBY':
      next_scn = self.SCNS_ARRAY[1]
    else:
      next_scn = self.SCNS_ARRAY[0]
    
    manifest_data = {
      "epic_name": self._env.PROJECT_NAME,
      "pdbname": self._env.DATABASE_NAME,
      "pdb_guid": self._env.DB_PROPS_ARRAY[0],
      "schemas": [sc.upper() for sc in schema_list],
      "common_user_remap": [
        {"source_schema": source, "target_schema": target}
        for source, target in common_user_remap.items()
      ],
      "tablespaces": [ts.upper() for ts in ts_list],
      "tde_keys_file": self._env.TDE_KEYS_FILE,
      "uri": self._env.TTS_BACKUP_URL if self._env.STORAGE_TYPE == "OBJECT_STORAGE" else None,
      "backupdir": self._env.TTS_FSS_MOUNT_DIR if self._env.STORAGE_TYPE == "FSS" else None,
      "cred_alias": self._env.TTS_WALLET_CRED_ALIAS,
      "dst_version": int(self._env.DB_PROPS_ARRAY[1]),
      "platform": self._env.DB_PROPS_ARRAY[2],
      "platform_id": int(self._env.DB_PROPS_ARRAY[3]),
      "incr_scn": str(next_scn),
      "nls_charset": self._env.DB_PROPS_ARRAY[5],
      "nls_ncharset": self._env.DB_PROPS_ARRAY[6],
      "db_edition": self._env.DB_PROPS_ARRAY[7],
      "db_version": self._env.DB_PROPS_ARRAY[8],
      "db_version_full": self._env.DB_PROPS_ARRAY[9],
      "table_with_xml_type": self._env.table_with_xml_type,
      "dbtimezone": self._env.DB_PROPS_ARRAY[11],
      "storage_size": self._env.DB_PROPS_ARRAY[12],
      "sf_additional_size": self._env.DB_PROPS_ARRAY[19],
      "bf_additional_size": self._env.DB_PROPS_ARRAY[20],
      "backup_log": [],
      "restore_log": {},
      "parallelism": self._env.PARALLELISM,
      "tbs_read_only": self._env.TBS_READ_ONLY,
      "final_backup": self._env.FINAL_BACKUP.upper(),
      "backup_level": self._env.BACKUP_LEVEL,
      "backup_logfile": self._env.RMAN_LOGFILES,
      "bigfile_tablespaces": [ts.upper() for ts in bf_ts_list],
      "smallfile_tablespaces": [ts.upper() for ts in sf_ts_list],
      "encrypted_tablespaces": [ts.upper() for ts in en_ts_list],
      "unencrypted_tablespaces": [ts.upper() for ts in ue_ts_list],
      "role_list": [rl for rl in role_list],
      "exclude_tables_list": [tbl for tbl in exclude_table_list],
      "mview_schemas": [mvs for mvs in mview_schemas],
      "sched_cred_list": [cred for cred in sched_cred_list],
      "src_compatible": self._env.DB_PROPS_ARRAY[24],
      "redaction_policies": [ps.upper() for ps in redaction_list],
      "ols_policies": [ps.upper() for ps in ols_list]
    }

    manifest_path = os.path.join(self._env.TTS_DIR_PATH, 'manifest.log')
    with open(manifest_path, 'w') as manifest_file:
      json.dump(manifest_data, manifest_file, indent=2)

    print("Manifest creation successful.")
    
    # Write project file
    project_data = {
      "project_name": self._env.PROJECT_NAME,
      "backup_level": new_backup_level,
      "incr_scn": next_scn,
      "tablespaces": ts_list
    }

    if self._env.FINAL_BACKUP == "TRUE":
      project_data['final_backup_complete'] = "TRUE"

    project_file_path = self._env.TTS_PROJECT_FILE
    with open(project_file_path, 'w') as project_file:
      json.dump(project_data, project_file, indent=2)

    print(f"Updated {self._env.TTS_PROJECT_FILE} Successful.")


class TTS_SRC_CLEANUP_MANAGER:
  def __init__(self, env):
    self._env = env
  
  def _get_rac_hosts(self, template):
    fd, host_file = tempfile.mkstemp(prefix="tts_cleanup_hosts_", suffix=".log")
    os.close(fd)
    try:
      sqlplus = SqlPlus(
          self._env.DBUSER,
          self._env.DBPASSWORD,
          self._env.HOSTNAME,
          self._env.LSNR_PORT,
          self._env.DB_SVC_NAME,
          self._env.ORAHOME
      )
      if not sqlplus.run_sql(template.get('tts_src_get_rac_hosts'), host_file):
        raise RuntimeError("Unable to discover RAC hosts for --cleanup.")

      with open(host_file, 'r') as file_handle:
        hosts = [line.strip() for line in file_handle if line.strip()]
    finally:
      try:
        os.remove(host_file)
      except OSError:
        pass
      
    hosts.append(socket.gethostname())
    unique_hosts = []
    for host in hosts:
      host = host.lower()
      if host not in unique_hosts:
        unique_hosts.append(host)
    
    return unique_hosts

  def tts_src_cleanup(self, template):
    project_dir_path = os.path.join(scriptpath(), self._env.PROJECT_NAME)
    rac_hosts = self._get_rac_hosts(template)

    # Drop first so no database directory object points at deleted storage.
    directory_manager = TTS_SRC_DIRECTORY_MANAGER(self._env, template, create_directory=False)
    directory_manager.tts_src_drop_directory(template)

    failures = []
    try:
      if os.path.exists(project_dir_path):
        shutil.rmtree(project_dir_path)
        print(f"Removed local project directory: {project_dir_path}")
    except Exception as err:
      failures.append(f"local host: {err}")

    current_host = socket.gethostname().lower()
    for host in rac_hosts:
      if host == current_host:
        continue
      try:
        remote_command = f"rm -rf -- {shlex.quote(project_dir_path)}"
        subprocess.run(["ssh", "-oBatchMode=yes", "-oConnectTimeout=15", "-oConnectionAttempts=1", host, remote_command], check=True, timeout=300)
        print(f"Removed project directory on {host}: {project_dir_path}")
      except subprocess.TimeoutExpired:
        failures.append(f"{host}: remote cleanup timed out after 300 seconds")
      except subprocess.CalledProcessError as err:
        failures.append(f"{host}: {err}")
    
    if failures:
      raise RuntimeError("Cleanup completed with failures:\n" + "\n".join(failures))
    
    print("TTS project cleanup completed successfully.")


class TTS_SRC_BUNDLE_MANAGER:
  """
  A class to manage creating and uploading bundles for transport.
  """
  def __init__(self, env):
    self._env = env
    self.tts_src_create_bundle()
    self._oci_curl = OCI_CURL_SIGNER(env)
  
  def tts_src_create_bundle(self):
    """Create a bundle file for transport."""
    current_dir = os.getcwd()
    print(f"Creating bundle file: {self._env.TTS_BUNDLE_FILE}.")

    # Change to project directory
    os.chdir(self._env.PROJECT_DIR_PATH)
    bundle_dir = os.path.basename(self._env.TTS_DIR_PATH)
    
    schema_dump = ""
    tablespace_dump = ""
    # Determine if final backup is requested
    if self._env.FINAL_BACKUP.upper() == "TRUE":
      tablespace_dump = os.path.join(bundle_dir, "tablespace.dmp")
      schema_dump = os.path.join(bundle_dir, "schema.dmp")

    tde_path = ""
    
    # Check if there are encrypted tablespaces
    if len([ts for ts in self._env.encrypted_tablespaces.split(',') if ts.strip()]) > 0:
        tde_path = os.path.join(bundle_dir, self._env.TDE_KEYS_FILE)

    # Create the tar.gz bundle
    try:
      with tarfile.open(self._env.TTS_BUNDLE_FILE, "w:gz") as tar:
        tar.add(os.path.join(bundle_dir, "manifest.log"), arcname=f"{os.path.basename(bundle_dir)}/manifest.log")
        for log_file in os.listdir(bundle_dir):
          if "encrypted.log" in log_file:
            tar.add(os.path.join(bundle_dir, log_file), arcname=f"{os.path.basename(bundle_dir)}/{log_file}")
        if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
          tar.add(os.path.join(bundle_dir, "cwallet.sso"), arcname=f"{os.path.basename(bundle_dir)}/cwallet.sso")
        if schema_dump:
          tar.add(schema_dump, arcname=f"{os.path.basename(bundle_dir)}/schema.dmp")
        if tablespace_dump:
          tar.add(tablespace_dump, arcname=f"{os.path.basename(bundle_dir)}/tablespace.dmp")
        if tde_path:
          tar.add(tde_path, arcname=f"{os.path.basename(bundle_dir)}/{self._env.TDE_KEYS_FILE}")
      print(f"Bundle created successfully: {self._env.TTS_BUNDLE_FILE}.")
    except Exception as e:
      print(f"An error occurred while creating the bundle: {e} \n")
      exit(1)


    # Clean up the bundle directory
    try:
      shutil.rmtree(bundle_dir)
      print(f"Cleaned up the bundle directory: {bundle_dir}.")
    except Exception as e:
      print(f"Failed to clean up the bundle directory: {e} \n")
    
    # Change back to the original working directory
    os.chdir(current_dir)

    # Cleanup libopc.so downloaded by OCI Installer
    if self._env.STORAGE_TYPE == "OBJECT_STORAGE" and not self._env.use_orahome_libopc():
      os.remove(self._env.get_libopc_path())
  
  def tts_src_upload_bundle(self):
    """
    Upload the created bundle to Object Storage or FSS.
    """
    try:
      if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
        url = self._oci_curl.build_object_url(
          self._env.TTS_BUNDLE_URL,
          self._env.BUNDLE_FILE_NAME
        )

        self._oci_curl.request(
          method="PUT",
          url=url,
          body_file=self._env.TTS_BUNDLE_FILE,
          content_type="application/octet-stream",
          expected_status=(200,)
        )

        print(f"Bundle uploaded successfully to {url}.")
        self.display_success_message(url)
      elif self._env.STORAGE_TYPE == "FSS":
        fss_mount_path = f"{self._env.TTS_FSS_MOUNT_DIR}/{self._env.PROJECT_NAME}/metadata/"
        fss_bundle_uri = f"{self._env.TTS_FSS_CONFIG}/{self._env.BUNDLE_FILE_NAME}"
        os.system(f"cp {self._env.TTS_BUNDLE_FILE} {fss_mount_path}")
        print(f"Bundle copied successfully to {fss_mount_path}.")
        self.display_success_message(fss_bundle_uri)
    except Exception as e:
      print(f"Error occurred during the upload_bundle: {e} \n")
      sys.exit(1) 
  
  def display_success_message(self, url):
      """Display a message upon successful upload."""
      print("---------")
      min_storage_size = float(self._env.DB_PROPS_ARRAY[12]) + max(float(self._env.DB_PROPS_ARRAY[19]),
                                                                   float(self._env.DB_PROPS_ARRAY[20]))
      print(f"Create or Update a database in ADB-S cloud with minimum storage size of {min_storage_size}GB")
      print("Under Migration, enable Import Transportable Tablespaces and provide this transportable tablespace bundle URI:")
      print(url)
      print("---------")

class Template(object):
  def __init__(self, filename):
    self._configpath = os.path.join(scriptpath(), filename)
    if not os.path.isfile(self._configpath):
      raise Exception(
        'TemplateFileNotFound',
        "Template file %s not found" % self._configpath)
    self._config = ConfigParser(interpolation=None)
    self._config.read(self._configpath)

  def get(self, entry):
    template_str = self._config.get('template', entry)
    s = string.Template(template_str)
    return s.safe_substitute(Configuration.substitutions)
  
class Configuration:
  substitutions = {}



"""
Main function
"""
def main(args):
  """
  Main entry function for the program
  """
  try:
    version_file_name = os.path.join(scriptpath(), "version.txt")

    tts_version = get_tts_tool_version(version_file_name)
    
    if "--version" in args:
      print(f"TTS backup utility version: {tts_version}\n")
      sys.exit(0)

    cleanup_only = args == ["--cleanup"]
    if args and not cleanup_only:
      print_stderr("Unsupported command line option. Use --version or --cleanup.")
      sys.exit(1)

    # Check if python version is >= 3
    check_python_version((3,6))

    # Get tts-backup tool version
    print(f"Using TTS backup utility version: {tts_version}\n")
    
    # Template for sql scripts
    template = Template(os.path.join(scriptpath(), 'ttsTemplate.txt'))

    # Configure or Load the environment
    _env = Environment(os.path.join(scriptpath(), 'tts-backup-env.txt'), cleanup_only=cleanup_only)

    if cleanup_only:
      TTS_SRC_CLEANUP_MANAGER(_env).tts_src_cleanup(template)
      return 0
 
    ### STEP 1: RUN tablespace validations ###
    print("\n* Run tablespace validations...\n")
    start_time = log_start_time()
    run_validations = TTS_SRC_RUN_VALIDATIONS(_env)
    _env.TABLESPACES = run_validations._get_tablespaces(template)
    print(f"\n TABLESPACES LIST : {_env.TABLESPACES}")
    _env.SCHEMAS = run_validations._get_schemas(template)
    print(f"\n SCHEMAS LIST : {_env.SCHEMAS}")
    print(f"\n COMMON USER REMAP LIST : {_env.COMMON_USER_REMAP}")
    _env.ols_policies_list = run_validations._validate_ols_policies(template)
    if _env.DB_VERSION != '11g':
      _env.redaction_policies_list = run_validations._validate_redaction_policies(template)
    else:
      _env.redaction_policies_list = ''
    if _env.DB_VERSION != '11g':
      run_validations._validate_dvrealm(template)
    run_validations._validate_schemas(template)
    run_validations._validate_tablespaces(template)
    _env.xml_export_tables = run_validations._get_xml_export_tables(template)
    log_end_time(start_time)

    if _env.STORAGE_TYPE == 'OBJECT_STORAGE':
      ### STEP 2: Check storage buckets ###
      print("\n* Check backup and bundle storage buckets...\n")
      start_time = log_start_time()
      storage_bucket_check = TTS_SRC_CHECK_STORAGE_BUCKETS(_env)
      log_end_time(start_time)

      ### STEP 3: Create wallet to store backup credentials ###
      print("\n* Add credential alias to backup wallet...\n")
      start_time = log_start_time()
      create_wallet = TTS_SRC_CREATE_WALLET(_env)
      _env.TTS_WALLET_CRED_ALIAS = create_wallet.tts_src_create_backup_wallet()
      if _env.TTS_WALLET_CRED_ALIAS is None:
        print("Failed to create wallet.\n")
        exit(1)
      log_end_time(start_time)

    ### STEP 4: Gather data ###
    print("\n* Gather database, pdb and tablespace properties...\n")
    start_time = log_start_time()
    gather_data = TTS_SRC_GATHER_DATA(_env)
    _env.DB_PROPS_ARRAY = gather_data.tts_src_gather_data(template)
    if _env.DB_PROPS_ARRAY is None:
      print("Failed to gather data.\n")
      exit(1)
    log_end_time(start_time)
    
    _env.platform_id = int(_env.DB_PROPS_ARRAY[3])
    _env.version_full = _env.DB_PROPS_ARRAY[9]
    _env.bigfile_tablespaces = _env.DB_PROPS_ARRAY[15].replace(';', ',')
    _env.smallfile_tablespaces = _env.DB_PROPS_ARRAY[16].replace(';', ',')
    _env.encrypted_tablespaces = _env.DB_PROPS_ARRAY[17].replace(';', ',')
    _env.unencrypted_tablespaces = _env.DB_PROPS_ARRAY[18].replace(';', ',')
    _env.role_list = _env.DB_PROPS_ARRAY[21].replace(';', ',')
    _env.mview_schemas = _env.DB_PROPS_ARRAY[22].replace(';', ',')
    _env.sched_cred_list = _env.DB_PROPS_ARRAY[23].replace(';', ',')

    if _env.DB_VERSION.strip().lower() == '11g' and _env.encrypted_tablespaces.strip():
      print(
        f"ERROR: Encrypted tablespaces are not supported for 11g databases: "
        f"{_env.encrypted_tablespaces}."
      )
      exit(1)

    _env.TBS_READ_ONLY = _env.DB_PROPS_ARRAY[14]
    _env.TBS_READ_ONLY = _env.TBS_READ_ONLY.rstrip() # Remove trailing whitespace

    ### STEP 5a: Create directory object ###
    print("\n* Create directory object...\n")
    start_time = log_start_time()
    directory_manager = TTS_SRC_DIRECTORY_MANAGER(_env, template)
    log_end_time(start_time)

    is_dry_run = _env.DRY_RUN.strip().upper() == 'TRUE'
    is_final_backup = _env.FINAL_BACKUP.strip().upper() == 'TRUE'

    # A real final backup must not run on physical standby.
    if not is_dry_run and is_final_backup:
      if not directory_manager.tts_src_can_run_expdp(template, 'Final TTS backup'):
        print('ERROR: FINAL_BACKUP=TRUE cannot run on a physical standby. '
            'Convert the standby to a SNAPSHOT STANDBY before triggering '
            'the final backup.')
        exit(1)

    ### Step 5a-1: Estimate xml dump size if xml tables exist and
    ###             fail early
    if (_env.STORAGE_TYPE == 'OBJECT_STORAGE' and
        _env.table_with_xml_type.upper() == 'TRUE'):
      if directory_manager.tts_src_can_run_expdp(template, 'XML dump size estimate'):
        print("\n* Estimate local xml dump staging space for object storage.\n")
        start_time = log_start_time()
        xml_estimator = TTS_SRC_RMAN_BACKUP(_env)
        if xml_estimator.tts_src_estimate_xml_dump_space(template) == 1:
          print("Estimate local xml dump staging space Failed.\n")
          if not _env.is_dry_run():
            exit(1)
        log_end_time(start_time)

    if _env.DRY_RUN.strip().upper() != "TRUE":
      ### STEP 5b: Export TDE keys ###
      if _env.encrypted_tablespaces.strip():
        print("\n* Export TDE keys...\n")
        start_time = log_start_time()
        tde_keys_exporter = TTS_SRC_TDE_KEY_EXPORTER(_env, template)
        log_end_time(start_time)

      if _env.STORAGE_TYPE == 'OBJECT_STORAGE':
        ### Step 6: Copy wallet into all the hosts ###
        print("\n* Copy wallet into the host list...\n")
        start_time = log_start_time()
        wallet_copier = TTS_SRC_WALLET_COPIER(_env)
        log_end_time(start_time)

      ### Step 7a: Get SCN for next incremental backup just before the RMAN execution ###
      print("\n* Get SCNS for next incremental backup...\n")
      start_time = log_start_time()
      _env.CHANNEL_STRING = ''
      rman_backup = TTS_SRC_RMAN_BACKUP(_env)
      rman_backup.tts_src_get_scn(template)
      log_end_time(start_time)

      ### Step 7b: Build channel string for RMAN ###
      print("\n* Construct channel string...\n")
      start_time = log_start_time()
      rman_backup.tts_src_get_channel()
      log_end_time(start_time)

      ### Step 7c: Perform RMAN Backup for Tablespace###
      rman_log_pattern = os.path.join(_env.TTS_DIR_PATH, 'rman_*.log')
      os.system(f'rm -rf {rman_log_pattern}')
      print(f"\n* Perform RMAN backup of {_env.TABLESPACES} tablespace datafiles and schema...\n")

      start_time = log_start_time()

      # Read the projectFile to check if Final restore completed
      tts_project_file = _env.TTS_PROJECT_FILE
      with open(tts_project_file, 'r') as f:
        project_data = json.load(f)
        final_backup_complete = project_data.get('final_backup_complete', 'FALSE')
      
      if _env.FINAL_BACKUP.upper() == "TRUE" and \
        final_backup_complete == "TRUE":
        print("Final Backup Completed, Proceeding with DATAPUMP Export\n")
      else:
        if len([ts for ts in _env.encrypted_tablespaces.split(',') if ts.strip()]) > 0:
          print("Backup for encrypted tablespaces started\n")
          if rman_backup.tts_src_backup_tablespaces("encrypted", template) == 1:
            print("Backup for encrypted tablespaces Failed.\n")
            exit(1)
          print("Backup for encrypted tablespaces completed successfully\n")
        
        if len([ts for ts in _env.unencrypted_tablespaces.split(',') if ts.strip()]) > 0:
          print("Backup for unencrypted tablespaces started\n")
          if rman_backup.tts_src_backup_tablespaces("unencrypted", template) == 1:
            print("Backup for unencrypted tablespaces Failed.\n")
            exit(1)
          print("Backup for unencrypted tablespaces completed successfully\n")
        
        if _env.FINAL_BACKUP.upper() == "TRUE":
          project_data['final_backup_complete'] = "TRUE"
          with open(tts_project_file, 'w') as f:
            json.dump(project_data, f, indent=2)
      log_end_time(start_time)
      

      ### STEP 7d: Export Schema ###
      if _env.FINAL_BACKUP.upper() == "TRUE":
        print(f"\n* Export {_env.SCHEMAS.upper()} schema using data pump...\n")
        # rman_backup.tts_src_export_schema()
        start_time = log_start_time()
        if rman_backup.tts_src_export_schema(template) == 1:
          print("Export schema Failed.\n")
          exit(1)
        log_end_time(start_time)

        print(f"\n* Export {_env.TABLESPACES.upper()} tablespaces schema using data pump...\n")
        # rman_backup.tts_src_export_tablespaces()
        start_time = log_start_time()
        if rman_backup.tts_src_export_tablespaces(template) == 1:
          print("Export Tablespace schema Failed.\n")
          exit(1)
        log_end_time(start_time)
        
        if _env.table_with_xml_type.upper() == "TRUE":
          print(
            f"\n* Export {_env.TABLESPACES.upper()} tablespaces XML "
            "tables using data pump...\n"
          )
          start_time = log_start_time()
          if rman_backup.tts_src_export_xml_tables(template) == 1:
            print("Export XML Tables Failed.\n")
            exit(1)
          log_end_time(start_time)

      ### STEP 8: Create manifiest ###
      print("\n* Create manifest...\n")
      start_time = log_start_time()
      rman_backup.tts_src_create_manifest()
      log_end_time(start_time)

      ### STEP 9: Create transport bundle ###
      print("\n* Create transport bundle...\n")
      start_time = log_start_time()
      bundle_manager = TTS_SRC_BUNDLE_MANAGER(_env)
      log_end_time(start_time)

      ### STEP 10: Cleanup ###
      if _env.FINAL_BACKUP.upper() == "TRUE":
        print("\n* Final Backup, Dropped the project manifest json file...\n")
        os.remove(_env.TTS_PROJECT_FILE)
        print("\n* Dropped the TTS_DIR_NAME directory object...\n")
        start_time = log_start_time()
        directory_manager.tts_src_drop_directory(template)
        log_end_time(start_time)

      ### STEP 11: Upload bundle to object store ###
      print("\n* Upload transport bundle to object storage...\n")
      start_time = log_start_time()
      bundle_manager.tts_src_upload_bundle()
      log_end_time(start_time)
    else:
      if _env.DB_VERSION != '11g':
        if directory_manager.tts_src_can_run_expdp(template, 'Dry-run Data Pump validation'):
          rman_backup = TTS_SRC_RMAN_BACKUP(_env)
          print(f"\n* Validation export for tablespaces metadata using datapump..\n")
          start_time = log_start_time()
          if rman_backup.tts_src_export_tablespaces(template, True) == 1:
            print("Export Tablespace metadata Failed.\n")
            _env.add_dry_run_error("Validation export for tablespaces metadata using datapump failed.")
          log_end_time(start_time)
        else:
          print('Data Pump validation is not supported on a physical standby. '
            'Convert the standby to a snapshot standby for data pump validations.')

      print("\n* Dry run cleanup: dropping the TTS directory object...\n")
      start_time = log_start_time()
      try:
        directory_manager.tts_src_drop_directory(template)
      except RuntimeError as err:
        _env.add_dry_run_error(f"Dry-run cleanup failed: {err}")
      log_end_time(start_time)
      sys.exit(_env.report_dry_run_result())

  except FileNotFoundError as err_msg:
    print(f"File Not Found Error: {err_msg}")
    if cleanup_only:
      return 1
  except EnvironmentError as err_msg:
    print(f"Environment Error: {err_msg}")
    if cleanup_only:
      return 1
  except ValueError as err_msg:
    print(f"Value Error: {err_msg}")
    if cleanup_only:
      return 1
  except AttributeError as err_msg:
    print(f"Attribute Error: {err_msg}")
    if cleanup_only:
      return 1
  except RuntimeError as err_msg:
    print(f"Runtime Error: {err_msg}")
    if cleanup_only:
      return 1
  except Exception as err_msg:
    print(f"Error: {err_msg}")
    if cleanup_only:
      return 1

if __name__ == '__main__':
  """
  Run the main function for direct invocation of script
  """
  exit_code = main(sys.argv[1:])
  if exit_code is not None:
    sys.exit(exit_code)
