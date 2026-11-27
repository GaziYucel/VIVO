#!/bin/bash

set -eo pipefail

# Print informational messages with INFO prefix
log_info() {
    echo "INFO: $*"
}
# Print error messages with ERROR prefix to stderr
log_error() {
    echo "ERROR: $*" >&2
}
# Download a sample file and adds to the WAR file
# $1 - path to WAR file
# $2 - url to the sample file
load_sample_data() {
  local war="$1"
  local url="$2"
  local entry="WEB-INF/resources/home-files/rdf/abox/filegraph/sample-data.n3"
  local tmp
  local result=1

  log_info "Starting to download sample data from $SAMPLE_DATA_REPO_URL"
  if [[ -z "$url" ]]; then
    log_error "SAMPLE_DATA_LOAD = $SAMPLE_DATA_LOAD given, but SAMPLE_DATA_REPO_URL not given"
    return 1
  fi

  if ! tmp=$(mktemp -d); then
    log_error "Could not create a temporary directory for sample data."
    return 1
  fi

  if ! mkdir -p -- "$tmp/$(dirname -- "$entry")"; then
    log_error "Could not create the temporary directory structure for sample data."
  elif curl -fL --show-error -o "$tmp/$entry" "$url" && [[ -s "$tmp/$entry" ]]; then
    if jar uf "$war" -C "$tmp" "$entry"; then
      log_info "Sample data downloaded and added to $war; it will be loaded at first start of Tomcat."
      result=0
    else
      log_error "Sample data downloaded, but adding the file to $war failed."
    fi
  else
    log_error "Sample data download failed or produced an empty file; $war was not modified."
  fi

  if ! rm -rf -- "$tmp"; then
    log_error "Could not remove temporary directory $tmp"
    result=1
  fi

  return "$result"
}
# Update property values in file runtime.properties with RUNTIME_PROPERTIES_UPDATE_LIST
update_runtime_properties_file() {
  local file="$RUNTIME_PROPERTIES_FILE"
  local key value key_regex escaped_value
  local -a sed_args=()

  for key in "${!RUNTIME_PROPERTIES_UPDATE_LIST[@]}"; do
    value="${RUNTIME_PROPERTIES_UPDATE_LIST[$key]}"

    # Skip if value is empty
    [ -z "$value" ] && continue

    # Escape the key for use as a regular expression.
    key_regex=${key//\\/\\\\}
    key_regex=${key_regex//./\\.}
    key_regex=${key_regex//\[/\\[}
    key_regex=${key_regex//\]/\\]}
    key_regex=${key_regex//\*/\\*}
    key_regex=${key_regex//\^/\\^}
    key_regex=${key_regex//\$/\\$}

    # Escape replacement characters for sed's | delimiter.
    escaped_value=${value//\\/\\\\}
    escaped_value=${escaped_value//&/\\&}
    escaped_value=${escaped_value//|/\\|}

    # Match optional whitespace and comment markers before the property.
    sed_args+=(
      -e "s|^([[:space:]]*)[#[:space:]]*${key_regex}[[:space:]]*=[[:space:]]*.*$|\1${key} = ${escaped_value}|"
    )
  done

  if ((${#sed_args[@]} == 0)); then
    return 0
  fi

  if ! sed -E -i.bak "${sed_args[@]}" "$file"; then
    log_error "Failed to update $file with given runtime properties"
    return 1
  fi

  log_info "Successfully updated $file with given runtime properties"

  return 0
}

# Allow debugging with `docker run -e VERBOSE=yes`
declare -rl VERBOSE="${VERBOSE:-no}"
case $VERBOSE in
  yes) set -x ;;
  no)  ;;
  *)   log_error "Invalid VERBOSE = $VERBOSE (must be yes or no)"; exit 1 ;;
esac

# env
declare -r TOMCAT_CONTEXT_PATH="${TOMCAT_CONTEXT_PATH-ROOT}"
declare -rl VIVO_RESET_HOME="${VIVO_RESET_HOME:-false}"
declare -rl RECONFIGURE="${RECONFIGURE:-false}"
declare -r VIVO_CONTAINER_VIVO_HOME="${VIVO_CONTAINER_VIVO_HOME:-/usr/local/vivo/home}"
declare -rl SAMPLE_DATA_LOAD="${SAMPLE_DATA_LOAD:-false}"
declare -rl SAMPLE_DATA_REPO_URL="${SAMPLE_DATA_REPO_URL:-}"
declare -r RUNTIME_PROPERTIES_FILE="$VIVO_CONTAINER_VIVO_HOME/config/runtime.properties"
declare -r APPLICATION_SETUP_FILE="$VIVO_CONTAINER_VIVO_HOME/config/applicationSetup.n3"

# Variables
declare -r VIVO_ARTIFACTS="${VIVO_ARTIFACTS:-/opt/vivo/artifacts}"
# CATALINA_HOME is provided by the tomcat base image (/usr/local/tomcat)
declare -r CATALINA_HOME="${CATALINA_HOME:-/usr/local/tomcat}"
declare -r TOMCAT_CONTEXT_MARKER="$CATALINA_HOME/webapps/.war-deployed"
declare -A RUNTIME_PROPERTIES_UPDATE_LIST

# Validate VIVO_CONTAINER_VIVO_HOME before deriving paths from it
if [[ "$VIVO_CONTAINER_VIVO_HOME" =~ ^/+$ ]]; then
  log_error "Invalid VIVO_CONTAINER_VIVO_HOME = '$VIVO_CONTAINER_VIVO_HOME'"
  exit 1
fi

# Deploy TOMCAT_CONTEXT_PATH and set TOMCAT_CONTEXT_MARKER after deployment
if [[ -n "$TOMCAT_CONTEXT_PATH" && "$TOMCAT_CONTEXT_PATH" =~ ^[[:alnum:]_.-]+$ ]]; then
  if [[ -f "$TOMCAT_CONTEXT_MARKER" ]]; then
    log_info "Deployment marker exists for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH, deployment skipped"
    [[ $SAMPLE_DATA_LOAD == true ]] && log_info "Already deployed, SAMPLE_DATA_LOAD = $SAMPLE_DATA_LOAD skipped"
  else
    if [[ ! -f "$CATALINA_HOME/webapps/ROOT.war" ]]; then
      log_error "ROOT.war not found for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH"
      exit 1
    fi

    if [[ "$TOMCAT_CONTEXT_PATH" == ROOT ]]; then
      log_info "ROOT.war deployed successfully for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH"
    else
      if ! mv -T -- "$CATALINA_HOME/webapps/ROOT.war" "$CATALINA_HOME/webapps/${TOMCAT_CONTEXT_PATH}.war"; then
        log_error "Failed renaming $CATALINA_HOME/webapps/ROOT.war to ${TOMCAT_CONTEXT_PATH}.war"
        exit 1
      fi
      log_info "$TOMCAT_CONTEXT_PATH.war deployed successfully for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH"
    fi

    if ! touch -- "$TOMCAT_CONTEXT_MARKER"; then
      log_error "Failed creating marker $TOMCAT_CONTEXT_MARKER for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH"
      exit 1
    else
      log_info "Deployment marker $TOMCAT_CONTEXT_MARKER set for TOMCAT_CONTEXT_PATH = $TOMCAT_CONTEXT_PATH"
    fi

    if [[ $SAMPLE_DATA_LOAD == true ]]; then
      load_sample_data "$CATALINA_HOME/webapps/${TOMCAT_CONTEXT_PATH}.war" "$SAMPLE_DATA_REPO_URL"
    fi
  fi
elif [[ -n "$TOMCAT_CONTEXT_PATH" ]]; then
  log_error "Invalid TOMCAT_CONTEXT_PATH = '$TOMCAT_CONTEXT_PATH' (only alphanumeric, _ and - allowed)"
  exit 1
fi

# Reset home directory if VIVO_RESET_HOME=true
if [[ "$VIVO_RESET_HOME" = "true" ]]; then
  log_info "Clearing VIVO HOME $VIVO_CONTAINER_VIVO_HOME"
  if [ -d "$VIVO_CONTAINER_VIVO_HOME" ]; then
    find "$VIVO_CONTAINER_VIVO_HOME" -mindepth 1 -delete
  fi
fi

# Copy home config if not exists
if [ ! -d "$VIVO_CONTAINER_VIVO_HOME/config" ]; then
  log_info "Copying home config directory to $VIVO_CONTAINER_VIVO_HOME/config"
  mkdir -p "$VIVO_CONTAINER_VIVO_HOME"
  cp -r "$VIVO_ARTIFACTS/config" "$VIVO_CONTAINER_VIVO_HOME/config"
fi

# Copy configuration file from template
# $1 - destination path
# $2 - template source path
copy_config_from_template() {
  local destination="$1"
  local template="$2"

  if [ ! -f "$template" ]; then
    log_error "$template does not exist"
    return 1
  fi

  if [ -f "$destination" ]; then
    log_info "Overwriting $destination with $template (RECONFIGURE=true)"
  else
    log_info "Copying $template to $destination"
  fi

  cp "$template" "$destination"

  return 0
}
if [ ! -f "$RUNTIME_PROPERTIES_FILE" ] || [ "$RECONFIGURE" = "true" ]; then
  copy_config_from_template "$RUNTIME_PROPERTIES_FILE" "$VIVO_CONTAINER_VIVO_HOME/config/example.runtime.properties" || exit 1
fi
if [ ! -f "$APPLICATION_SETUP_FILE" ] || [ "$RECONFIGURE" = "true" ]; then
  copy_config_from_template "$APPLICATION_SETUP_FILE" "$VIVO_CONTAINER_VIVO_HOME/config/example.applicationSetup.n3" || exit 1
fi

# Update SEARCH_ENGINE_TYPE in applicationSetup.n3
update_search_engine_type() {
  local file="$1"
  local engine="$2"
  local -a sed_args
  local -a elastic_sed_args
  local -a open_sed_args

  # Normalize to Solr
  sed_args=(
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*:wraps[[:blank:]]+):elasticSearchEngine([[:blank:]]+[.])$|\1:solrSearchEngine\2|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*):elasticSearchEngine([[:blank:]]*)(.*)$|\1:solrSearchEngine\2\3|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*a[[:blank:]]+)vitroWebapp:searchengine[.]elastic[.]ElasticSearchEngine(.*)$|\1vitroWebapp:searchengine.solr.SolrSearchEngine\2|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*:wraps[[:blank:]]+):openSearchEngine([[:blank:]]+[.])$|\1:solrSearchEngine\2|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*):openSearchEngine([[:blank:]]*)(.*)$|\1:solrSearchEngine\2\3|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*a[[:blank:]]+)vitroWebapp:searchengine[.]open[.]OpenSearchEngine(.*)$|\1vitroWebapp:searchengine.solr.SolrSearchEngine\2|'
  )

  # ElasticSearch
  elastic_sed_args=(
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*:wraps[[:blank:]]+):solrSearchEngine([[:blank:]]+[.])$|\1:elasticSearchEngine\2|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*):solrSearchEngine([[:blank:]]*)(.*)$|\1:elasticSearchEngine\2\3|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*a[[:blank:]]+)vitroWebapp:searchengine[.]solr[.]SolrSearchEngine(.*)$|\1vitroWebapp:searchengine.elastic.ElasticSearchEngine\2|'
  )

  # OpenSearch
  open_sed_args=(
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*:wraps[[:blank:]]+):solrSearchEngine([[:blank:]]+[.])$|\1:openSearchEngine\2|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*):solrSearchEngine([[:blank:]]*)(.*)$|\1:openSearchEngine\2\3|'
    -e '/^[[:blank:]]*#/!s|^([[:blank:]]*a[[:blank:]]+)vitroWebapp:searchengine[.]solr[.]SolrSearchEngine(.*)$|\1vitroWebapp:searchengine.open.OpenSearchEngine\2|'
  )

  # Append the search-engine-specific conversions
  case "$engine" in
    elasticsearch) sed_args+=("${elastic_sed_args[@]}") ;;
    opensearch)    sed_args+=("${open_sed_args[@]}") ;;
  esac

  if ! sed -E -i.bak "${sed_args[@]}" "$file"; then
    log_error "Could not update $file SEARCH_ENGINE_TYPE = $engine"
    return 1
  fi

  log_info "Successfully updated $file SEARCH_ENGINE_TYPE = $engine"

  return 0
}
if [[ -n "${SEARCH_ENGINE_TYPE:-}" ]]; then
  if [[ ! "$SEARCH_ENGINE_TYPE" =~ ^(solr|elasticsearch|opensearch)$ ]]; then
    log_error "Invalid SEARCH_ENGINE_TYPE = $SEARCH_ENGINE_TYPE (must be solr, elasticsearch, or opensearch)"
  else
    log_info "Configuring $APPLICATION_SETUP_FILE SEARCH_ENGINE_TYPE = $SEARCH_ENGINE_TYPE"
    if ! update_search_engine_type "$APPLICATION_SETUP_FILE" "$SEARCH_ENGINE_TYPE"; then
      log_error "$APPLICATION_SETUP_FILE SEARCH_ENGINE_TYPE = $SEARCH_ENGINE_TYPE could not be updated"
    fi
  fi
fi

# Update properties in runtime.properties and save to file

if [[ -n "${SEARCH_ENGINE_URL:-}" ]]; then
  search_engine_url_property="vitro.local.solr.url"
  if [[ "$SEARCH_ENGINE_TYPE" = "elasticsearch" || "$SEARCH_ENGINE_TYPE" = "opensearch" ]]; then
    search_engine_url_property="vitro.local.searchengine.url"
  fi
  log_info "Setting runtime.properties $search_engine_url_property = $SEARCH_ENGINE_URL"
  RUNTIME_PROPERTIES_UPDATE_LIST["$search_engine_url_property"]="$SEARCH_ENGINE_URL"
fi

if [ -n "${SEARCH_ENGINE_USERNAME:-}" ]; then
  log_info "Setting runtime.properties vitro.local.searchengine.username = $SEARCH_ENGINE_USERNAME"
  RUNTIME_PROPERTIES_UPDATE_LIST["vitro.local.searchengine.username"]="$SEARCH_ENGINE_USERNAME"
fi

if [ -n "${SEARCH_ENGINE_PASSWORD:-}" ]; then
  log_info "Setting runtime.properties vitro.local.searchengine.password = ***MASKED***"
  RUNTIME_PROPERTIES_UPDATE_LIST["vitro.local.searchengine.password"]="$SEARCH_ENGINE_PASSWORD"
fi

if [ -n "${EMAIL_SMTP_HOST:-}" ]; then
  log_info "Setting runtime.properties email.smtpHost = $EMAIL_SMTP_HOST"
  RUNTIME_PROPERTIES_UPDATE_LIST["email.smtpHost"]="$EMAIL_SMTP_HOST"
fi

if [ -n "${EMAIL_PORT:-}" ]; then
  log_info "Setting runtime.properties email.port = $EMAIL_PORT"
  RUNTIME_PROPERTIES_UPDATE_LIST["email.port"]="$EMAIL_PORT"
fi

if [ -n "${EMAIL_REPLY_TO:-}" ]; then
  log_info "Setting runtime.properties email.replyTo = $EMAIL_REPLY_TO"
  RUNTIME_PROPERTIES_UPDATE_LIST["email.replyTo"]="$EMAIL_REPLY_TO"
fi

if [ -n "${EMAIL_USERNAME:-}" ]; then
  log_info "Setting runtime.properties email.username = $EMAIL_USERNAME"
  RUNTIME_PROPERTIES_UPDATE_LIST["email.username"]="$EMAIL_USERNAME"
fi

if [ -n "${EMAIL_PASSWORD:-}" ]; then
  log_info "Setting runtime.properties email.password = ***MASKED***"
  RUNTIME_PROPERTIES_UPDATE_LIST["email.password"]="$EMAIL_PASSWORD"
fi

if [ -n "${ROOT_USER_ADDRESS:-}" ]; then
  log_info "Setting runtime.properties rootUser.emailAddress = $ROOT_USER_ADDRESS"
  RUNTIME_PROPERTIES_UPDATE_LIST["rootUser.emailAddress"]="$ROOT_USER_ADDRESS"
fi

if [ -n "${DEFAULT_NAMESPACE:-}" ]; then
  log_info "Setting runtime.properties Vitro.defaultNamespace = $DEFAULT_NAMESPACE"
  RUNTIME_PROPERTIES_UPDATE_LIST["Vitro.defaultNamespace"]="$DEFAULT_NAMESPACE"
fi

if [ -n "${SELF_ID_MATCHING_PROPERTY:-}" ]; then
  log_info "Setting runtime.properties selfEditing.idMatchingProperty = $SELF_ID_MATCHING_PROPERTY"
  RUNTIME_PROPERTIES_UPDATE_LIST["selfEditing.idMatchingProperty"]="$SELF_ID_MATCHING_PROPERTY"
fi

if [[ "$LANGUAGE_FILTER_ENABLED" == "true" || "$LANGUAGE_FILTER_ENABLED" == "false" ]]; then
  log_info "Setting runtime.properties RDFService.languageFilter = $LANGUAGE_FILTER_ENABLED"
  RUNTIME_PROPERTIES_UPDATE_LIST["RDFService.languageFilter"]="$LANGUAGE_FILTER_ENABLED"
elif [[ -n "$LANGUAGE_FILTER_ENABLED" ]]; then
  log_error "Invalid LANGUAGE_FILTER_ENABLED = $LANGUAGE_FILTER_ENABLED (must be true or false)"
fi

if [[ "$FORCE_LOCALE" == "true" || "$FORCE_LOCALE" == "false" ]]; then
  log_info "Setting runtime.properties languages.forceLocale = $FORCE_LOCALE"
  RUNTIME_PROPERTIES_UPDATE_LIST["languages.forceLocale"]="$FORCE_LOCALE"
elif [[ -n "$FORCE_LOCALE" ]]; then
  log_error "Invalid FORCE_LOCALE = $FORCE_LOCALE (must be true or false)"
fi

if [ -n "${SELECTABLE_LOCALES:-}" ]; then
  log_info "Setting runtime.properties languages.selectableLocales = $SELECTABLE_LOCALES"
  RUNTIME_PROPERTIES_UPDATE_LIST["languages.selectableLocales"]="$SELECTABLE_LOCALES"
fi

update_runtime_properties_file

# Configure TDB file mode in JAVA_OPTS based on VIVO_TDB_FILE_MODE
if [[ -n "$VIVO_TDB_FILE_MODE" && ( "$VIVO_TDB_FILE_MODE" == direct || "$VIVO_TDB_FILE_MODE" == mapped ) ]]; then
  CLEAN_JAVA_OPTS="$(printf '%s\n' "${JAVA_OPTS:-}" | sed -E 's/(^|[[:space:]]+)-Dtdb:fileMode=[^[:space:]]*//g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [ -n "$CLEAN_JAVA_OPTS" ]; then
    export JAVA_OPTS="$CLEAN_JAVA_OPTS -Dtdb:fileMode=$VIVO_TDB_FILE_MODE"
  else
    export JAVA_OPTS="-Dtdb:fileMode=$VIVO_TDB_FILE_MODE"
  fi
  log_info "TDB file mode = $VIVO_TDB_FILE_MODE configured JAVA_OPTS = $JAVA_OPTS"
else
  log_error "Invalid VIVO_TDB_FILE_MODE = $VIVO_TDB_FILE_MODE (must be direct or mapped)"
  exit 1
fi

# Configure Tomcat HTTP connector port based on VIVO_CONTAINER_PORT
if [[ -n "${VIVO_CONTAINER_PORT}" && "${VIVO_CONTAINER_PORT}" != 8080 ]]; then
  log_info "Configuring Tomcat HTTP connector port to $VIVO_CONTAINER_PORT in $CATALINA_HOME/conf/server.xml"
  sed -i -E "s/(<Connector[^>]*[[:space:]]port=\")[0-9]+(\"[^>]*protocol=\"HTTP\/1\.1\")/\1${VIVO_CONTAINER_PORT}\2/" "$CATALINA_HOME/conf/server.xml"
fi

# Reset VIVO Solr core
reset_solr_index() {
  local solr_url="http://localhost:8983/solr/vivocore/update?commit=true"
  local -a curl_args=(
    -H "Content-Type: text/xml"
    --data-binary "<delete><query>*:*</query></delete>"
  )

  if curl --fail-with-body -sS "${curl_args[@]}" "$solr_url"; then
    log_info "Solr delete request succeeded"
  else
    local curl_status=$?
    log_error "Solr delete request failed (curl exit code $curl_status)"
    return "$curl_status"
  fi
}
if [[ "$SOLR_RESET_CORE" == "true" ]]; then
  log_info "Clearing VIVO Solr core = $SOLR_RESET_CORE"
  reset_solr_index
elif [[ -n "$SOLR_RESET_CORE" && "$SOLR_RESET_CORE" != "false" ]]; then
  log_error "Invalid SOLR_RESET_CORE = $SOLR_RESET_CORE (must be true or false)"
fi

exec catalina.sh run
