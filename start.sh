#!/bin/bash

set -e

# allow easier debugging with `docker run -e VERBOSE=yes`
#if [[ $SOLR_VERBOSE == "true" ]]; then
  set -x
#fi

# allow easier reset home with `docker run -e VIVO_RESET_HOME=true`
if [[ $VIVO_RESET_HOME == "true" ]]; then
  echo "Clearing VIVO HOME $VIVO_CONTAINER_VIVO_HOME"
  rm -rf "${VIVO_CONTAINER_VIVO_HOME:?}"/*
fi

# copy home config if not exists
if [ ! -d "$VIVO_CONTAINER_VIVO_HOME"/config ]; then
  echo "Copying home config directory to $VIVO_CONTAINER_VIVO_HOME/config"
  cp -r "$VIVO_HOST_VIVO_HOME"/config "$VIVO_CONTAINER_VIVO_HOME/config"
fi

# copy runtime.properties if it does not already exist in target home directory or RECONFIGURE=true
if [ -f "$VIVO_CONTAINER_VIVO_HOME/config/example.runtime.properties" ]; then
  if [ ! -f "$VIVO_CONTAINER_VIVO_HOME/config/runtime.properties" ] || [ "$RECONFIGURE" = "true" ]
  then
    echo "Copying example.runtime.properties to $VIVO_CONTAINER_VIVO_HOME/config/runtime.properties"
    cp "$VIVO_CONTAINER_VIVO_HOME/config/example.runtime.properties" "$VIVO_CONTAINER_VIVO_HOME/config/runtime.properties"

    # Template all deployment variables into runtime.properties
    echo "Templating runtime.properties with environment configuration..."

    # languages.selectableLocales
    if [ -n "$SELECTABLE_LOCALES" ]; then
      sed -i "s#^[#[:space:]]*languages\.selectableLocales[[:space:]]*=.*#languages.selectableLocales = $SELECTABLE_LOCALES#g" "$VIVO_CONTAINER_VIVO_HOME/config/runtime.properties"
    fi

  else
    echo "Using existing $VIVO_CONTAINER_VIVO_HOME/config/runtime.properties"
  fi
fi

# copy applicationSetup.n3 if it does not already exist in target home directory
if [ -f "$VIVO_CONTAINER_VIVO_HOME/config/example.applicationSetup.n3" ]; then
  if [ ! -f "$VIVO_CONTAINER_VIVO_HOME/config/applicationSetup.n3" ]
  then
    echo "Copying example.applicationSetup.n3 to $VIVO_CONTAINER_VIVO_HOME/config/applicationSetup.n3"
    cp "$VIVO_CONTAINER_VIVO_HOME/config/example.applicationSetup.n3" "$VIVO_CONTAINER_VIVO_HOME/config/applicationSetup.n3"
  else
    echo "Using existing $VIVO_CONTAINER_VIVO_HOME/config/applicationSetup.n3"
  fi
fi

# Load sample data if requested
#if [[ "$LOAD_SAMPLE_DATA" = "true" ]]; then
#  echo "Loading sample data from $SAMPLE_DATA_REPO_URL (branch: $SAMPLE_DATA_BRANCH, directory: $SAMPLE_DATA_DIRECTORY)..."
#  # Sample data integration if repository tools/scripts or RDF files are handled
#  # (e.g. cloning sample data into VIVO home rdf directory if applicable)
#  if [ -d "$VIVO_CONTAINER_VIVO_HOME" ]; then
#    SAMPLE_TARGET_DIR="$VIVO_CONTAINER_VIVO_HOME/rdf/abox/sample"
#    mkdir -p "$SAMPLE_TARGET_DIR"
#    if command -v git &> /dev/null; then
#      TMP_SAMPLE_CLONE="/tmp/sample-data-clone"
#      rm -rf "$TMP_SAMPLE_CLONE"
#      git clone --branch "$SAMPLE_DATA_BRANCH" "$SAMPLE_DATA_REPO_URL" "$TMP_SAMPLE_CLONE"
#      if [ -d "$TMP_SAMPLE_CLONE/$SAMPLE_DATA_DIRECTORY" ]; then
#        cp -r "$TMP_SAMPLE_CLONE/$SAMPLE_DATA_DIRECTORY/"* "$SAMPLE_TARGET_DIR/"
#        echo "Sample data successfully copied to $SAMPLE_TARGET_DIR"
#      else
#        echo "Warning: Sample data directory $SAMPLE_DATA_DIRECTORY not found in repository clone."
#      fi
#      rm -rf "$TMP_SAMPLE_CLONE"
#    else
#      echo "Warning: git command not found, cannot clone sample data repo."
#    fi
#  fi
#fi
#
# Note on TOMCAT_CONTEXT_PATH: if TOMCAT_CONTEXT_PATH is set and is not ROOT, rename ROOT.war accordingly
#if [ -n "$TOMCAT_CONTEXT_PATH" ] && [ "$TOMCAT_CONTEXT_PATH" != "ROOT" ]; then
#  if [ -f "/usr/local/tomcat/webapps/ROOT.war" ]; then
#    mv /usr/local/tomcat/webapps/ROOT.war "/usr/local/tomcat/webapps/${TOMCAT_CONTEXT_PATH}.war"
#    echo "Renamed ROOT.war to ${TOMCAT_CONTEXT_PATH}.war per TOMCAT_CONTEXT_PATH=$TOMCAT_CONTEXT_PATH"
#  fi
#fi

catalina.sh run
