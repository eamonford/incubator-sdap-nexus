# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM nexusjpl/alpine-pyspark:2.4.4

MAINTAINER Apache SDAP "dev@sdap.apache.org"

ARG CONDA_VERSION="4.7.12.1"
ARG CONDA_MD5="81c773ff87af5cfac79ab862942ab6b3"
ARG CONDA_DIR="/opt/conda"

ENV PYTHONPATH=${PYTHONPATH}:/opt/spark/python:/opt/spark/python/lib/py4j-0.10.7-src.zip:/opt/spark/python/lib/pyspark.zip/python:/usr/lib \
    NEXUS_SRC=/tmp/incubator-sdap-nexus \
    PROJ_LIB=/opt/conda/lib/python2.7/site-packages/pyproj/data	\
    PATH="$CONDA_DIR/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYSPARK_DRIVER_PYTHON=/opt/conda/bin/python \
    PYSPARK_PYTHON=/opt/conda/bin/python \
    LD_LIBRARY_PATH=/usr/lib 


RUN apk add --update --no-cache \
    bzip2 \
    gcc \
    git \
    mesa-gl \
    wget \
    curl \
    which \
    python3 \
    bash==4.4.19-r1 \
    libc-dev \
    libressl2.7-libcrypto 
RUN  apk upgrade musl

WORKDIR /tmp

RUN apk del libc6-compat
RUN apk --no-cache add wget zlib && \
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.30-r0/glibc-2.30-r0.apk && \
    apk add glibc-2.30-r0.apk && \
    ln -s /lib/libz.so.1 /usr/glibc-compat/lib/ && \
    ln -s /lib/libc.musl-x86_64.so.1 /usr/glibc-compat/lib && \
    ln -s /usr/lib/libgcc_s.so.1 /usr/glibc-compat/lib

# Install conda
RUN echo "**** install dev packages ****" && \
    apk add --no-cache --virtual .build-dependencies bash wget && \
    echo "**** get Miniconda ****" && \
    mkdir -p "$CONDA_DIR" && \
    wget "http://repo.continuum.io/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh" -O miniconda.sh && \
    echo "$CONDA_MD5  miniconda.sh" | md5sum -c && \
    \
    echo "**** install Miniconda ****" && \
    bash miniconda.sh -f -b -p "$CONDA_DIR" && \
    echo "export PATH=$CONDA_DIR/bin:\$PATH" > /etc/profile.d/conda.sh && \
    \
    echo "**** setup Miniconda ****" && \
    conda update --all --yes && \
    conda config --set auto_update_conda False && \
    \
    echo "**** cleanup ****" && \
    apk del --purge .build-dependencies && \
    rm -f miniconda.sh && \
    conda clean --all --force-pkgs-dirs --yes && \
    find "$CONDA_DIR" -follow -type f \( -iname '*.a' -o -iname '*.pyc' -o -iname '*.js.map' \) -delete && \
    \
    echo "**** finalize ****" && \
    mkdir -p "$CONDA_DIR/locks" && \
    chmod 777 "$CONDA_DIR/locks" && \
    conda update -n base conda



# Conda dependencies for nexus
RUN conda install python=2.7
RUN cd /usr/lib && ln -s libcom_err.so.2 libcom_err.so.3 && \ 
    cd /opt/conda/lib && \
    ln -s libnetcdf.so.11 libnetcdf.so.7 && \
    ln -s libkea.so.1.4.6 libkea.so.1.4.5 && \
    ln -s libhdf5_cpp.so.12 libhdf5_cpp.so.10 && \
    ln -s libjpeg.so.9 libjpeg.so.8

# Install nexusproto and nexus
ARG APACHE_NEXUSPROTO=https://github.com/apache/incubator-sdap-nexusproto.git
ARG APACHE_NEXUSPROTO_BRANCH=master

ARG REBUILD_CODE=0

COPY docker/nexus-webapp/install_nexusproto.sh ./install_nexusproto.sh
RUN /tmp/install_nexusproto.sh $APACHE_NEXUSPROTO $APACHE_NEXUSPROTO_BRANCH

COPY data-access /incubator-sdap-nexus/data-access
COPY analysis /incubator-sdap-nexus/analysis

WORKDIR /incubator-sdap-nexus/data-access
RUN python setup.py install

WORKDIR /incubator-sdap-nexus/analysis
RUN python setup.py install

# Upgrade kubernetes client jar from the default version
RUN rm /opt/spark/jars/kubernetes-client-4.1.2.jar
ADD https://repo1.maven.org/maven2/io/fabric8/kubernetes-client/4.4.2/kubernetes-client-4.4.2.jar /opt/spark/jars