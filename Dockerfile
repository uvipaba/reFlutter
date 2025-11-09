FROM ubuntu:22.04

ARG HASH_PATCH
ARG COMMIT

ENV DEPOT_TOOLS_PATH=/depot_tools
ENV TEMP_ENGINE=/engine
ENV ENGINE_PATH=/customEngine
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/depot_tools
ENV WAIT=4
ENV HASH_PATCH=$HASH_PATCH
ENV COMMIT=$COMMIT
ENV GCLIENT_NUM_JOBS=1
ENV GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1

# Install only essential dependencies
RUN apt-get update && \
  DEBIAN_FRONTEND="noninteractive" apt-get install -y \
  git wget curl unzip \
  python3-pip python3 \
  python3-pkgconfig default-jre default-jdk ninja-build && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  mkdir /t

# Retry wrapper for gclient sync
RUN echo '#!/bin/bash\n\
MAX_RETRIES=5\n\
RETRY_DELAY=300\n\
ATTEMPT=1\n\
\n\
while [ $ATTEMPT -le $MAX_RETRIES ]; do\n\
  echo "Attempt $ATTEMPT of $MAX_RETRIES..."\n\
  if gclient sync; then\n\
    echo "gclient sync successful!"\n\
    exit 0\n\
  else\n\
    EXIT_CODE=$?\n\
    if [ $ATTEMPT -lt $MAX_RETRIES ]; then\n\
      echo "gclient sync failed with exit code $EXIT_CODE"\n\
      echo "Waiting ${RETRY_DELAY} seconds before retry..."\n\
      sleep $RETRY_DELAY\n\
      RETRY_DELAY=$((RETRY_DELAY + 300))\n\
    fi\n\
    ATTEMPT=$((ATTEMPT + 1))\n\
  fi\n\
done\n\
\n\
echo "gclient sync failed after $MAX_RETRIES attempts"\n\
exit 1' > /usr/local/bin/gclient-sync-retry && \
  chmod +x /usr/local/bin/gclient-sync-retry

ENTRYPOINT ["/bin/bash", "-c", "set -e && \
  cd /t && \
  echo '=== Installing ReFlutter ===' && \
  pip3 install wheel && \
  pip3 install . && \
  \
  echo '=== Cloning depot_tools ===' && \
  rm -rf ${DEPOT_TOOLS_PATH} 2> /dev/null && \
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git ${DEPOT_TOOLS_PATH} && \
  \
  echo '=== Cloning Flutter engine ===' && \
  rm -rf ${TEMP_ENGINE} 2> /dev/null && \
  git clone --depth 1 https://github.com/flutter/flutter.git ${TEMP_ENGINE} && \
  \
  echo '=== Setting up engine directory ===' && \
  rm -rf ${ENGINE_PATH} 2> /dev/null && \
  mkdir -p ${ENGINE_PATH} && \
  cd ${TEMP_ENGINE} && \
  git config --global user.email 'reflutter@example.com' && \
  git config --global user.name 'reflutter' && \
  \
  echo '=== Fetching specific commit ===' && \
  git fetch --depth 1 origin ${COMMIT} && \
  git reset --hard FETCH_HEAD && \
  \
  echo '=== Applying ReFlutter patches ===' && \
  reflutter -b ${HASH_PATCH} -p && \
  echo 'reflutter' > REFLUTTER && \
  git add . && \
  git commit -am 'reflutter' && \
  \
  echo '=== Setting up gclient ===' && \
  cd ${ENGINE_PATH} && \
  echo 'solutions = [{\"managed\": False,\"name\": \".\",\"url\": \"'${TEMP_ENGINE}'\",\"custom_deps\": {},\"deps_file\": \"DEPS\",\"safesync_url\": \"\",},]' > .gclient && \
  \
  echo '=== Running gclient sync (this takes 30-60 minutes) ===' && \
  gclient-sync-retry && \
  \
  echo '=== Applying patches again ===' && \
  reflutter -b ${HASH_PATCH} -p && \
  \
  echo '=== Waiting for manual changes (${WAIT} seconds) ===' && \
  sleep $WAIT && \
  \
  echo '=== Checking disk space ===' && \
  df -h && \
  \
  echo '=== Building ARM64 only ===' && \
  engine/src/flutter/tools/gn --no-goma --android --android-cpu=arm64 --runtime-mode=release && \
  ninja -C engine/src/out/android_release_arm64 && \
  \
  echo '=== Copying output ===' && \
  if [ -f engine/src/out/android_release_arm64/lib.stripped/libflutter.so ]; then \
    cp engine/src/out/android_release_arm64/lib.stripped/libflutter.so /t/libflutter_arm64.so && \
    echo '✅ SUCCESS! libflutter_arm64.so created' && \
    ls -lh /t/libflutter_arm64.so; \
  else \
    echo '❌ ERROR: libflutter.so not found' && \
    exit 1; \
  fi && \
  \
  echo '=== Build complete! ===' && \
  tail -f /dev/null"]

CMD ["bash"]
