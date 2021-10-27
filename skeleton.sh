#!/usr/bin/env bash

set -eEuo pipefail

####################################################################################################
# HELPER FUNCTIONS
####################################################################################################

function print_usage () {
  echo ""
  echo "DESCRIPTION"
  echo "  blah blah blah"
  echo "USAGE"
  echo "  kubectl rook-ceph <main args> <command> <command args>"
  echo "MAIN ARGS"
  echo "  -v, --verbose               : output verbose info"
  echo "  -h, --help                  : output help text"
  echo "  -n, --namespace='rook-ceph' : the namespace of the CephCluster"
  echo "COMMANDS"
  echo "  help           : output help text"
  echo "  ceph <args>    : call a 'ceph' CLI command with arbitrary args"
  echo "  status         : show status of the CephCluster and its resources"
  echo "    -l, --long     : show long status"
  echo "  operator <subcommand>..."
  echo "    restart      : restart the Rook-Ceph operator"
  echo ""
}

function fail_error () {
  print_usage >&2
  echo "ERROR: $*" >&2
  exit 1
}

# return failure if the input is not a flag
function is_flag () {
  [[ "$1" == -* ]]
}

# return failure if the input (a flag value) doesn't exist
function val_exists () {
  local val="$1"
  [[ -n "$val" ]]
}

# fail with an error if the value is set
function flag_no_value () {
  local flag="$1"
  local value="$2"
  val_exists "$value" && fail_error "Flag '$flag' does not take a value"
}

# Usage: parse_flags 'set_value_function' "$@"
#
# This is a reusable function that will parse flags from the beginning of the "$@" (arguments) input
# until a non-flag argument is reached. It then returns the remaining arguments in a global env var
# called REMAINING_ARGS. For each parsed flag, it calls the user-specified callback function
# 'set_value_function' to set a config value.
#
# When a flag is reached, calls 'set_value_function' with the parsed flag and value as args 1 and 2.
# The 'set_value_function' must take 2 args in this order: flag, value
# The 'set_value_function' must return non-zero if the flag needs a value and was not given one.
#   Can copy-paste this line to achieve the above:  val_exists "$val" || return 1 # val should exist
# The 'set_value_function' must return zero in all other cases.
# The 'set_value_function' should call 'fail_error' if a flag is specified incorrectly.
# The 'set_value_function' should enforce flags that should have no values (use 'flag_no_value').
# The 'set_value_function' should record the config specified by the flag/value if it is valid.
# When a non-flag arg is reached, stop parsing and return the remaining args in REMAINING_ARGS.
REMAINING_ARGS=()
function parse_flags () {
  local set_value_function="$1"
  shift # pop set_value_function arg from the arg list
  while (( $# )); do
    arg="$1"
    shift
    FLAG=""
    VAL=""
    case "$arg" in
      --*=*) # long flag with a value, e.g., '--namespace=my-ns'
        FLAG="${arg%%=*}" # left of first equal
        VAL="${arg#*=}" # right of first equal
        val_exists "$VAL" || fail_error "Flag '$FLAG' does not specify a value"
        ;;
      --*) # long flag without a value, e.g., '--help' or '--namespace my-ns'
        FLAG="$arg"
        VAL=""
        ;;
      -*) # short flags
        if [[ "${#arg}" -eq 2 ]]; then # short flag without a value, e.g., '-h' or '-n my-ns'
          FLAG="$arg"
          VAL=""
        else # short flag with a value, e.g., '-nmy-ns', or '-n=my-ns'
          FLAG="${arg:0:2}" # first 2 chars
          VAL="${arg:2:${#arg}}" # remaining chars
          VAL="${VAL#*=}" # strip first equal from the value
        fi
        ;;
      *)
        # This is not a flag, so stop parsing and return the stored remaining args
        REMAINING_ARGS=("$arg" "$@") # store remaining args BEFORE shifting so we still have the
        break
        ;;
    esac
    is_flag "$VAL" && fail_error "Flag '$FLAG' value '$VAL' looks like another flag"
    # run the command with the current value, which may be empty
    if ! $set_value_function "$FLAG" "$VAL"; then
      # the flag needs a value, so grab the next arg to use as the value
      VAL="$1" || fail_error "Could not get value for flag '$FLAG'"
      shift
      # fail if the next arg looks like a flag and not a value
      is_flag "$VAL" && fail_error "Flag '$FLAG' value '$VAL' looks like another flag"
      # fail because the flag needs a value and value given is empty, e.g., --namespace ''
      val_exists "$VAL" || fail_error "Flag '$FLAG' does not specify a value"
      # run the command again with the next arg as its value
      if ! $set_value_function "$FLAG" "$VAL"; then
        fail_error "Flag '$FLAG' must have a value" # probably won't reach this, but just in case
      fi
    fi
  done
}

# call this at the end of a command tree when there should be no more inputs past a given point.
# Usage: end_of_command_parsing "$@" # where "$@" contains the remaining args
function end_of_command_parsing () {
  if [[ "$#" -gt 0 ]]; then
    fail_error "Extraneous arguments at end of input: $*"
  fi
}

####################################################################################################
# 'kubectl rook-ceph help' command
####################################################################################################

function run_help_command () {
  end_of_command_parsing "$@" # end of command tree
  print_usage
}

####################################################################################################
# 'kubectl rook-ceph ceph ...' command
####################################################################################################

function run_ceph_command () {
  # do not call end_of_command_parsing here because all remaining input is passed directly to 'ceph'
  echo "RUNNING CEPH COMMAND WITH ARGS '$*'"
}

####################################################################################################
# 'kubectl rook-ceph operator ...' commands
####################################################################################################

function run_operator_command () {
  [[ -z "${1:-""}" ]] && fail_error "Missing 'operator' subcommand"
  subcommand="$1"
  shift # remove the subcommand from the front of the arg list
  case "$subcommand" in
    restart)
      run_operator_restart_command "$@"
      ;;
    *)
      fail_error "'operator' subcommand '$subcommand' does not exist"
      ;;
  esac
}

function run_operator_restart_command () {
  end_of_command_parsing "$@" # end of command tree
  echo "restarting operator in namespace $NAMESPACE"
}

####################################################################################################
# 'kubectl rook-ceph status' command
####################################################################################################

# The status subcommand takes some args
LONG_STATUS='false'

# set_value_function for parsing flags for the status subcommand.
function parse_status_flag () {
  local flag="$1"
  local val="$2"
  case "$flag" in
    "-l"|"--long")
      flag_no_value "$flag" "$val"
      LONG_STATUS='true'
      ;;
    *)
      fail_error "Unsupported 'status' flag '$flag'"
      ;;
  esac
}

function run_status_command () {
  REMAINING_ARGS=()
  parse_flags 'parse_status_flag' "$@"
  end_of_command_parsing "${REMAINING_ARGS[@]}" # end of command tree

  if [[ "$LONG_STATUS" == "true" ]]; then
    echo "LONG STATUS"
  else
    echo "SHORT STATUS"
  fi
}

####################################################################################################
# MAIN COMMAND HANDLER (is effectively main)
####################################################################################################

function run_main_command () {
  local command="$1"
  shift # pop first arg off the front of the function arg list
  case "$command" in
    help)
      run_help_command "$@"
      ;;
    ceph)
      run_ceph_command "$@"
      ;;
    operator)
      run_operator_command "$@"
      ;;
    status)
      run_status_command "$@"
      ;;
    *)
      fail_error "Unknown command '$command'"
      ;;
  esac
}

####################################################################################################
# MAIN: PARSE MAIN ARGS AND CALL MAIN COMMAND HANDLER
####################################################################################################

# Default values for flag-controlled settings.
NAMESPACE='rook-ceph' # namespace of the cluster

# set_value_function for parsing flags for the main rook-ceph plugin.
function parse_main_flag () {
  local flag="$1"
  local val="$2"
  case "$flag" in
    "-n"|"--namespace")
      val_exists "$val" || return 1 # val should exist
      NAMESPACE="${val}"
      ;;
    "-h"|"--help")
      flag_no_value "$flag" "$val"
      run_help_command
      exit 0 # unique for the help flag; stop parsing everything and exit with success
      ;;
    "-v"|"--verbose")
      # just an example
      flag_no_value "$flag" "$val"
      echo "VERBOSE MODE"
      ;;
    *)
      fail_error "Flag $flag is not supported"
      ;;
  esac
}

REMAINING_ARGS=()
parse_flags 'parse_main_flag' "$@"

if [[ "${#REMAINING_ARGS[@]}" -eq 0 ]]; then
  fail_error "No command to run"
fi

run_main_command "${REMAINING_ARGS[@]}"
