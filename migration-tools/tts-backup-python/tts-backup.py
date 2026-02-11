#!/usr/bin/python3
#
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
import oci
from urllib.parse import urlparse
import math
import getpass
import functools
from datetime import datetime


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

  def __init__(self, args, env_file: str):
    self.env_file = env_file
    self._env = ConfigParser()
    self._defaults = {}

    # Validate and load environment file
    self._validate_env_file()
    self._load_arg_variables(args)
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
    print_stderr("optional arguments allowed : --IGNORE_NON_FATAL_ERRORS, --JDK8_PATH")
    print_stderr("runtime required inputs    : DBPASSWORD")
    print_stderr("runtime optional inputs    : TDE_WALLET_STORE_PASSWORD, DVREALM_PASSWORD")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("Provide inputs during runtime manually - ")
    print_stderr("        Usage: python3 " + sys.argv[0] + " [OPTIONS]")
    print_stderr("        Example: python3 " + sys.argv[0] + " --IGNORE_NON_FATAL_ERRORS=<True/False> --JDK8_PATH=<path to jdk8> ")
    print_stderr("")
    print_stderr("Or provide inputs via standard input (e.g., for automation):")
    print_stderr("        (TDE and DV applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n<TDE_WALLET_STORE_PASSWORD>\\n<DVREALM_PASSWORD>\" | python3 " + sys.argv[0] + " [OPTIONS]")
    print_stderr("        (TDE applicable, DV not applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n<TDE_WALLET_STORE_PASSWORD>\" | python3 " + sys.argv[0] + " [OPTIONS]")
    print_stderr("        (TDE not applicable, DV applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\\n\\n<DVREALM_PASSWORD>\" | python3 " + sys.argv[0] + " [OPTIONS]")
    print_stderr("        (TDE and DV not applicable):")
    print_stderr("        echo -e \"<DBPASSWORD>\" | python3 " + sys.argv[0] + " [OPTIONS]")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("        ARGUMENTS DESCRIPTION      ")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    print_stderr("--IGNORE_NON_FATAL_ERRORS=<optional, provide if required to ignore schema bound object validation errors...>")
    print_stderr("--JDK8_PATH=<optional, provide to use jdk8_path to download objstore bucket wallet...>")
    print_stderr("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
    sys.exit(1)
     
  def _load_arg_variables(self, args):
    """Load environment variables from the arguments provided and 
       set them as class attributes."""
    arg_dict = {}
    arg_vars = ['IGNORE_NON_FATAL_ERRORS', 'JDK8_PATH']

    # Populate arg_dict from given args
    for arg in args:
      if arg.startswith('--') and '=' in arg:
        key, value = arg[2:].split('=', 1)
        key = key.strip()
        value = value.strip()
        if key not in arg_vars:
          print(f"Invalid argument key: {key}")
          self.usage()
        arg_dict[key] = value
      else:
        print(f"Invalid argument format: {arg}")
        self.usage()

    for key in arg_vars:
      value = arg_dict.get(key)
      setattr(self, key, value)

   
  def _load_env_variables(self):
    """Load environment variables from the config file and set them as class attributes."""
    self._env.read(self.env_file)
    self._defaults = self._env['DEFAULT']
    
    # Define and load required variables
    value_fss = self._defaults.get('TTS_FSS_CONFIG', '').strip()
    value_objs = self._defaults.get('TTS_BACKUP_URL', '').strip()
    if value_fss:
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

    # Set one varable which defines customer choosen storage type disk ot objs
    if value_fss:
      setattr(self, 'STORAGE_TYPE', 'FSS')
    elif value_objs:
      setattr(self, 'STORAGE_TYPE', 'OBJECT_STORAGE')

    if value_objs:
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
    optional_vars = ['SCHEMAS', 'TABLESPACES', 'OCI_INSTALLER_PATH',
                     'OCI_PROXY_HOST', 'OCI_PROXY_PORT', 'CLUSTER_MODE',
                     'DRCC_REGION', 'DRY_RUN', 'EXCLUDE_TABLES', 'EXCLUDE_STATISTICS', 
                     'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES',
                     'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT','DVREALM_USER',
                     'ZDM_BASED_TRANSPORT']
    for var in optional_vars:
      value = self._defaults.get(var, '').strip()
      if value and (var == 'TABLESPACES' or var == 'SCHEMAS'):
        value = value.replace(" ", "")
      setattr(self, var, value)
    
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

    # Set default values
    setattr(self, 'BACKUP_LEVEL', 0)
    setattr(self, 'INCR_SCN', 0)
    setattr(self, 'FINAL_BACKUP', getattr(self, 'FINAL_BACKUP', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES', getattr(self, 'TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES', 'FALSE') or 'FALSE')
    setattr(self, 'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT', getattr(self, 'TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT', 'FALSE') or 'FALSE')
    setattr(self, 'ZDM_BASED_TRANSPORT', getattr(self, 'ZDM_BASED_TRANSPORT', 'FALSE') or 'FALSE')

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
    opt_vars = ['DRCC_REGION', 'DRY_RUN', 'EXCLUDE_STATISTICS']
    for var in opt_vars:
      setattr(self, var, getattr(self, var, 'FALSE') or 'FALSE')
      value = getattr(self, var).strip().upper()
      if value not in ['TRUE', 'FALSE']:
        raise ValueError(f"{var} value should be one of ['TRUE' , 'FALSE' , 'true' , 'false'] but value is {value}.")

    # Other default settings
    setattr(self, 'OCI_INSTALLER_PATH', getattr(self, 'OCI_INSTALLER_PATH', '') or scriptpath())
    setattr(self, 'TTS_WALLET_CRED_ALIAS', '')
    setattr(self, 'TTS_DIR_NAME', 'TTS_DUMP_DIR')
    setattr(self, 'TDE_KEYS_FILE', "tde_keys.exp")
    setattr(self, 'NEXT_SCN', 0)
    setattr(self, 'MAX_CHANNELS', 200)
    setattr(self, 'RMAN_LOGFILES', [])

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

  def _create_manifest_file(self):
    """Create or load the project manifest file."""
    
    # Retrieve project directory path
    project_dir_path = getattr(self, 'PROJECT_DIR_PATH')
    if project_dir_path and not os.path.exists(project_dir_path):
      os.makedirs(project_dir_path)
      print(f"Created project directory: {project_dir_path} \n")


    # No need for manifest json in case of dry run
    if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
      print(f"DRY_RUN : Skipping Create/Load of project manifest file...\n")
      return

    # Load project manifest JSON file and process it if already exists
    tts_project_file = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}.json")
    setattr(self, 'TTS_PROJECT_FILE', tts_project_file)


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
        setattr(self, 'BACKUP_LEVEL', project_data.get('backup_level'))
        setattr(self, 'INCR_SCN', project_data.get('incr_scn'))
        setattr(self, 'level0_tablespaces', project_data.get('tablespaces'))
      print((f"Loaded existing project manifest file: {tts_project_file} \n"))

  def _setup_backup_directories(self):
    """Set up backup directories and bundle files."""
    
    # Create project directory based on backup level
    project_dir_path = getattr(self, 'PROJECT_DIR_PATH')

    if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
      tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN")
    else:
      tts_dir_path = os.path.join(project_dir_path, f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}")

    # Check if the directory exists
    if os.path.exists(tts_dir_path):
      failed_dir = f"{tts_dir_path}_FAILED"
      # Ensure the failed directory name is unique to avoid overwriting old failures
      counter = 1
      while os.path.exists(failed_dir):
        failed_dir = f"{tts_dir_path}_FAILED_{counter}"
        counter += 1
      # Move the directory
      shutil.move(tts_dir_path, failed_dir)
      print(f"Moved existing failed directory '{tts_dir_path}' to '{failed_dir}'")

    # Create bundle file for transport of backup files
    if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
      bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN.tgz"
    else:
      bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}.tgz"
    tts_bundle_file = os.path.join(project_dir_path, bundle_file_name)
    if os.path.isfile(tts_bundle_file):
      now = subprocess.check_output("date +%d-%b-%Y_%H_%M_%S", shell=True).decode().strip()
      if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
        bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_DRY_RUN_{now}.tgz"
      else:
        bundle_file_name = f"{getattr(self, 'PROJECT_NAME')}_LEVEL_{getattr(self, 'BACKUP_LEVEL')}_{now}.tgz"
      tts_bundle_file = os.path.join(os.path.dirname(tts_dir_path), bundle_file_name)
      if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
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

    if getattr(self, 'DRY_RUN').strip().upper() == "TRUE":
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

  def run_sql(self, sql_script, log_file=None, dv_user=False):
    """Build the SQL*Plus command string."""
    if dv_user:
      conn_string = f"{self.dbuser}/{self.dbpassword}@{self.hostname}:{self.port}/{self.service_name}"
    else:
      conn_string = f"{self.dbuser}/{self.dbpassword}@{self.hostname}:{self.port}/{self.service_name} as SYSDBA"
    

    command = f'{self.orahome}/bin/sqlplus -s "{conn_string}" << EOF\n'
    command += "whenever sqlerror exit 1;\n"
    command += "set heading off\nset feedback off\nset pagesize 0\nset serveroutput on\n"

    if log_file:
      command += f"spool {log_file};\n"

    if not sql_script.strip():
      raise ValueError("Empty SQL query provided.")
    command += sql_script
    
    if log_file:
      command += "\nspool off;"
    command += "\nEOF"

    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    stdout, stderr = process.communicate()

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
    self._sqlplus = SqlPlus(
        dbuser=self._env.DBUSER,
        dbpassword=self._env.DBPASSWORD,
        hostname=self._env.HOSTNAME,
        port=self._env.LSNR_PORT,
        service_name=self._env.DB_SVC_NAME,
        orahome=self._env.ORAHOME
    )
    self.log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_validate.log")

  def _get_tablespaces(self, template):
    """Return all tablespaces if not given"""
    if self._env.TABLESPACES:
      return self._env.TABLESPACES

    print(f"Tablespaces not provided. Fetching all tablespaces...")
    try:
      _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_get_tablespaces.log")
      if not self._sqlplus.run_sql(template.get('get_tablespaces'), _log_file):
        raise ValueError(f"Failed to fetch user tablespaces.")

      # Read the log file to get the SQL*Plus output
      with open(_log_file, "r") as file:
        lines = file.readlines()
        tbs = [line.strip().upper() for line in lines if line.strip()]
      
      self._env.TABLESPACES = ",".join(tbs)
      return self._env.TABLESPACES

    except Exception as e:
      print(f"Error while fetching tablespaces : {e}")
      raise

  def _get_schemas(self, template, user_type=None):
    """Return Local/Common users"""
    if user_type == "local":
      if self._env.DB_VERSION == '11g':
        sql_script = template.get('get_local_schemas_dbversion_11g')
      else: 
        sql_script = template.get('get_local_schemas')
    elif user_type == "common":
      if self._env.DB_VERSION == '11g':
        sql_script = template.get('get_common_schemas_dbversion_11g')
      else: 
        sql_script = template.get('get_common_schemas')
    elif user_type == "required":
      ts_list = split_into_lines(self._env.TABLESPACES)
      Configuration.substitutions = {
        'ts_list': ts_list.upper(),
      }
      sql_script = template.get('owners_in_tablespaces')
    else:
      if not self._env.SCHEMAS:
        print("No schemas provided. Returning a list of required users.")
        self._env.SCHEMAS = self._get_schemas(template, "required")
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
      
      return ",".join(users)
    except Exception as e:
      print(f"Error while fetching {user_type} users: {e}")
      raise

  def _validate_schemas(self, template):
    """Validate schemas"""
    print("Validating schemas...")
    # Validate schemas for common users
    common_users = self._get_schemas(template, "common")
    required_schemas = self._get_schemas(template, "required")
    
    sc_list = split_into_lines(self._env.SCHEMAS)

    exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)

    exc_tbl_filter = f"and table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""

    _log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_schema_validations.log")
    for schema in self._env.SCHEMAS.split(','):
      Configuration.substitutions = {
        'schema': schema.upper(),
        'exc_tbl_filter': exc_tbl_filter,
        'dry_run': self._env.DRY_RUN.strip().upper(),
      }
      if schema.upper() in common_users.split(','):
        err_msg = f"Schema validation failed: {schema} is a common user. Common users are not allowed to transport."
        if self._env.DRY_RUN.strip().upper() == "TRUE":
          print(err_msg)
        else:
          raise ValueError(err_msg)
      if not self._sqlplus.run_sql(template.get('validate_schemas'), _log_file):
        print(f"Schema {schema.upper()} validations failed. \n")
        self._print_log_and_exit(_log_file)

    if os.path.isfile(_log_file) and os.path.getsize(_log_file) > 0:
      self._print_log_and_exit(_log_file, 0)

    for schema in required_schemas.split(','):
      if schema.upper() in common_users.split(','):
        err_msg = f"Schema validation failed: {schema} is a required schema to transport and is a common user. Common users are not allowed to transport. Please update TABLESPACES list in the env."
        if self._env.DRY_RUN.strip().upper() == "TRUE":
          print(err_msg)
        else:
          raise ValueError(err_msg)
      if schema.upper() not in sc_list:
        err_msg = f"Schema validation failed: {schema} is a required schema to transport."
        if self._env.DRY_RUN.strip().upper() == "TRUE":
          print(err_msg)
        else:
          raise ValueError(err_msg)
  
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

    print("Finding plsql objects that are not transported due to owner not in transport list")
    self._run_object_validation(template, ts_list, sc_list)

    Configuration.substitutions = {
      'ts_list': ts_list.upper(),
      'final_backup': self._env.FINAL_BACKUP.upper(),
    }

    if not self._sqlplus.run_sql(template.get('purge_dba_recyclebin')):
      print(f"Validation failed: Found BIN$ objects in one or more tablespaces from tbs list..\n")
      print(f"'Please purge dba_recyclebin to avoid move failures at ADBS'")
    
    for tablespace in ts_array:
      tablespace = tablespace.strip().upper()
      print(f"Validate if tablespace {tablespace} is ready for transport...")
      self._run_tablespace_validation_script(template, tablespace, sc_list, exc_tbl_list)
      if os.path.isfile(self.log_file) and os.path.getsize(self.log_file) > 0:
        print(f"Tablespace validations failed.")
        self._print_log_and_exit(self.log_file, 0)

    if self._env.DB_VERSION == '11g':
      ts_list = "'{}'".format(",".join(self._env.TABLESPACES.split(',')))
      Configuration.substitutions = {
        'ts_list': ts_list
      }
      if not self._sqlplus.run_sql(template.get('validate_tablespaces_dbversion_11g'), f"{self.log_file} append"):
        print(f"Tablespace validations failed. Please review {self.log_file} for details\n")
        self._print_log_and_exit(self.log_file)
      if os.path.isfile(self.log_file) and os.path.getsize(self.log_file) > 0:
        print(f"Tablespace validations failed.")
        self._print_log_and_exit(self.log_file, 0)

  def _run_object_validation(self, template, ts_list, sc_list):
    """Run SQL object validation for all tablespaces."""
    if self._env.DB_VERSION == '11g':
      l_user_list_clause = "and username not in ('SYS','SYSTEM')"
    else:
      l_user_list_clause = "and username not in ('SYS','SYSTEM') and common='NO'"

    Configuration.substitutions = {
        'sc_list': sc_list.upper(),
        'ts_list': ts_list.upper(),
        'l_user_list_clause': l_user_list_clause,
      }
      
    if self._env.DRY_RUN.strip().upper() == "TRUE":
      _log_file = os.path.join(self._env.PROJECT_DIR_PATH, f"{self._env.PROJECT_NAME}_LEVEL_{self._env.BACKUP_LEVEL}_dry_run_object_validations.log")
    else:
      _log_file = os.path.join(self._env.PROJECT_DIR_PATH, f"{self._env.PROJECT_NAME}_LEVEL_{self._env.BACKUP_LEVEL}_object_validations.log")
    
    if not self._sqlplus.run_sql(template.get('object_validation'), _log_file):
      print(f"\n Object validations failed. Please review:")
      print(f"{_log_file}\n")
      raise RuntimeError(f"Failed to run object validations on tablespaces.")

    print(f"Object validations complete.\n")

    if os.path.isfile(_log_file) and os.path.getsize(_log_file) > 0:
      print(f" Please review: {_log_file}\n")
      print("This file contains a list of database objects that will NOT be transported.\n")
      if self._env.IGNORE_NON_FATAL_ERRORS and self._env.IGNORE_NON_FATAL_ERRORS.upper() == 'TRUE':
        print("Errors Ignored proceeding...\n")
      else:
        print("Please run with option --IGNORE_NON_FATAL_ERRORS=TRUE to ignore non fatal errors...\n")
        print("IGNORE_NON_FATAL_ERRORS option not provided, exiting...")
        print(f" Review: {_log_file}\n")
        if self._env.DRY_RUN.strip().upper() == "FALSE":
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

  def _run_tablespace_validation_script(self, template, tablespace, sc_list, exc_tbl_list):
    """Run SQL validation for a single tablespace."""
    exc_tbl_filter = f"and t.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_seg = f"and c.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
    exc_tbl_filter_dt = f"and atc.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""

    Configuration.substitutions = {
        'tablespace': tablespace.upper(),
        'final_backup': self._env.FINAL_BACKUP.upper(),
        'sc_list': sc_list.upper(),
        'exc_tbl_filter': exc_tbl_filter,
        'exc_tbl_filter_seg': exc_tbl_filter_seg,
        'exc_tbl_filter_dt': exc_tbl_filter_dt,
        'dry_run': self._env.DRY_RUN.strip().upper(),
      }
    
    if not self._sqlplus.run_sql(template.get('validate_tablespaces'), self.log_file):
      print(f"Tablespace {tablespace} validations failed. \n")
      self._print_log_and_exit(self.log_file, 0 if self._env.DRY_RUN.strip().upper() == "TRUE" else 1)
    
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
      print(f"Tablespaces count validation failed. \n")
      print(f"ERROR : Total number of specified tablespaces are : {ts_count}. Max allowed tablespace count of 30 will be exceeded in ADWCS.")
      if self._env.DRY_RUN.strip().upper() == "FALSE":
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
      self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      redaction_pls = log.read().strip()
    
    if redaction_pls and self._env.TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES.upper() == "FALSE":
      print("Redaction Policies found in the database. You have to create the redaction policies in ADB-S database. Redacted data will be unprotected in ADB-S database otherwise. \n")
      print(f"[ERROR] Please provide consent to transport tables protected by redaction policies by specifying TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES=TRUE. Redaction policies found are : {redaction_pls}")
      if self._env.DRY_RUN.strip().upper() == "FALSE":
        exit(1)
    return redaction_pls

  def _validate_ols_policies(self, template):
    """OLS Policies validation"""
    print("Validating OLS policies...")
    sc_list = split_into_lines(self._env.SCHEMAS)

    Configuration.substitutions = {
        'sc_list': sc_list.upper(),
      }
    
    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_ols.log")
    if not self._sqlplus.run_sql(template.get('validate_ols_policies'), log_file):
      print("OLS Policies validation failed. \n")
      self._print_log_and_exit(log_file)
    
    with open(log_file, 'r') as log:
      ols_pls = log.read().strip()
    
    if ols_pls and self._env.TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES.upper() == "FALSE":
      print("OLS Policies found in the database. You have to create the OLS policies in ADB-S database. Data protected by OLS will be unprotected in ADB-S otherwise.\n")
      print(f"[ERROR] Please provide consent to transport tables protected by OLS policies by specifying TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES=TRUE. OLS policies found are : {ols_pls}")
      if self._env.DRY_RUN.strip().upper() == "FALSE":
        exit(1)

    return ols_pls
  
  def _validate_dvrealm(self, template):
    """DVREALM validation"""
    print("Checking Database Vault protection...")

    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_dvops.log")
    if not self._sqlplus.run_sql(template.get('validate_dvops_protection'), log_file):
      print("Database Vault protection check failed. \n")
      self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      dvops_cnt = log.read().strip()

    if int(dvops_cnt) > 0 and self._env.TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT.upper() == "FALSE":
      print("Database Vault protection is enabled in the database. You have to re-enable database vault protection on the ADB-S database. Transported data will be unprotected otherwise \n")
      print("[ERROR] Please provide consent to transport Database Vault protected database by specifying TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT=TRUE.")
      if self._env.DRY_RUN.strip().upper() == "FALSE":
        exit(1)

    print("Checking Database Vault realms...")
    log_file = os.path.join(self._env.TTS_DIR_PATH, f"{self._env.PROJECT_NAME}_dvrealm.log")
    if not self._sqlplus.run_sql(template.get('validate_dvrealm_policies'), log_file):
      print("Unable to check Database Vault realms. \n")
      self._print_log_and_exit(log_file)

    with open(log_file, 'r') as log:
      dvrealm_output = log.read().strip()
    dvrealm_array = dvrealm_output.split(',')

    is_dv_enabled = all(int(x) > 0 for x in dvrealm_array[:3])
    if is_dv_enabled: 
      if not self._env.DVREALM_USER.strip() or not self._env.DVREALM_PASSWORD.strip():
        print("[ERROR] Database Vault is enabled in the database. Please provide inputs for DVREALM_USER and DVREALM_PASSWORD.")
        if self._env.DRY_RUN.strip().upper() == "FALSE":
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
        self._print_log_and_exit(log_file)
      
      with open(log_file, 'r') as log:
        dvschemas_output = log.read().strip()

      print(dvschemas_output)
      if int(dvschemas_output) == 0:
        print("[ERROR]Please authorize sys as an Data Pump user to transport the Database Vault protected schemas and retry the export\n")
        if self._env.DRY_RUN.strip().upper() == "FALSE":
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
    self.tts_src_check_storage_buckets()

  def _validate_bucket(self, url):
    """
    Helper function to check if a storage bucket exists.
    """
    # Parse the URL
    parsed_url = urlparse(url)
    # Extract the region from the netloc (example: objectstorage.us-ashburn-1.oraclecloud)
    region = parsed_url.netloc.split('.')[1]
    # Extract the namespace from the path (after "/n/")
    namespace = parsed_url.path.split('/')[2]
    # Extract the bucket name from the path (after "/b/")
    bucket_name = parsed_url.path.split('/')[4]
    
    config = oci.config.from_file(self._env.CONFIG_FILE, "DEFAULT")
    config['region'] = region
    try:
      print(f"Validating storage bucket at URL: {url}...")
      
      object_storage_client = oci.object_storage.ObjectStorageClient(config=config,
                                service_endpoint=url.split('/n')[0])
      if self._env.OCI_PROXY_HOST and self._env.OCI_PROXY_PORT:
        proxy_url = f"{self._env.OCI_PROXY_HOST}:{self._env.OCI_PROXY_PORT}"
        object_storage_client.base_client.session.proxies = {'https': proxy_url}

      response =  object_storage_client.get_bucket(namespace_name=namespace, bucket_name=bucket_name)
      if response.status != 200:
        raise ValueError(f"Failed to validate URI {url}. HTTP Status Code: {response.status} \n")
      print(f"Successfully validated URI {url}.")
    except Exception as e:
      print(f"Error occurred while checking the bucket {url}: {str(e)}\n")
      print("Check if the storage bucket exists and credentials are correct. \n")
      sys.exit(1) 

  def tts_src_check_storage_buckets(self):
    """Function to check both backup and bundle storage buckets."""
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
      # If the first attempt fails, run with user provided jdk8 path and try again
      if self._env.JDK8_PATH:
        print("Running with provided JDK8_PATH...")
        jdk8_path = self._env.JDK8_PATH
      else:
        print("\n Please run with option --JDK8_PATH=/path-to-jdk8 to retry with jdk8...\n")
        print("JDK8_PATH option not provided, exiting...")
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
        '-libDir', self._env.PROJECT_DIR_PATH,
        '-configFile', os.path.join(self._env.ORAHOME, 'dbs', f'opc{os.environ["ORACLE_SID"]}.ora'),
        '-import-all-trustcerts'
    ]
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
      exc_tbl_list = split_into_lines(self._env.EXCLUDE_TABLES, False)
      exc_tbl_filter = f"and t.table_name not in ({exc_tbl_list})" if exc_tbl_list.strip() else ""
      
      Configuration.substitutions = {
        'l_pdb_table': l_pdb_table,
        'l_pdb_type': l_pdb_type,
        'l_version_type': l_version_type,
        'ts_list': ts_list.upper(),
        'sc_list': sc_list.upper(),
        'database_name': self._env.DATABASE_NAME,
        'exc_tbl_filter': exc_tbl_filter,
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
  Class to create or drop a directory object in the database.
  """
  def __init__(self, env, template):
    self._env = env
    self.tts_src_create_directory(template)

  def tts_src_create_directory(self, template):
    """Function to create directory object in the database"""
    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)

    Configuration.substitutions = {
        'tts_dir_name': self._env.TTS_DIR_NAME,
        'tts_dir_path': self._env.TTS_DIR_PATH,
        'db_user': self._env.DBUSER,
      }
    
    log_file = os.path.join(self._env.TTS_DIR_PATH, 'create_dir.log')
    if not sqlplus.run_sql(template.get('tts_src_create_directory'), log_file):
      print(f"Failed to create directory {self._env.TTS_DIR_NAME} \n")
      self._log_error(log_file)
      raise RuntimeError(f"Directory creation failed: {self._env.TTS_DIR_NAME}\n")
      
    print(f"Directory {self._env.TTS_DIR_NAME} created successfully.")
  
  def tts_src_drop_directory(self, template):
    """Function to drop directory object in the database"""
    sqlplus = SqlPlus(self._env.DBUSER, self._env.DBPASSWORD,
                      self._env.HOSTNAME, self._env.LSNR_PORT,
                      self._env.DB_SVC_NAME, self._env.ORAHOME)

    Configuration.substitutions = {
        'tts_dir_name': self._env.TTS_DIR_NAME,
      }
    if not sqlplus.run_sql(template.get('tts_src_drop_directory')):
      print(f"Failed to drop directory {self._env.TTS_DIR_NAME} \n")
      raise RuntimeError(f"Directory drop failed: {self._env.TTS_DIR_NAME}\n")
    print(f"Directory {self._env.TTS_DIR_NAME} dropped successfully.")
  
  def _log_error(self, log_file):
    """Helper function to log the error details from the log file."""
    if os.path.exists(log_file):
      with open(log_file, 'r') as log:
        error_details = log.read()
        print(f"Error details:\n{error_details} \n")
    else:
      print(f"Log file {log_file} does not exist. \n")


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
      if not sqlplus.run_sql(template.get('tts_src_export_tde_keys')) or not os.path.exists(tde_keys_path):
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
    self.hosts = self.parse_hosts(self._env.DB_PROPS_ARRAY[13])
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

  def _execute_command(self, command, command_type):
    """Executes the given shell command and handles errors."""
    try:
      process = subprocess.Popen(command, shell=True, stdout=sys.stdout, stderr=sys.stderr, universal_newlines=True)
      stdout, stderr = process.communicate()
      
      if process.returncode == 0 or process.returncode == 5:
        print(f"{command_type} executed successfully.")
        return 0
      else:
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
    self.host_array = self._env.DB_PROPS_ARRAY[13].split(';')
    self._env.CPU_COUNT = self.calculate_cpu_count()

    if not self.host_array or self._env.CPU_COUNT <= 0:
      print("No instances or CPUs to construct channel string. Exiting...")
      return False

    rman_parms = ""
    if self._env.STORAGE_TYPE == "FSS":
      rman_parms = f"""
      parms='SBT_LIBRARY=oracle.disksbt,
      ENV=(BACKUP_DIR={self._env.TTS_FSS_MOUNT_DIR}/{self._env.PROJECT_NAME}/datafile)';
      """
    else:
      rman_parms = f"""
      parms='SBT_LIBRARY={self._env.PROJECT_DIR_PATH}/libopc.so, 
      ENV=(OPC_WALLET="LOCATION=file:{self._env.TTS_DIR_PATH} CREDENTIAL_ALIAS={self._env.TTS_WALLET_CRED_ALIAS}",
      OPC_HOST={self._env.TTS_BACKUP_URL.split('/b/')[0]}, 
      OPC_CONTAINER={self._env.TTS_BACKUP_URL.split('/b/')[1]}, 
      OPC_AUTH_SCHEME=BMC,
      OPC_CHUNK_SIZE=524288000, 
      _OPC_BUFFER_WRITE=TRUE, 
      _OPC_BUFFER_READ=TRUE, 
      _OPC_TAG_METERING=FALSE)';
      """

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
       
        if self._env.DB_VERSION == '11g':
          l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}"
        else:
          l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME} as sysdba"

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

  def check_log_for_errors(self, log_file):
    """Checks the RMAN/EXPDP log file for errors and raises an exception if any are found."""
    try:
      with open(log_file, 'r') as log:
        log_contents = log.read()

        for line in log_contents.splitlines():
          if "RMAN-" in line and "WARNING" not in line:
            print(f"RMAN errors found. {line}")
            print(f"Please check logs at {log_file}.")
            return False
          if "EXPORT" in line and "stopped due to fatal error" in line:
            print(f"EXPDP errors found. {line}")
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
        incremental_clause = f"incremental from scn {self._env.INCR_SCN}"

    backup_string += (
      f"backup as {compressed} backupset {backup_set_transport}"
      f"{allow_inconsistent} {incremental_clause} "
      f"{section_size_clause}"
      f"tablespace {tablespace_clause.upper()} "
      f"format '{self._env.PROJECT_NAME}_%d_%U' "
      f"{tablespace_dump_clause};"
    )
    
    if self._env.DB_VERSION == '11g':
      l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME}"
    else:
      l_conn_str = f"{host_name}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME} as sysdba"

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
    
    return_val = self._execute_command(template.get('tts_src_backup_tablespaces'), "RMAN")

    # Check the log file for errors after execution
    log_file = f"{self._env.TTS_DIR_PATH}/backup_{backup_type}.log"

    if not self.check_log_for_errors(log_file):
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
    expdp_command = ' '.join(line.strip() for line in template.get("tts_src_export_schema").splitlines() if line.strip())
    return_val = self._execute_command(expdp_command, "EXPDP")
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

  
  def tts_src_export_tablespaces(self, template, _validate=False):
    """Export tablespaces"""
    if _validate:
      tablespace_dump_path = os.path.join(self._env.TTS_DIR_PATH, 'validate_tablespace.dmp')
    else:
      tablespace_dump_path = os.path.join(self._env.TTS_DIR_PATH, 'tablespace.dmp')
    if os.path.exists(tablespace_dump_path):
        os.remove(tablespace_dump_path)  

    l_conn_str = f"{self._env.HOSTNAME}:{self._env.LSNR_PORT}/{self._env.DB_SVC_NAME} AS SYSDBA"
      
    exclude_table_list = [tbl.strip() for tbl in self._env.EXCLUDE_TABLES.split(',') if tbl.strip()]
    quoted_tables = ",".join(f"\\\'{tbl}\\\'" for tbl in exclude_table_list)
    
    xml_table_exclude_clause = ""
    if quoted_tables:
      xml_table_exclude_clause = f'TABLE:\\\"IN \({quoted_tables}\)\\\"'
    
    exclude_clause = ""
    if self._env.EXCLUDE_STATISTICS.strip().upper() == "TRUE":
      if xml_table_exclude_clause:
        exclude_clause = f'EXCLUDE=STATISTICS,INDEX_STATISTICS,TABLE_STATISTICS,{xml_table_exclude_clause}'
      else:
        exclude_clause = 'EXCLUDE=STATISTICS,INDEX_STATISTICS,TABLE_STATISTICS'
    elif xml_table_exclude_clause:
      exclude_clause = f'EXCLUDE={xml_table_exclude_clause}'
    
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

    expdp_command = ' '.join(line.strip() for line in template.get("tts_src_export_tablespaces").splitlines() if line.strip())    
    return_val = self._execute_command(expdp_command, "EXPDP")
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

    new_backup_level = self._env.BACKUP_LEVEL + 1
    
    if self._env.TBS_READ_ONLY == "true":
      next_scn = self.SCNS_ARRAY[1]
    else:
      next_scn = self.SCNS_ARRAY[0]
    
    manifest_data = {
      "epic_name": self._env.PROJECT_NAME,
      "pdbname": self._env.DATABASE_NAME,
      "pdb_guid": self._env.DB_PROPS_ARRAY[0],
      "schemas": [sc.upper() for sc in schema_list],
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
      "table_with_xml_type": self._env.DB_PROPS_ARRAY[10],
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



class TTS_SRC_BUNDLE_MANAGER:
  """
  A class to manage creating and uploading bundles for transport.
  """
  def __init__(self, env):
    self._env = env
    self.tts_src_create_bundle()
  
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
      os.system(f"rm -rf {bundle_dir}")
      print(f"Cleaned up the bundle directory: {bundle_dir}.")
    except Exception as e:
      print(f"Failed to clean up the bundle directory: {e} \n")
    
    # Change back to the original working directory
    os.chdir(current_dir)

    # Cleanup libopc.so downloaded by OCI Installer
    if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
      os.remove(os.path.join(self._env.PROJECT_DIR_PATH, 'libopc.so'))

      # Remove remote directory created on other rac instances
      self.hosts = [host.strip() for host in self._env.DB_PROPS_ARRAY[13].split(';') if host.strip()]
      current_host = socket.gethostname()

      for host in self.hosts:
        host_name = host.split(':')[0]
        if current_host == host_name:
          continue
        if self._env.CLUSTER_MODE.upper() == 'TRUE':
          rm_tts_dir = f"ssh -oStrictHostKeyChecking=no {host_name} 'rm -rf {self._env.PROJECT_DIR_PATH}'"
          print(f"Removing remote directory on {host_name}...")
          subprocess.run(rm_tts_dir, shell=True, check=True)
  
  def tts_src_upload_bundle(self):
    """Upload the created bundle to object storage or fss."""
    try:
      if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
        url = f"{self._env.TTS_BUNDLE_URL}/o/{self._env.BUNDLE_FILE_NAME}"
        # Parse the URL
        parsed_url = urlparse(url)
        # Extract the region from the netloc (example: objectstorage.us-ashburn-1.oraclecloud)
        region = parsed_url.netloc.split('.')[1]
        # Extract the namespace from the path (after "/n/")
        namespace = parsed_url.path.split('/')[2]
        # Extract the bucket name from the path (after "/b/")
        bucket_name = parsed_url.path.split('/')[4]

        config = oci.config.from_file(self._env.CONFIG_FILE, "DEFAULT")
        config['region'] = region
        
        object_storage_client = oci.object_storage.ObjectStorageClient(config=config,
                                  service_endpoint=url.split('/n')[0])
        if self._env.OCI_PROXY_HOST and self._env.OCI_PROXY_PORT:
          proxy_url = f"{self._env.OCI_PROXY_HOST}:{self._env.OCI_PROXY_PORT}"
          object_storage_client.base_client.session.proxies = {'https': proxy_url}
          
        with open(self._env.TTS_BUNDLE_FILE, 'rb') as file:
          response = object_storage_client.put_object(
              namespace_name=namespace, 
              bucket_name=bucket_name, 
              object_name=self._env.BUNDLE_FILE_NAME, 
              put_object_body=file
          )  

        # Check HTTP response code
        if response.status != 200:
          raise ValueError(f"Uploading transport bundle to object storage failed with HTTP status: {response.status}...")
        print(f"Bundle uploaded successfully to {url}.")
        self.display_success_message(url)
      elif self._env.STORAGE_TYPE == "FSS":
        url = f"{self._env.TTS_FSS_MOUNT_DIR}/{self._env.PROJECT_NAME}/metadata/"
        os.system(f"cp {self._env.TTS_BUNDLE_FILE} {url}")
        print(f"Bundle copied successfully to {url}.")
        self.display_success_message(url)
    except Exception as e:
      print(f"Error occurred during the upload_bundle: {e} \n")
      sys.exit(1) 
  
  def display_success_message(self, url):
      """Display a message upon successful upload."""
      print("---------")
      min_storage_size = float(self._env.DB_PROPS_ARRAY[12]) + max(float(self._env.DB_PROPS_ARRAY[19]),
                                                                   float(self._env.DB_PROPS_ARRAY[20]))
      print(f"Create a database in ADB-S cloud with minimum storage size of {min_storage_size}GB")
      print("Specify tag name/value as")
      if self._env.STORAGE_TYPE == "OBJECT_STORAGE":
        print(f"ADB$TTS_BUNDLE_URL: {url}")
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

    # Check if python version is >= 3
    check_python_version((3,6))

    # Get tts-backup tool version
    print(f"Using TTS backup utility version: {tts_version}\n")
    
    # Template for sql scripts
    template = Template(os.path.join(scriptpath(), 'ttsTemplate.txt'))

    # Configure or Load the environment
    _env = Environment(args, os.path.join(scriptpath(), 'tts-backup-env.txt'))
 
    ### STEP 1: RUN tablespace validations ###
    print("\n* Run tablespace validations...\n")
    start_time = log_start_time()
    run_validations = TTS_SRC_RUN_VALIDATIONS(_env)
    _env.TABLESPACES = run_validations._get_tablespaces(template)
    _env.SCHEMAS = run_validations._get_schemas(template)
    _env.ols_policies_list = run_validations._validate_ols_policies(template)
    if _env.DB_VERSION != '11g':
      _env.redaction_policies_list = run_validations._validate_redaction_policies(template)
    else:
      _env.redaction_policies_list = ''
    if _env.DB_VERSION != '11g':
      run_validations._validate_dvrealm(template)
    run_validations._validate_schemas(template)
    run_validations._validate_tablespaces(template)
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
    
    _env.platform_id = int(_env.DB_PROPS_ARRAY[4])
    _env.version_full = _env.DB_PROPS_ARRAY[9]
    _env.bigfile_tablespaces = _env.DB_PROPS_ARRAY[15].replace(';', ',')
    _env.smallfile_tablespaces = _env.DB_PROPS_ARRAY[16].replace(';', ',')
    _env.encrypted_tablespaces = _env.DB_PROPS_ARRAY[17].replace(';', ',')
    _env.unencrypted_tablespaces = _env.DB_PROPS_ARRAY[18].replace(';', ',')
    _env.role_list = _env.DB_PROPS_ARRAY[21].replace(';', ',')
    _env.mview_schemas = _env.DB_PROPS_ARRAY[22].replace(';', ',')
    _env.sched_cred_list = _env.DB_PROPS_ARRAY[23].replace(';', ',')

    _env.TBS_READ_ONLY = _env.DB_PROPS_ARRAY[14]
    _env.TBS_READ_ONLY = _env.TBS_READ_ONLY.rstrip() # Remove trailing whitespace

    ### STEP 5a: Create directory object ###
    print("\n* Create directory object...\n")
    start_time = log_start_time()
    directory_manager = TTS_SRC_DIRECTORY_MANAGER(_env, template)
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

      if _env.STORAGE_TYPE == "FSS":
        print(f"ADB$TTS_BUNDLE_URL : {_env.TTS_FSS_CONFIG}/{_env.BUNDLE_FILE_NAME}")
        print("---------")  
    else:
      if _env.DB_VERSION != '11g':
        rman_backup = TTS_SRC_RMAN_BACKUP(_env)
        print(f"\n* Validation export for tablespaces metadata using datapump..\n")
        start_time = log_start_time()
        if rman_backup.tts_src_export_tablespaces(template, True) == 1:
          print("Export Tablespace metadata Failed.\n")
        log_end_time(start_time)
      print("TTS BACKUP TOOL : Dry Run Completed Successfully...")

  except FileNotFoundError as err_msg:
    print(f"File Not Found Error: {err_msg}")
  except EnvironmentError as err_msg:
    print(f"Environment Error: {err_msg}")
  except ValueError as err_msg:
    print(f"Value Error: {err_msg}")
  except AttributeError as err_msg:
    print(f"Attribute Error: {err_msg}")
  except RuntimeError as err_msg:
    print(f"Runtime Error: {err_msg}")
  except Exception as err_msg:
    print(f"Error: {err_msg}")

if __name__ == '__main__':
  """
  Run the main function for direct invocation of script
  """
  main(sys.argv[1:])
